create or replace package body test_billing_run as

  procedure setup is
  begin
    test_fixture.setup;
  end setup;

  procedure rate is
    l_n pls_integer;
  begin
    l_n := billing_rate.rate_pending;
  end rate;

  procedure bill(p_cycle_id bill_cycles.cycle_id%type) is
    l_n pls_integer;
  begin
    l_n := billing_run.bill_cycle(p_cycle_id);
  end bill;

  function invoice_of(p_customer_id customers.customer_id%type) return invoices%rowtype is
    l invoices%rowtype;
  begin
    select * into l from invoices where customer_id = p_customer_id and cycle_id = test_fixture.g_jan;
    return l;
  end invoice_of;

  procedure invoice_adds_up is
    l_id      cdrs.cdr_id%type;
    l         invoices%rowtype;
    l_status  bill_cycles.status%type;
    l_actual  sys_refcursor;
    l_expect  sys_refcursor;
  begin
    billing_admin.change_plan(test_fixture.g_subscriber, 'TEST2', date '2031-01-11');
    l_id := test_fixture.add_cdr('VOICE', '33140000000', to_date('2031-01-06 10:00', 'YYYY-MM-DD HH24:MI'), 61);
    insert into adjustments (customer_id, cycle_id, amount, reason)
    values (test_fixture.g_customer, test_fixture.g_jan, -5, 'Goodwill credit');
    rate;
    bill(test_fixture.g_jan);

    l := invoice_of(test_fixture.g_customer);
    -- 30.00 * 10/31 = 9.68, 60.00 * 21/31 = 40.65, a 2.00 call, a 5.00 credit.
    ut.expect(l.subtotal).to_equal(47.33);
    ut.expect(l.tax).to_equal(8.52);
    ut.expect(l.total).to_equal(55.85);

    open l_actual for
      select line_no, kind, description, quantity, amount
        from invoice_lines where invoice_id = l.invoice_id order by line_no;
    open l_expect for
      -- Literals are CHAR; the casts make the column types match the table's.
      select 1 line_no, cast('RECURRING' as varchar2(10)) kind,
             cast('Test TEST1, 10 of 31 days' as varchar2(200)) description, 10 quantity, 9.68 amount from dual union all
      select 2, 'RECURRING', 'Test TEST2, 21 of 31 days', 21, 40.65 from dual union all
      select 3, 'USAGE', 'Calls to international numbers', 120, 2 from dual union all
      select 4, 'ADJUSTMENT', 'Goodwill credit', null, -5 from dual;
    ut.expect(l_actual).to_equal(l_expect);

    select status into l_status from bill_cycles where cycle_id = test_fixture.g_jan;
    ut.expect(l_status).to_equal('BILLED');
  end invoice_adds_up;

  procedure gapless_numbers is
    l_second  customers.customer_id%type := billing_admin.add_customer('Second customer', 0.2);
    l_sub     subscribers.subscriber_id%type;
    l_count   pls_integer;
  begin
    l_sub := billing_admin.add_subscriber(l_second, '447000999002', 'TEST1', date '2031-01-01');
    rate;
    select count(*) into l_count from invoices where cycle_id = test_fixture.g_jan;
    ut.expect(l_count).to_equal(0);
    l_count := billing_run.bill_cycle(test_fixture.g_jan);
    ut.expect(l_count).to_equal(2);
    ut.expect(invoice_of(test_fixture.g_customer).invoice_no).to_equal('INV-203101-000001');
    ut.expect(invoice_of(l_second).invoice_no).to_equal('INV-203101-000002');
    -- 30.00 and 20% tax.
    ut.expect(invoice_of(l_second).total).to_equal(36);
  end gapless_numbers;

  procedure late_line is
    l_on_time  cdrs.cdr_id%type;
    l_late     cdrs.cdr_id%type;
    l_lines    sys_refcursor;
    l_expect   sys_refcursor;
  begin
    l_on_time := test_fixture.add_cdr('VOICE', '33140000000', date '2031-02-02' + 10/24, 60);
    rate;
    bill(test_fixture.g_jan);
    l_late := test_fixture.add_cdr('VOICE', '33140000000', date '2031-01-31' + 10/24, 60);
    rate;
    bill(test_fixture.g_feb);

    open l_lines for
      select l.description, l.amount
        from invoice_lines l
        join invoices i on i.invoice_id = l.invoice_id
       where i.customer_id = test_fixture.g_customer
         and i.cycle_id = test_fixture.g_feb
         and l.kind = 'USAGE'
       order by l.line_no;
    open l_expect for
      select cast('Calls to international numbers' as varchar2(200)) description, 1 amount from dual union all
      select 'Calls to international numbers, arrived late', 1 from dual;
    ut.expect(l_lines).to_equal(l_expect);
  end late_line;

  procedure rerun_refused is
  begin
    bill(test_fixture.g_jan);
    bill(test_fixture.g_jan);
  end rerun_refused;

  procedure pending_refused is
    l_id cdrs.cdr_id%type := test_fixture.add_cdr('SMS', '447700900123', date '2031-01-05', 1);
  begin
    bill(test_fixture.g_jan);
  end pending_refused;

  procedure unknown_cycle is
  begin
    bill(-1);
  end unknown_cycle;

  procedure invoice_frozen is
  begin
    bill(test_fixture.g_jan);
    update invoices set subtotal = 0, tax = 0, total = 0 where customer_id = test_fixture.g_customer;
  end invoice_frozen;

  procedure lines_frozen is
    l_invoice invoices.invoice_id%type;
  begin
    bill(test_fixture.g_jan);
    l_invoice := invoice_of(test_fixture.g_customer).invoice_id;
    delete from invoice_lines where invoice_id = l_invoice;
  end lines_frozen;

  procedure adjustment_refused is
  begin
    bill(test_fixture.g_jan);
    insert into adjustments (customer_id, cycle_id, amount, reason)
    values (test_fixture.g_customer, test_fixture.g_jan, 1, 'Too late');
  end adjustment_refused;

end test_billing_run;
/
