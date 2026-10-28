-- Times a month of made up usage through the loader, all three raters
-- and the bill run. The arguments are the call records, the customers
-- and how many times to run each rater:
--   sqlplus billrun/password@//localhost/FREEPDB1 @bench/bench.sql 50000 2000 3
-- Uses March 2030, which nothing else touches. The parallel rater runs
-- in other sessions, which only see committed rows, so the data is
-- committed, and deleted again at the end; the bill run is rolled back.

whenever sqlerror exit failure rollback
set verify off
set feedback off
set serveroutput on

declare
  c_records    constant pls_integer := &1;
  c_customers  constant pls_integer := &2;
  c_runs       constant pls_integer := &3;
  c_month      constant date := date '2030-03-01';
  l_cycle      bill_cycles.cycle_id%type;
  l_start      pls_integer;
  l_n          pls_integer;
  l_slow       number;
  l_fast       number;
  l_parallel   number;
  l_expected   number;
  l_rated      boolean := false;

  -- One number for what the raters wrote on every record of the month,
  -- so the faster raters can be checked against the row by row one.
  function fingerprint return number is
    l_sum number;
  begin
    select sum(ora_hash(cdr_id || '|' || status || '|' || tariff_id || '|' || charged_units || '|' || amount))
      into l_sum
      from cdrs
     where started_at >= c_month and started_at < add_months(c_month, 1);
    return l_sum;
  end fingerprint;

  procedure check_same(p_rater varchar2) is
  begin
    if fingerprint <> l_expected then
      raise_application_error(-20999, p_rater || ' rated the month differently from rate_pending_slow');
    end if;
  end check_same;

  -- Rates the month c_runs times with one rater, from unrated each time,
  -- checks every run against the first run of rate_pending_slow, and
  -- prints the median, fastest and slowest. Returns the median.
  function rate_runs(p_rater varchar2) return number is
    l_secs    sys.odcinumberlist := sys.odcinumberlist();
    l_median  number;
    l_min     number;
    l_max     number;
  begin
    for i in 1 .. c_runs loop
      if l_rated then
        unrate;
      end if;
      l_start := dbms_utility.get_time;
      if p_rater = 'rate_pending_slow' then
        l_n := billing_rate.rate_pending_slow(p_max_rows => c_records * 2);
      elsif p_rater = 'rate_pending' then
        l_n := billing_rate.rate_pending(p_max_rows => c_records * 2);
      else
        l_n := billing_rate.rate_parallel(p_parallel_level => 2, p_chunks => 8);
      end if;
      l_secs.extend;
      l_secs(i) := since;
      commit;
      l_rated := true;
      if l_expected is null then
        l_expected := fingerprint;
      else
        check_same(p_rater);
      end if;
    end loop;

    select median(column_value), min(column_value), max(column_value)
      into l_median, l_min, l_max
      from table(l_secs);
    dbms_output.put_line(rpad(p_rater, 26) || lpad(l_n, 8) || ' rows'
      || '  median ' || to_char(l_median, 'FM990.00') || ' s, min ' || to_char(l_min, 'FM990.00')
      || ' s, max ' || to_char(l_max, 'FM990.00') || ' s, '
      || case when l_median > 0 then round(l_n / l_median) end || ' rows/s');
    return l_median;
  end rate_runs;

  -- Seconds since l_start, from dbms_utility.get_time's hundredths.
  function since return number is
  begin
    return (dbms_utility.get_time - l_start) / 100;
  end since;

  procedure report(p_step varchar2, p_rows pls_integer, p_secs number) is
  begin
    dbms_output.put_line(rpad(p_step, 26) || lpad(p_rows, 8) || ' rows'
      || lpad(to_char(p_secs, 'FM990.00'), 9) || ' s'
      || lpad(case when p_secs > 0 then to_char(round(p_rows / p_secs)) end, 10) || ' rows/s');
  end report;

  procedure unrate is
  begin
    update cdrs
       set status = 'NEW', cycle_id = null, late = 'N', dest_class = null, peak = null, tariff_id = null,
           rated_units = null, included_units = null, charged_units = null, amount = null,
           fail_reason = null, rated_at = null
     where started_at >= c_month and started_at < add_months(c_month, 1);
    delete from allowance_usage where cycle_id = l_cycle;
    commit;
  end unrate;

  procedure clean_up is
  begin
    rollback;
    delete from allowance_usage where cycle_id = l_cycle;
    delete from cdrs where started_at >= c_month and started_at < add_months(c_month, 1);
    delete from cdr_staging where file_name = 'bench.csv';
    delete from subscriber_plans
     where subscriber_id in (select s.subscriber_id from subscribers s
                               join customers c on c.customer_id = s.customer_id
                              where c.name like 'Bench customer %');
    delete from subscribers
     where customer_id in (select customer_id from customers where name like 'Bench customer %');
    delete from customers where name like 'Bench customer %';
    delete from bill_cycles where cycle_id = l_cycle;
    commit;
  end clean_up;
begin
  dbms_output.put_line(c_records || ' call records, ' || c_customers || ' customers, '
    || c_runs || ' runs of each rater, all checked against the first run of rate_pending_slow');
  billing_demo.add_customers(c_customers, date '2030-01-01', 42);
  update customers set name = replace(name, 'Demo customer', 'Bench customer')
   where name like 'Demo customer %';
  l_cycle := billing_admin.open_cycle(c_month);

  l_start := dbms_utility.get_time;
  billing_demo.stage_usage('bench.csv', c_records, c_month, 42, 0.01);
  report('stage (generate)', c_records, since);
  commit;

  l_start := dbms_utility.get_time;
  l_n := billing_load.load_staged(p_max_rows => c_records * 2);
  report('load_staged', l_n, since);
  commit;

  l_slow := rate_runs('rate_pending_slow');
  l_fast := rate_runs('rate_pending');
  l_parallel := rate_runs('rate_parallel');
  if l_fast > 0 and l_parallel > 0 then
    dbms_output.put_line('by median, rate_pending is ' || to_char(l_slow / l_fast, 'FM990.0')
      || 'x rate_pending_slow; rate_parallel is ' || to_char(l_slow / l_parallel, 'FM990.0') || 'x');
  end if;

  l_start := dbms_utility.get_time;
  l_n := billing_run.bill_cycle(l_cycle);
  report('bill_cycle (invoices)', l_n, since);

  clean_up;
exception
  when others then
    clean_up;
    raise;
end;
/
