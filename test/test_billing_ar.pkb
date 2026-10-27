create or replace package body test_billing_ar as

  -- The fixture's line on TEST1 for a whole month: 30.00 plus 18% tax.
  c_month_total constant number := 35.40;

  procedure setup is
  begin
    test_fixture.setup;
  end setup;

  function bill(p_cycle_id bill_cycles.cycle_id%type) return invoices%rowtype is
    l_n  pls_integer := billing_run.bill_cycle(p_cycle_id);
    l    invoices%rowtype;
  begin
    select * into l from invoices where customer_id = test_fixture.g_customer and cycle_id = p_cycle_id;
    return l;
  end bill;

  function pay(p_amount number, p_reference varchar2, p_on date) return payments.payment_id%type is
  begin
    return billing_ar.record_payment(test_fixture.g_customer, p_amount, p_reference, p_on);
  end pay;

  function customer_status return customers.status%type is
    l customers.status%type;
  begin
    select status into l from customers where customer_id = test_fixture.g_customer;
    return l;
  end customer_status;

  procedure due_dates is
    l invoices%rowtype := bill(test_fixture.g_jan);
  begin
    ut.expect(l.issued_at).to_equal(date '2031-02-01');
    ut.expect(l.due_date).to_equal(date '2031-02-15');
    ut.expect(l.total).to_equal(c_month_total);
  end due_dates;

  procedure oldest_first is
    l_jan  invoices%rowtype := bill(test_fixture.g_jan);
    l_feb  invoices%rowtype := bill(test_fixture.g_feb);
    l_id   payments.payment_id%type;
  begin
    l_id := pay(50, 'BANK-0001', date '2031-02-20');
    ut.expect(billing_ar.open_amount(l_jan.invoice_id)).to_equal(0);
    ut.expect(billing_ar.open_amount(l_feb.invoice_id)).to_equal(2 * c_month_total - 50);
  end oldest_first;

  procedure credit_on_account is
    l_id   payments.payment_id%type := pay(100, 'BANK-0002', date '2031-01-15');
    l_jan  invoices%rowtype;
    l_n    pls_integer;
    l_row  ar_aging_row;
  begin
    l_jan := bill(test_fixture.g_jan);
    ut.expect(billing_ar.open_amount(l_jan.invoice_id)).to_equal(c_month_total);
    l_n := billing_ar.allocate_all;
    ut.expect(l_n).to_equal(1);
    ut.expect(billing_ar.open_amount(l_jan.invoice_id)).to_equal(0);
    select value(a) into l_row
      from table(billing_ar.aging(date '2031-02-02')) a
     where a.customer_id = test_fixture.g_customer;
    ut.expect(l_row.total_open).to_equal(0);
    ut.expect(l_row.unallocated).to_equal(100 - c_month_total);
  end credit_on_account;

  procedure resent_payment is
    l_first   payments.payment_id%type := pay(20, 'CARD-77', date '2031-02-03');
    l_second  payments.payment_id%type := pay(20, 'CARD-77', date '2031-02-03');
    l_n       pls_integer;
  begin
    ut.expect(l_second).to_equal(l_first);
    select count(*) into l_n from payments where customer_id = test_fixture.g_customer;
    ut.expect(l_n).to_equal(1);
  end resent_payment;

  procedure reference_clash is
    l_id payments.payment_id%type := pay(20, 'CARD-78', date '2031-02-03');
  begin
    l_id := pay(25, 'CARD-78', date '2031-02-03');
  end reference_clash;

  procedure dunning_steps is
    l_jan      invoices%rowtype := bill(test_fixture.g_jan);
    l_actual   sys_refcursor;
    l_expect   sys_refcursor;
    l_id       payments.payment_id%type;
  begin
    -- Due on 2031-02-15.
    ut.expect(billing_ar.run_dunning(date '2031-02-21')).to_equal(0);
    ut.expect(billing_ar.run_dunning(date '2031-02-22')).to_equal(1);
    ut.expect(billing_ar.run_dunning(date '2031-02-22')).to_equal(0);
    ut.expect(customer_status).to_equal('ACTIVE');
    ut.expect(billing_ar.run_dunning(date '2031-04-16')).to_equal(2);
    ut.expect(customer_status).to_equal('SUSPENDED');

    open l_actual for
      select step, action, days_overdue, open_amount, taken_on
        from dunning_actions where invoice_id = l_jan.invoice_id order by step;
    open l_expect for
      select 1 step, cast('REMINDER' as varchar2(8)) action, 7 days_overdue, c_month_total open_amount,
             date '2031-02-22' taken_on from dual union all
      select 2, 'WARNING', 60, c_month_total, date '2031-04-16' from dual union all
      select 3, 'SUSPEND', 60, c_month_total, date '2031-04-16' from dual;
    ut.expect(l_actual).to_equal(l_expect);

    l_id := pay(c_month_total, 'BANK-0003', date '2031-04-17');
    ut.expect(customer_status).to_equal('ACTIVE');
  end dunning_steps;

  procedure aging_buckets is
    l_jan  invoices%rowtype := bill(test_fixture.g_jan);
    l_feb  invoices%rowtype := bill(test_fixture.g_feb);
    l_row  ar_aging_row;
  begin
    -- On 2031-03-20 January is 33 days overdue and February 5.
    select value(a) into l_row
      from table(billing_ar.aging(date '2031-03-20')) a
     where a.customer_id = test_fixture.g_customer;
    ut.expect(l_row.not_due).to_equal(0);
    ut.expect(l_row.days_1_30).to_equal(c_month_total);
    ut.expect(l_row.days_31_60).to_equal(c_month_total);
    ut.expect(l_row.total_open).to_equal(2 * c_month_total);
    ut.expect(l_row.status).to_equal('ACTIVE');
  end aging_buckets;

end test_billing_ar;
/
