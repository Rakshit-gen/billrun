create or replace package body test_billing_export as

  g_invoice invoices.invoice_id%type;

  procedure setup is
    l_id  cdrs.cdr_id%type;
    l_n   pls_integer;
  begin
    test_fixture.setup;
    l_id := test_fixture.add_cdr('VOICE', '33140000000', date '2031-01-06' + 10/24, 61);
    l_n := billing_rate.rate_pending;
    l_n := billing_run.bill_cycle(test_fixture.g_jan);
    select invoice_id into g_invoice
      from invoices where customer_id = test_fixture.g_customer and cycle_id = test_fixture.g_jan;
    l_id := billing_ar.record_payment(test_fixture.g_customer, 10, 'CARD-1', date '2031-02-03', 'CARD');
  end setup;

  procedure invoice_document is
    l_doc     clob := billing_export.invoice_json(g_invoice);
    l_no      varchar2(20);
    l_total   number;
    l_paid    number;
    l_lines   pls_integer;
    l_msisdn  varchar2(15);
    l_ref     varchar2(60);
  begin
    ut.expect(l_doc).not_to_be_null();
    select json_value(l_doc, '$.invoiceNo'),
           json_value(l_doc, '$.total' returning number),
           json_value(l_doc, '$.paid' returning number),
           json_value(l_doc, '$.lines[0].msisdn'),
           json_value(l_doc, '$.payments[0].reference')
      into l_no, l_total, l_paid, l_msisdn, l_ref
      from dual;
    ut.expect(l_no).to_equal('INV-203101-000001');
    -- 30.00 and a 2.00 call, plus 18%.
    ut.expect(l_total).to_equal(37.76);
    ut.expect(l_paid).to_equal(10);
    ut.expect(l_msisdn).to_equal(test_fixture.g_msisdn);
    ut.expect(l_ref).to_equal('CARD-1');
    select count(*) into l_lines
      from json_table(l_doc, '$.lines[*]' columns (line_no number path '$.line'));
    ut.expect(l_lines).to_equal(2);
  end invoice_document;

  procedure cycle_document is
    l_doc  clob := billing_export.cycle_json(test_fixture.g_jan);
    l_n    pls_integer;
  begin
    select count(*) into l_n
      from json_table(l_doc, '$[*]' columns (invoice_no varchar2(20) path '$.invoiceNo'))
     where invoice_no = 'INV-203101-000001';
    ut.expect(l_n).to_equal(1);
  end cycle_document;

  procedure unknown_invoice is
  begin
    ut.expect(billing_export.invoice_json(-1)).to_be_null();
  end unknown_invoice;

end test_billing_export;
/
