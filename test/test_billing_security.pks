create or replace package test_billing_security as
  --%suite(billing_security: resellers see only their own customers)

  --%beforeeach
  procedure setup;

  --%aftereach
  procedure clear;

  --%test(A reseller session sees its customers, their lines, calls and invoices, and nothing else)
  procedure scoped_reads;

  --%test(Without a reseller set everything is visible)
  procedure unscoped;

  --%test(A reseller can't create a customer for another reseller)
  --%throws(-28115)
  procedure scoped_insert;

  --%test(An unknown reseller is refused)
  --%throws(-20010)
  procedure unknown_reseller;
end test_billing_security;
/
