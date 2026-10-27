create or replace package billing_jobs as
  -- The entry points DBMS_SCHEDULER runs. Unlike the packages they call,
  -- these commit: a batch at a time while loading and rating, so a crash
  -- loses one batch of work, not the night's.

  usage_job  constant varchar2(30) := 'BILLRUN_USAGE';
  bill_job   constant varchar2(30) := 'BILLRUN_MONTHLY';

  -- Loads everything staged, then rates everything loaded.
  procedure process_usage;

  -- On the 1st: makes sure this month's and next month's cycles exist,
  -- processes the last of the usage, and bills last month.
  procedure bill_last_month;

  -- Creates the two jobs: usage every 15 minutes, billing at 02:00 on
  -- the 1st. Needs the CREATE JOB privilege.
  procedure create_jobs;
  procedure drop_jobs;
end billing_jobs;
/
