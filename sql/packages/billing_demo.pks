create or replace package billing_demo as
  -- Made up customers and call records for demos, tests and timing.
  -- Everything comes from dbms_random seeded with p_seed, so a seed
  -- always gives the same data. Nothing here commits.

  -- Adds p_customers customers with one to three lines each, on random
  -- plans from p_from. Numbers are 4470 followed by eight digits.
  procedure add_customers(p_customers pls_integer, p_from date, p_seed binary_integer default 1);

  -- Stages p_records call records spread over the month of p_month, from
  -- lines active all that month, as if they came in file p_file_name.
  -- About p_bad_share of them are broken the way real feeds are: a start
  -- time in the wrong format, a number nobody has, or a resent record.
  procedure stage_usage(
    p_file_name  varchar2,
    p_records    pls_integer,
    p_month      date,
    p_seed       binary_integer default 1,
    p_bad_share  number default 0.01
  );
end billing_demo;
/
