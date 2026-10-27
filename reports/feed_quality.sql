-- Switch feed quality, for operations.
--   @reports/feed_quality.sql
--
-- Requirement: for each file received, how many records came in, how
-- many were billed, rejected on load and failed in rating, the share
-- lost, and the most common reason, worst file first. Reasons quote the
-- bad value, which would make each one unique, so the value is masked
-- before they're counted.

column file_name format a22         heading 'File'
column received  format 999,990     heading 'Received'
column rated     format 999,990     heading 'Rated'
column rejected  format 99,990      heading 'Rejected'
column failed    format 99,990      heading 'Failed'
column lost_pct  format 990.0       heading 'Lost %'
column reason    format a46         heading 'Most common reason'
column times     format 99,990      heading 'Times'

prompt
prompt Switch feed quality
prompt

with records as (
  select s.file_name,
         case
           when s.status = 'REJECTED' then 'REJECTED'
           when c.status = 'FAILED' then 'FAILED'
           when c.status = 'RATED' then 'RATED'
         end as outcome,
         regexp_replace(coalesce(s.reject_reason, c.fail_reason), '"[^"]*"', '"..."') as reason
    from cdr_staging s
    left join cdrs c on c.staging_id = s.staging_id
),
reasons as (
  select file_name, reason, count(*) as times
    from records
   where reason is not null
   group by file_name, reason
),
top_reason as (
  select file_name,
         max(reason) keep (dense_rank first order by times desc, reason) as reason,
         max(times) as times
    from reasons
   group by file_name
)
select r.file_name,
       count(*) as received,
       count(case r.outcome when 'RATED' then 1 end) as rated,
       count(case r.outcome when 'REJECTED' then 1 end) as rejected,
       count(case r.outcome when 'FAILED' then 1 end) as failed,
       round(100 * count(case when r.outcome in ('REJECTED', 'FAILED') then 1 end) / count(*), 1) as lost_pct,
       t.reason, t.times
  from records r
  left join top_reason t on t.file_name = r.file_name
 group by r.file_name, t.reason, t.times
 order by lost_pct desc, r.file_name;
