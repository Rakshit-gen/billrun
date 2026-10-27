create or replace package test_billing_export as
  --%suite(billing_export: invoices as JSON)

  --%beforeeach
  procedure setup;

  --%test(An invoice comes out as JSON with its lines and payments nested)
  procedure invoice_document;

  --%test(A cycle comes out as an array of its invoices)
  procedure cycle_document;

  --%test(An unknown invoice gives null)
  procedure unknown_invoice;
end test_billing_export;
/
