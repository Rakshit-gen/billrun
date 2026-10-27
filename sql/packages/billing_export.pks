create or replace package billing_export as
  -- Invoices as JSON documents, for the customer portal, the print house
  -- or a REST endpoint (ORDS can publish this function as it is). Built
  -- with SQL/JSON functions, so it works the same on 19c and later.

  -- One invoice with its customer, lines and payments, or null if there's
  -- no such invoice.
  function invoice_json(p_invoice_id invoices.invoice_id%type) return clob;

  -- Every invoice in a cycle, as one JSON array.
  function cycle_json(p_cycle_id bill_cycles.cycle_id%type) return clob;
end billing_export;
/
