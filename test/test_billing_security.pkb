create or replace package body test_billing_security as

  g_mine  customers.customer_id%type;
  g_rival resellers.reseller_id%type;

  procedure setup is
    l_reseller  resellers.reseller_id%type;
    l_sub       subscribers.subscriber_id%type;
    l_cdr       cdrs.cdr_id%type;
    l_n         pls_integer;
  begin
    test_fixture.setup;
    l_reseller := billing_admin.add_reseller('TESTMVNO', 'Test MVNO');
    g_rival := billing_admin.add_reseller('RIVAL', 'Rival MVNO');
    g_mine := billing_admin.add_customer('MVNO customer', 0.2, 'TESTMVNO');
    l_sub := billing_admin.add_subscriber(g_mine, '447000999777', 'TEST1', date '2031-01-01');
    insert into cdrs (subscriber_id, service, called, started_at, quantity)
    values (l_sub, 'SMS', '447700900123', date '2031-01-06', 1);
    l_cdr := test_fixture.add_cdr('SMS', '447700900123', date '2031-01-06', 1);
    l_n := billing_rate.rate_pending;
    l_n := billing_run.bill_cycle(test_fixture.g_jan);
  end setup;

  procedure clear is
  begin
    billing_security.clear_reseller;
  end clear;

  function seen(p_table varchar2) return pls_integer is
    l_n pls_integer;
  begin
    -- Dynamic so each count is parsed with the policy in force.
    execute immediate 'select count(*) from ' || dbms_assert.simple_sql_name(p_table) into l_n;
    return l_n;
  end seen;

  procedure scoped_reads is
    l_customer customers.customer_id%type;
  begin
    billing_security.set_reseller('TESTMVNO');
    ut.expect(seen('CUSTOMERS')).to_equal(1);
    select customer_id into l_customer from customers;
    ut.expect(l_customer).to_equal(g_mine);
    ut.expect(seen('SUBSCRIBERS')).to_equal(1);
    ut.expect(seen('CDRS')).to_equal(1);
    ut.expect(seen('INVOICES')).to_equal(1);
    ut.expect(seen('INVOICE_LINES')).to_equal(2);
  end scoped_reads;

  procedure unscoped is
  begin
    ut.expect(seen('CUSTOMERS')).to_be_greater_or_equal(2);
    ut.expect(seen('INVOICES')).to_be_greater_or_equal(2);
  end unscoped;

  procedure scoped_insert is
  begin
    billing_security.set_reseller('TESTMVNO');
    insert into customers (name, reseller_id) values ('Poached', g_rival);
  end scoped_insert;

  procedure unknown_reseller is
  begin
    billing_security.set_reseller('NOBODY');
  end unknown_reseller;

end test_billing_security;
/
