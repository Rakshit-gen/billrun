create or replace package body test_billing_maint as

  c_month  constant date := date '2032-01-01';
  g_customer  customers.customer_id%type;
  g_cdr       cdrs.cdr_id%type;

  procedure setup is
    l_sub subscribers.subscriber_id%type;
  begin
    g_customer := billing_admin.add_customer('Maintenance test');
    l_sub := billing_admin.add_subscriber(g_customer, '447000888001', 'BASIC', c_month);
    insert into cdrs (subscriber_id, service, called, started_at, quantity)
    values (l_sub, 'SMS', '447700900123', c_month + 9, 1)
    returning cdr_id into g_cdr;
    commit;
  end setup;

  procedure clean_up is
  begin
    rollback;
    delete from cdrs where started_at >= c_month and started_at < add_months(c_month, 1);
    delete from subscriber_plans
     where subscriber_id in (select subscriber_id from subscribers where customer_id = g_customer);
    delete from subscribers where customer_id = g_customer;
    delete from customers where customer_id = g_customer;
    commit;
  end clean_up;

  procedure compresses is
    l_name         varchar2(128) := billing_maint.partition_of(c_month);
    l_compression  user_tab_partitions.compression%type;
    l_unusable     pls_integer;
  begin
    ut.expect(l_name).not_to_be_null();
    billing_maint.compress_month(c_month + 14);
    select compression into l_compression
      from user_tab_partitions where table_name = 'CDRS' and partition_name = l_name;
    ut.expect(l_compression).to_equal('ENABLED');
    select count(*) into l_unusable
      from user_ind_partitions where partition_name = l_name and status <> 'USABLE';
    ut.expect(l_unusable).to_equal(0);
  end compresses;

  procedure purges is
  begin
    ut.expect(billing_maint.purge_before(add_months(c_month, 1), c_month)).to_equal(0);
    ut.expect(billing_maint.partition_of(c_month)).not_to_be_null();

    update cdrs set status = 'FAILED', fail_reason = 'test'
     where cdr_id = g_cdr and started_at = c_month + 9;
    commit;
    ut.expect(billing_maint.purge_before(add_months(c_month, 1), c_month)).to_equal(1);
    ut.expect(billing_maint.partition_of(c_month)).to_be_null();
  end purges;

end test_billing_maint;
/
