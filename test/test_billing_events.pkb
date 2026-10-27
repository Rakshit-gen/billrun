create or replace package body test_billing_events as

  procedure setup is
  begin
    test_fixture.setup;
  end setup;

  -- Events on the queue for the fixture's customer, delivered or not:
  -- the queue table holds what this transaction enqueued.
  function events(p_type varchar2) return pls_integer is
    l_n pls_integer;
  begin
    select count(*) into l_n
      from billing_events_qt q
     where q.user_data.event_type = p_type
       and q.user_data.customer_id = test_fixture.g_customer;
    return l_n;
  end events;

  procedure invoice_issued is
    l_n        pls_integer := billing_run.bill_cycle(test_fixture.g_jan);
    l_no       varchar2(20);
    l_due      varchar2(10);
  begin
    ut.expect(events('INVOICE_ISSUED')).to_equal(1);
    select json_value(q.user_data.payload, '$.invoiceNo'), json_value(q.user_data.payload, '$.due')
      into l_no, l_due
      from billing_events_qt q
     where q.user_data.event_type = 'INVOICE_ISSUED'
       and q.user_data.customer_id = test_fixture.g_customer;
    ut.expect(l_no).to_equal('INV-203101-000001');
    ut.expect(l_due).to_equal('2031-02-15');
  end invoice_issued;

  procedure payment_received is
    l_id payments.payment_id%type := billing_ar.record_payment(test_fixture.g_customer, 12.5, 'BANK-9', date '2031-01-20');
  begin
    ut.expect(events('PAYMENT_RECEIVED')).to_equal(1);
    -- A resend isn't a second payment, and isn't a second event.
    l_id := billing_ar.record_payment(test_fixture.g_customer, 12.5, 'BANK-9', date '2031-01-20');
    ut.expect(events('PAYMENT_RECEIVED')).to_equal(1);
  end payment_received;

  procedure dunning_events is
    l_n pls_integer := billing_run.bill_cycle(test_fixture.g_jan);
  begin
    l_n := billing_ar.run_dunning(date '2031-04-16');
    ut.expect(events('DUNNING_REMINDER')).to_equal(1);
    ut.expect(events('DUNNING_WARNING')).to_equal(1);
    ut.expect(events('DUNNING_SUSPEND')).to_equal(1);
  end dunning_events;

  procedure allowance_alerts is
    l_id  cdrs.cdr_id%type := test_fixture.add_cdr('VOICE', '441614960000', date '2031-01-06' + 10/24, 500);
    l_n   pls_integer;
  begin
    -- 540 of 600 seconds.
    l_n := billing_rate.rate_pending;
    ut.expect(billing_events.raise_allowance_alerts).to_equal(1);
    ut.expect(billing_events.raise_allowance_alerts).to_equal(0);
    ut.expect(events('ALLOWANCE_80')).to_equal(1);
    l_id := test_fixture.add_cdr('VOICE', '441614960000', date '2031-01-07' + 10/24, 120);
    l_n := billing_rate.rate_pending;
    ut.expect(billing_events.raise_allowance_alerts).to_equal(1);
    ut.expect(events('ALLOWANCE_100')).to_equal(1);
  end allowance_alerts;

end test_billing_events;
/
