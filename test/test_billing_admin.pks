create or replace package test_billing_admin as
  --%suite(billing_admin: customers, numbers and plans)

  --%beforeeach
  procedure setup;

  --%test(A number in use can't be given to someone else)
  --%throws(-20004)
  procedure number_in_use;

  --%test(A number can be reused once its line is deactivated)
  procedure number_reused;

  --%test(A plan change has to come after the current plan started)
  --%throws(-20007)
  procedure change_too_early;

  --%test(An unknown plan is reported as such)
  --%throws(-20006)
  procedure unknown_plan;

  --%test(Opening a cycle twice gives the same cycle)
  procedure open_cycle_twice;
end test_billing_admin;
/
