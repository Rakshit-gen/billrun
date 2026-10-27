create or replace package test_billing_maint as
  --%suite(billing_maint: compressing and purging months)
  --%rollback(manual)

  -- Partition DDL commits, so this suite commits its own data in 2032
  -- and removes it again.

  --%beforeall
  procedure setup;

  --%afterall
  procedure clean_up;

  --%test(A month is compressed in place and its indexes stay usable)
  procedure compresses;

  --%test(A month with records still to rate is kept, and dropped once they're done)
  procedure purges;
end test_billing_maint;
/
