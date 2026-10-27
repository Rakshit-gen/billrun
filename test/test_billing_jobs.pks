create or replace package test_billing_jobs as
  --%suite(billing_jobs: scheduler jobs)
  --%rollback(manual)

  -- DBMS_SCHEDULER commits, so this can't run inside a rolled back
  -- transaction; the test drops what it creates.
  --%test(The jobs can be created and dropped, and dropping twice is fine)
  procedure create_and_drop;
end test_billing_jobs;
/
