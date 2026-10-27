create or replace package billing_errors as
  -- The errors billrun raises, by number and as named exceptions, so a
  -- caller can catch the one it expects and let the rest through.

  cycle_not_open   constant pls_integer := -20001;
  usage_not_rated  constant pls_integer := -20002;
  no_such_cycle    constant pls_integer := -20003;
  number_in_use    constant pls_integer := -20004;
  busy             constant pls_integer := -20005;
  no_such_plan     constant pls_integer := -20006;
  bad_date         constant pls_integer := -20007;
  payment_clash    constant pls_integer := -20008;
  bad_file         constant pls_integer := -20009;
  no_such_reseller constant pls_integer := -20010;

  e_cycle_not_open exception;
  pragma exception_init(e_cycle_not_open, -20001);
  e_usage_not_rated exception;
  pragma exception_init(e_usage_not_rated, -20002);
  e_no_such_cycle exception;
  pragma exception_init(e_no_such_cycle, -20003);
  e_number_in_use exception;
  pragma exception_init(e_number_in_use, -20004);
  e_busy exception;
  pragma exception_init(e_busy, -20005);
  e_no_such_plan exception;
  pragma exception_init(e_no_such_plan, -20006);
  e_bad_date exception;
  pragma exception_init(e_bad_date, -20007);
  e_payment_clash exception;
  pragma exception_init(e_payment_clash, -20008);
  e_bad_file exception;
  pragma exception_init(e_bad_file, -20009);
  e_no_such_reseller exception;
  pragma exception_init(e_no_such_reseller, -20010);

  -- Takes the lock for a process (a row of billing_locks) until the
  -- transaction ends, or raises busy if another session holds it.
  procedure take_lock(p_name varchar2);

  -- The same lock, held across commits until release_lock or the end of
  -- the session: for work that commits as it goes.
  procedure hold_lock(p_name varchar2);
  procedure release_lock(p_name varchar2);
end billing_errors;
/
