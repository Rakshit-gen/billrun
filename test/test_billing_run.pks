create or replace package test_billing_run as
  --%suite(billing_run: invoices)

  --%beforeeach
  procedure setup;

  --%test(A plan change mid month is charged pro rata, with usage, adjustments and tax)
  procedure invoice_adds_up;

  --%test(Invoice numbers run from 1 without gaps, in customer order)
  procedure gapless_numbers;

  --%test(Late calls get their own line)
  procedure late_line;

  --%test(A billed cycle can't be billed again)
  --%throws(-20001)
  procedure rerun_refused;

  --%test(A cycle with calls still to rate can't be billed)
  --%throws(-20002)
  procedure pending_refused;

  --%test(An unknown cycle is reported as such)
  --%throws(-20003)
  procedure unknown_cycle;

  --%test(Invoices in a billed cycle can't be changed)
  --%throws(-20001)
  procedure invoice_frozen;

  --%test(Invoice lines in a billed cycle can't be changed)
  --%throws(-20001)
  procedure lines_frozen;

  --%test(Adjustments can't be booked against a billed cycle)
  --%throws(-20001)
  procedure adjustment_refused;
end test_billing_run;
/
