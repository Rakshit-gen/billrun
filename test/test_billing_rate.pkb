create or replace package body test_billing_rate as

  function ts(p_text varchar2) return date is
  begin
    return to_date(p_text, 'YYYY-MM-DD HH24:MI:SS');
  end ts;

  procedure rate is
    l_n pls_integer;
  begin
    l_n := billing_rate.rate_pending;
  end rate;

  procedure setup is
  begin
    test_fixture.setup;
  end setup;

  procedure international is
    l_id  cdrs.cdr_id%type := test_fixture.add_cdr('VOICE', '33140000000', ts('2031-01-06 10:00:00'), 61);
    l     cdrs%rowtype;
  begin
    rate;
    l := test_fixture.cdr(l_id);
    ut.expect(l.status).to_equal('RATED');
    ut.expect(l.dest_class).to_equal('INTL');
    ut.expect(l.rated_units).to_equal(120);
    ut.expect(l.included_units).to_equal(0);
    ut.expect(l.amount).to_equal(2);
    ut.expect(l.cycle_id).to_equal(test_fixture.g_jan);
    ut.expect(l.late).to_equal('N');
  end international;

  procedure off_peak is
    l_id  cdrs.cdr_id%type := test_fixture.add_cdr('VOICE', '441614960000', ts('2031-01-06 21:00:00'), 61);
    l     cdrs%rowtype;
  begin
    rate;
    l := test_fixture.cdr(l_id);
    ut.expect(l.peak).to_equal('N');
    ut.expect(l.rated_units).to_equal(61);
    ut.expect(l.included_units).to_equal(61);
    ut.expect(l.amount).to_equal(0);
  end off_peak;

  procedure allowance_split is
    -- Added out of order: rating goes by time, not by arrival.
    l_third   cdrs.cdr_id%type := test_fixture.add_cdr('VOICE', '441614960000', ts('2031-01-08 10:00:00'), 60);
    l_second  cdrs.cdr_id%type := test_fixture.add_cdr('VOICE', '441614960000', ts('2031-01-07 10:00:00'), 120);
    l_first   cdrs.cdr_id%type := test_fixture.add_cdr('VOICE', '441614960000', ts('2031-01-06 10:00:00'), 500);
    l         cdrs%rowtype;
    l_used    allowance_usage.used_units%type;
  begin
    rate;
    -- 500 seconds at peak is billed as 9 minutes, 540 of the 600 included.
    l := test_fixture.cdr(l_first);
    ut.expect(l.rated_units).to_equal(540);
    ut.expect(l.included_units).to_equal(540);
    ut.expect(l.amount).to_equal(0);
    -- The last 60 seconds of allowance, then a minute at 0.10.
    l := test_fixture.cdr(l_second);
    ut.expect(l.included_units).to_equal(60);
    ut.expect(l.charged_units).to_equal(60);
    ut.expect(l.amount).to_equal(0.1);
    l := test_fixture.cdr(l_third);
    ut.expect(l.included_units).to_equal(0);
    ut.expect(l.amount).to_equal(0.1);

    select used_units into l_used
      from allowance_usage
     where subscriber_id = test_fixture.g_subscriber
       and cycle_id = test_fixture.g_jan
       and service = 'VOICE';
    ut.expect(l_used).to_equal(600);
  end allowance_split;

  procedure allowance_per_cycle is
    l_jan  cdrs.cdr_id%type := test_fixture.add_cdr('VOICE', '441614960000', ts('2031-01-06 10:00:00'), 600);
    l_feb  cdrs.cdr_id%type := test_fixture.add_cdr('VOICE', '441614960000', ts('2031-02-03 10:00:00'), 600);
  begin
    rate;
    ut.expect(test_fixture.cdr(l_jan).included_units).to_equal(600);
    ut.expect(test_fixture.cdr(l_feb).included_units).to_equal(600);
    ut.expect(test_fixture.cdr(l_feb).cycle_id).to_equal(test_fixture.g_feb);
  end allowance_per_cycle;

  procedure plan_change is
    l_before  cdrs.cdr_id%type;
    l_after   cdrs.cdr_id%type;

    -- The plan whose tariff a record was rated on.
    function plan_of(p_cdr_id cdrs.cdr_id%type) return plans.plan_id%type is
      l_tariff  tariffs.tariff_id%type := test_fixture.cdr(p_cdr_id).tariff_id;
      l_plan    plans.plan_id%type;
    begin
      select plan_id into l_plan from tariffs where tariff_id = l_tariff;
      return l_plan;
    end plan_of;
  begin
    billing_admin.change_plan(test_fixture.g_subscriber, 'TEST2', date '2031-01-11');
    l_before := test_fixture.add_cdr('SMS', '447700900123', ts('2031-01-10 23:59:59'), 1);
    l_after := test_fixture.add_cdr('SMS', '447700900123', ts('2031-01-11 00:00:00'), 1);
    rate;
    ut.expect(plan_of(l_before)).to_equal(billing_admin.plan_id('TEST1'));
    ut.expect(plan_of(l_after)).to_equal(billing_admin.plan_id('TEST2'));
  end plan_change;

  procedure tariff_change is
    l_plan    plans.plan_id%type := billing_admin.plan_id('TEST1');
    l_before  cdrs.cdr_id%type;
    l_after   cdrs.cdr_id%type;
  begin
    update tariffs
       set valid_to = date '2031-01-15'
     where plan_id = l_plan and service = 'VOICE' and dest_class = 'INTL';
    insert into tariffs (plan_id, service, dest_class, period, first_units, next_units, price, price_units, valid_from)
    values (l_plan, 'VOICE', 'INTL', 'ANY', 60, 60, 2.00, 60, date '2031-01-15');
    l_before := test_fixture.add_cdr('VOICE', '33140000000', ts('2031-01-14 12:00:00'), 61);
    l_after := test_fixture.add_cdr('VOICE', '33140000000', ts('2031-01-15 12:00:00'), 61);
    rate;
    ut.expect(test_fixture.cdr(l_before).amount).to_equal(2);
    ut.expect(test_fixture.cdr(l_after).amount).to_equal(4);
  end tariff_change;

  procedure late_call is
    l_id  cdrs.cdr_id%type := test_fixture.add_cdr('VOICE', '33140000000', ts('2031-01-30 12:00:00'), 60);
    l     cdrs%rowtype;
  begin
    update bill_cycles set status = 'BILLED', billed_at = systimestamp where cycle_id = test_fixture.g_jan;
    rate;
    l := test_fixture.cdr(l_id);
    ut.expect(l.status).to_equal('RATED');
    ut.expect(l.cycle_id).to_equal(test_fixture.g_feb);
    ut.expect(l.late).to_equal('Y');
  end late_call;

  procedure failures is
    l_local    cdrs.cdr_id%type := test_fixture.add_cdr('VOICE', '442079460000', ts('2031-01-06 10:00:00'), 60);
    l_nowhere  cdrs.cdr_id%type := test_fixture.add_cdr('VOICE', '8613800000000', ts('2031-01-06 10:00:00'), 60);
    l_april    cdrs.cdr_id%type := test_fixture.add_cdr('VOICE', '441614960000', ts('2031-04-02 10:00:00'), 60);
    l_early    cdrs.cdr_id%type := test_fixture.add_cdr('VOICE', '441614960000', ts('2030-12-31 10:00:00'), 60);
  begin
    rate;
    ut.expect(test_fixture.cdr(l_local).status).to_equal('FAILED');
    ut.expect(test_fixture.cdr(l_local).fail_reason).to_equal(
      'plan ' || billing_admin.plan_id('TEST1') || ' has no VOICE tariff for LOCAL at peak');
    ut.expect(test_fixture.cdr(l_nowhere).fail_reason).to_equal('no destination matches 8613800000000');
    ut.expect(test_fixture.cdr(l_april).fail_reason).to_equal('no open bill cycle for 2031-04-02');
    ut.expect(test_fixture.cdr(l_early).fail_reason).to_equal('not on any plan on 2030-12-31');
  end failures;

  procedure rerate is
    l_intl   cdrs.cdr_id%type := test_fixture.add_cdr('VOICE', '33140000000', ts('2031-01-06 10:00:00'), 61);
    l_local  cdrs.cdr_id%type := test_fixture.add_cdr('VOICE', '441614960000', ts('2031-01-07 10:00:00'), 300);
    l_used   allowance_usage.used_units%type;
  begin
    rate;
    ut.expect(test_fixture.cdr(l_intl).amount).to_equal(2);
    update tariffs
       set price = 1.50
     where plan_id = billing_admin.plan_id('TEST1') and service = 'VOICE' and dest_class = 'INTL';
    ut.expect(billing_rate.rerate_cycle(test_fixture.g_jan)).to_equal(2);
    ut.expect(test_fixture.cdr(l_intl).status).to_equal('NEW');
    rate;
    ut.expect(test_fixture.cdr(l_intl).amount).to_equal(3);
    -- Counted once, not twice.
    select used_units into l_used
      from allowance_usage
     where subscriber_id = test_fixture.g_subscriber and cycle_id = test_fixture.g_jan and service = 'VOICE';
    ut.expect(l_used).to_equal(300);
  end rerate;

  procedure rerate_billed is
    l_n pls_integer;
  begin
    l_n := billing_run.bill_cycle(test_fixture.g_jan);
    l_n := billing_rate.rerate_cycle(test_fixture.g_jan);
  end rerate_billed;

  -- Rates a month of made up traffic both ways, small batches for the
  -- fast one so allowances carry across batch boundaries, and compares
  -- every field of every record.
  procedure fast_matches_slow is
    type t_sig is table of varchar2(400) index by pls_integer;
    l_slow        t_sig;
    l_n           pls_integer;
    l_rated       pls_integer;
    l_mismatches  pls_integer := 0;
    l_used_slow   number;
    l_used_fast   number;

    procedure snapshot(p_into in out nocopy t_sig) is
    begin
      p_into.delete;
      for r in (select cdr_id,
                       status || '|' || cycle_id || '|' || late || '|' || dest_class || '|' || peak || '|'
                       || tariff_id || '|' || rated_units || '|' || included_units || '|' || charged_units
                       || '|' || amount || '|' || fail_reason as sig
                  from cdrs
                 where started_at >= date '2031-01-01' and started_at < date '2031-02-01') loop
        p_into(r.cdr_id) := r.sig;
      end loop;
    end snapshot;
  begin
    billing_demo.add_customers(30, date '2031-01-01', 7);
    billing_demo.stage_usage('demo.csv', 2000, date '2031-01-01', 7, 0.02);
    l_n := billing_load.load_staged;
    select count(*) into l_rated from cdrs where started_at >= date '2031-01-01' and started_at < date '2031-02-01';
    ut.expect(l_rated).to_be_greater_than(1900);

    l_n := billing_rate.rate_pending_slow;
    ut.expect(l_n).to_equal(l_rated);
    snapshot(l_slow);
    select sum(used_units) into l_used_slow from allowance_usage where cycle_id = test_fixture.g_jan;

    update cdrs
       set status = 'NEW', cycle_id = null, late = 'N', dest_class = null, peak = null, tariff_id = null,
           rated_units = null, included_units = null, charged_units = null, amount = null,
           fail_reason = null, rated_at = null
     where started_at >= date '2031-01-01' and started_at < date '2031-02-01';
    delete from allowance_usage where cycle_id = test_fixture.g_jan;

    l_n := billing_rate.rate_pending(p_batch_size => 97);
    ut.expect(l_n).to_equal(l_rated);
    for r in (select cdr_id,
                     status || '|' || cycle_id || '|' || late || '|' || dest_class || '|' || peak || '|'
                     || tariff_id || '|' || rated_units || '|' || included_units || '|' || charged_units
                     || '|' || amount || '|' || fail_reason as sig
                from cdrs
               where started_at >= date '2031-01-01' and started_at < date '2031-02-01') loop
      if not l_slow.exists(r.cdr_id) or l_slow(r.cdr_id) <> r.sig then
        l_mismatches := l_mismatches + 1;
      end if;
    end loop;
    ut.expect(l_mismatches).to_equal(0);

    select sum(used_units) into l_used_fast from allowance_usage where cycle_id = test_fixture.g_jan;
    ut.expect(l_used_fast).to_equal(l_used_slow);
    ut.expect(l_used_fast).to_be_greater_than(0);
  end fast_matches_slow;

end test_billing_rate;
/
