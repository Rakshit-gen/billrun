create or replace package body test_billing_admin as

  procedure setup is
  begin
    test_fixture.setup;
  end setup;

  procedure number_in_use is
    l_id subscribers.subscriber_id%type;
  begin
    l_id := billing_admin.add_subscriber(test_fixture.g_customer, test_fixture.g_msisdn, 'TEST1', date '2031-06-01');
  end number_in_use;

  procedure number_reused is
    l_other  customers.customer_id%type := billing_admin.add_customer('Next owner');
    l_id     subscribers.subscriber_id%type;
    l_rows   pls_integer;
  begin
    billing_admin.deactivate(test_fixture.g_subscriber, date '2031-02-01');
    l_id := billing_admin.add_subscriber(l_other, test_fixture.g_msisdn, 'TEST2', date '2031-02-01');
    select count(*) into l_rows from subscribers where msisdn = test_fixture.g_msisdn;
    ut.expect(l_rows).to_equal(2);
    select count(*) into l_rows
      from subscriber_plans
     where subscriber_id = test_fixture.g_subscriber and valid_to = date '2031-02-01';
    ut.expect(l_rows).to_equal(1);
  end number_reused;

  procedure change_too_early is
  begin
    billing_admin.change_plan(test_fixture.g_subscriber, 'TEST2', date '2031-01-01');
  end change_too_early;

  procedure unknown_plan is
  begin
    billing_admin.change_plan(test_fixture.g_subscriber, 'NOPE', date '2031-02-01');
  end unknown_plan;

  procedure open_cycle_twice is
  begin
    ut.expect(billing_admin.open_cycle(date '2031-01-17')).to_equal(test_fixture.g_jan);
  end open_cycle_twice;

end test_billing_admin;
/
