-- Times a month of made up usage through the loader and both raters,
-- then rolls it all back:
--   sqlplus billrun/password@//localhost/FREEPDB1 @bench/bench.sql
-- Uses March 2030, which nothing else touches.

whenever sqlerror exit failure rollback
set define off
set feedback off
set serveroutput on

declare
  c_records    constant pls_integer := 50000;
  c_customers  constant pls_integer := 2000;
  l_cycle      bill_cycles.cycle_id%type;
  l_start      pls_integer;
  l_n          pls_integer;
  l_slow       number;
  l_fast       number;

  -- Seconds since l_start, from dbms_utility.get_time's hundredths.
  function since return number is
  begin
    return (dbms_utility.get_time - l_start) / 100;
  end since;

  procedure report(p_step varchar2, p_rows pls_integer, p_secs number) is
  begin
    dbms_output.put_line(rpad(p_step, 22) || lpad(p_rows, 8) || ' rows'
      || lpad(to_char(p_secs, 'FM990.00'), 9) || ' s'
      || lpad(case when p_secs > 0 then to_char(round(p_rows / p_secs)) end, 10) || ' rows/s');
  end report;
begin
  billing_demo.add_customers(c_customers, date '2030-01-01', 42);
  l_cycle := billing_admin.open_cycle(date '2030-03-01');

  l_start := dbms_utility.get_time;
  billing_demo.stage_usage('bench.csv', c_records, date '2030-03-01', 42, 0.01);
  report('stage (generate)', c_records, since);

  l_start := dbms_utility.get_time;
  l_n := billing_load.load_staged(p_max_rows => c_records * 2);
  report('load_staged', l_n, since);

  l_start := dbms_utility.get_time;
  l_n := billing_rate.rate_pending_slow(p_max_rows => c_records * 2);
  l_slow := since;
  report('rate_pending_slow', l_n, l_slow);

  update cdrs
     set status = 'NEW', cycle_id = null, late = 'N', dest_class = null, peak = null, tariff_id = null,
         rated_units = null, included_units = null, charged_units = null, amount = null,
         fail_reason = null, rated_at = null
   where started_at >= date '2030-03-01' and started_at < date '2030-04-01';
  delete from allowance_usage where cycle_id = l_cycle;

  l_start := dbms_utility.get_time;
  l_n := billing_rate.rate_pending(p_max_rows => c_records * 2);
  l_fast := since;
  report('rate_pending', l_n, l_fast);
  if l_fast > 0 then
    dbms_output.put_line('rate_pending is ' || to_char(l_slow / l_fast, 'FM990.0') || 'x rate_pending_slow');
  end if;

  l_start := dbms_utility.get_time;
  l_n := billing_run.bill_cycle(l_cycle);
  report('bill_cycle (invoices)', l_n, since);

  rollback;
end;
/
