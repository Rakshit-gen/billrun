create or replace package test_fixture as
  -- Data the test suites share, created inside each test's transaction
  -- and rolled back after it by utPLSQL. Everything is dated 2031 so it
  -- can't meet the seed data or a demo run.
  --
  -- Plans TEST1 (30.00 a month) and TEST2 (60.00) charge the same:
  --   calls to national numbers  0.10 a minute at peak, in whole minutes
  --                              0.05 a minute off peak, per second after the first minute
  --   calls abroad               1.00 a minute, in whole minutes
  --   texts to mobiles           0.05 each
  --   data                       0.01 a megabyte
  -- and include 600 seconds of calls and 2048 KB of data. They have no
  -- tariff for local numbers.
  --
  -- 2031-01-06 is a Monday.

  g_customer    customers.customer_id%type;
  g_subscriber  subscribers.subscriber_id%type;
  g_msisdn      constant varchar2(15) := '447000999001';
  g_jan         bill_cycles.cycle_id%type;
  g_feb         bill_cycles.cycle_id%type;
  g_mar         bill_cycles.cycle_id%type;

  -- The plans, a customer taxed at 18% with one line on TEST1 from
  -- 2031-01-01, and open cycles for January to March 2031.
  procedure setup;

  -- Adds a NEW call record for the fixture's line.
  function add_cdr(p_service varchar2, p_called varchar2, p_at date, p_quantity number)
    return cdrs.cdr_id%type;

  function cdr(p_cdr_id cdrs.cdr_id%type) return cdrs%rowtype;
end test_fixture;
/
