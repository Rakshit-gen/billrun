-- Aged debt, for collections.
--   @reports/aged_debt.sql YYYY-MM-DD
--
-- Requirement: on the given day, the 20 customers to call first (most
-- owed over 60 days past due, then most owed in all) with what they owe
-- by days past due, money they have on account, their status and the
-- last dunning step taken, then a total row over every customer, not
-- only the 20.

column customer    format a24             heading 'Customer'
column status      format a9              heading 'Status'
column not_due     format 999,990.00      heading 'Not due'
column d1_30       format 999,990.00      heading '1-30'
column d31_60      format 999,990.00      heading '31-60'
column d61_90      format 999,990.00      heading '61-90'
column d90         format 999,990.00      heading 'Over 90'
column open_amount format 9,999,990.00    heading 'Owed'
column on_account  format 999,990.00      heading 'On account'
column last_step   format a8              heading 'Dunning'

prompt
prompt Aged debt on &1
prompt

with aging as (
  select * from table(billing_ar.aging(to_date('&1', 'YYYY-MM-DD')))
),
last_step as (
  select i.customer_id, max(d.action) keep (dense_rank last order by d.step, d.taken_on) as action
    from dunning_actions d
    join invoices i on i.invoice_id = d.invoice_id
   where d.taken_on <= to_date('&1', 'YYYY-MM-DD')
   group by i.customer_id
),
worst as (
  select a.name, a.status, a.not_due, a.days_1_30, a.days_31_60, a.days_61_90, a.days_over_90,
         a.total_open, a.unallocated, s.action,
         row_number() over (order by a.days_61_90 + a.days_over_90 desc, a.total_open desc, a.customer_id) as rn
    from aging a
    left join last_step s on s.customer_id = a.customer_id
   where a.total_open > 0
)
select customer, status, not_due, d1_30, d31_60, d61_90, d90, open_amount, on_account, last_step
  from (select rn, name as customer, status, not_due, days_1_30 as d1_30, days_31_60 as d31_60,
               days_61_90 as d61_90, days_over_90 as d90, total_open as open_amount,
               unallocated as on_account, action as last_step
          from worst
         where rn <= 20
        union all
        select 21, 'All ' || count(*) || ' customers', null, sum(not_due), sum(days_1_30), sum(days_31_60),
               sum(days_61_90), sum(days_over_90), sum(total_open), sum(unallocated), null
          from aging)
 order by rn;
