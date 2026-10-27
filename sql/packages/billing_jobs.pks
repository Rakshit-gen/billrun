create or replace package billing_jobs as
  -- The entry points DBMS_SCHEDULER runs. Unlike the packages they call,
  -- these commit: a batch at a time while loading and rating, so a crash
  -- loses one batch of work, not the night's.

  usage_job  constant varchar2(30) := 'BILLRUN_USAGE';
  bill_job   constant varchar2(30) := 'BILLRUN_MONTHLY';
  dun_job    constant varchar2(30) := 'BILLRUN_DUNNING';

  -- Loads everything staged, then rates everything loaded.
  procedure process_usage;

  -- On the 1st: makes sure this month's and next month's cycles exist,
  -- processes the last of the usage, bills last month, and puts money
  -- on account towards the new invoices.
  procedure bill_last_month;

  -- Daily: the dunning steps due today.
  procedure chase_overdue;

  -- Creates the three jobs: usage every 15 minutes, billing at 02:00 on
  -- the 1st, dunning at 06:00 every day. Needs the CREATE JOB privilege.
  procedure create_jobs;
  procedure drop_jobs;
end billing_jobs;
/
