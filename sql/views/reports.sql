-- Reports over billed cycles and rated usage, written with analytic
-- functions so each is one pass over the data.

-- Revenue per billed cycle and the change on the cycle before.
create or replace view cycle_revenue as
select c.cycle_id,
       c.period_start,
       count(i.invoice_id) as invoices,
       nvl(sum(i.subtotal), 0) as subtotal,
       nvl(sum(i.tax), 0) as tax,
       nvl(sum(i.total), 0) as total,
       lag(nvl(sum(i.total), 0)) over (order by c.period_start) as previous_total,
       round(100 * (nvl(sum(i.total), 0)
                    / nullif(lag(nvl(sum(i.total), 0)) over (order by c.period_start), 0) - 1), 1) as change_pct
  from bill_cycles c
  left join invoices i on i.cycle_id = c.cycle_id
 where c.status = 'BILLED'
 group by c.cycle_id, c.period_start;

-- The ten lines with the biggest usage charges in each cycle. rank()
-- keeps ties together, so a cycle can show more than ten.
create or replace view top_usage as
select cycle_id, subscriber_id, msisdn, usage_amount, calls, rnk
  from (select c.cycle_id, c.subscriber_id, s.msisdn,
               round(sum(c.amount), 2) as usage_amount,
               count(*) as calls,
               rank() over (partition by c.cycle_id order by sum(c.amount) desc) as rnk
          from cdrs c
          join subscribers s on s.subscriber_id = c.subscriber_id
         where c.status = 'RATED'
         group by c.cycle_id, c.subscriber_id, s.msisdn)
 where rnk <= 10;

-- Where usage revenue comes from: each destination class's share of the
-- cycle's usage charges.
create or replace view usage_by_destination as
select c.cycle_id,
       c.service,
       c.dest_class,
       count(*) as calls,
       sum(c.rated_units) as rated_units,
       sum(c.included_units) as included_units,
       round(sum(c.amount), 2) as amount,
       round(100 * ratio_to_report(sum(c.amount)) over (partition by c.cycle_id), 1) as share_pct
  from cdrs c
 where c.status = 'RATED'
 group by c.cycle_id, c.service, c.dest_class;

-- Calls by hour of the day, with a running share, for sizing peak hours.
create or replace view usage_by_hour as
select hour_of_day,
       calls,
       round(100 * calls / sum(calls) over (), 1) as share_pct,
       round(100 * sum(calls) over (order by hour_of_day) / sum(calls) over (), 1) as running_pct
  from (select to_number(to_char(started_at, 'HH24')) as hour_of_day, count(*) as calls
          from cdrs
         where status = 'RATED'
         group by to_number(to_char(started_at, 'HH24')));

-- Why call records were rejected or couldn't be rated, most common first.
create or replace view problems as
select 'REJECTED' as stage, reject_reason as reason, count(*) as records,
       min(staged_at) as first_seen, max(staged_at) as last_seen
  from cdr_staging
 where status = 'REJECTED'
 group by reject_reason
union all
select 'FAILED', fail_reason, count(*), cast(min(rated_at) as timestamp), cast(max(rated_at) as timestamp)
  from cdrs
 where status = 'FAILED'
 group by fail_reason;

-- How far through its allowances each line is in each open cycle.
create or replace view allowance_left as
select u.subscriber_id, s.msisdn, u.cycle_id, u.service, a.units as allowance, u.used_units,
       greatest(a.units - u.used_units, 0) as left_units,
       round(100 * u.used_units / a.units, 1) as used_pct
  from allowance_usage u
  join bill_cycles c on c.cycle_id = u.cycle_id and c.status = 'OPEN'
  join subscribers s on s.subscriber_id = u.subscriber_id
  join subscriber_plans sp on sp.subscriber_id = u.subscriber_id
                          and sp.valid_from < c.period_end
                          and (sp.valid_to is null or sp.valid_to > c.period_start)
                          and sp.valid_to is null
  join allowances a on a.plan_id = sp.plan_id and a.service = u.service;
