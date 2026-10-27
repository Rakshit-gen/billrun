-- Builds three billed months with payments, runs the reports on them,
-- and rolls it all back, so it can run on any billrun schema:
--   sqlplus billrun/password@//host/service @reports/run.sql
-- None of the calls below commit; the jobs, which do, aren't used.

whenever sqlerror exit failure rollback
set feedback off
set serveroutput on
set define on
set verify off
set linesize 180 pagesize 100 trimspool on

prompt Building January to March 2031: 300 customers, three resellers
declare
  l_north  resellers.reseller_id%type := billing_admin.add_reseller('NORTH', 'Northtel Mobile');
  l_coast  resellers.reseller_id%type := billing_admin.add_reseller('COAST', 'Coastline Telecom');
  l_month  date;
  l_cycle  bill_cycles.cycle_id%type;
  l_paid   number;
  l_n      pls_integer;
  -- How broken each month's switch file is, so the files differ.
  type t_shares is varray(3) of number;
  l_bad    t_shares := t_shares(0.01, 0.04, 0.02);
begin
  billing_demo.add_customers(300, date '2031-01-01', 7);
  update customers
     set reseller_id = case mod(customer_id, 3) when 1 then l_north when 2 then l_coast end
   where name like 'Demo customer %';

  for m in 1 .. 3 loop
    l_month := add_months(date '2031-01-01', m - 1);
    l_cycle := billing_admin.open_cycle(l_month);
    billing_demo.stage_usage('switch-' || to_char(l_month, 'YYYYMM') || '.csv', 6000, l_month, 7 + m, l_bad(m));
    l_n := billing_load.load_staged;
    l_n := billing_rate.rate_pending;

    -- A goodwill credit for every 25th customer.
    insert into adjustments (customer_id, cycle_id, amount, reason)
    select customer_id, l_cycle, -5, 'Goodwill credit'
      from customers
     where name like 'Demo customer %' and mod(customer_id, 25) = 0;

    l_n := billing_run.bill_cycle(l_cycle);

    -- Most customers pay in full a few days before the due date, some
    -- pay half, and the rest don't pay; fewer pay each month, so the
    -- debt ages. ora_hash makes the choice the same on every run.
    for i in (select i.invoice_id, i.invoice_no, i.customer_id, i.total, i.due_date,
                     ora_hash(i.invoice_id, 9) as bucket
                from invoices i
               where i.cycle_id = l_cycle and i.total > 0) loop
      l_paid := case
                  when i.bucket < 8 - m then i.total
                  when i.bucket < 9 - m then round(i.total / 2, 2)
                end;
      if l_paid > 0 then
        l_n := billing_ar.record_payment(i.customer_id, l_paid, 'BANK-' || i.invoice_no, i.due_date - 3);
      end if;
    end loop;
  end loop;

  l_n := billing_ar.run_dunning(date '2031-04-30');
end;
/

@@month_end.sql 2031-03
@@aged_debt.sql 2031-04-30
@@feed_quality.sql

rollback;
exit
