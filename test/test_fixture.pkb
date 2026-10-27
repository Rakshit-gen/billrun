create or replace package body test_fixture as

  procedure add_plan(p_code varchar2, p_fee number) is
    l_plan plans.plan_id%type;

    procedure tariff(p_service varchar2, p_class varchar2, p_period varchar2,
                     p_first number, p_next number, p_price number, p_per number) is
    begin
      insert into tariffs (plan_id, service, dest_class, period, first_units, next_units, price, price_units, valid_from)
      values (l_plan, p_service, p_class, p_period, p_first, p_next, p_price, p_per, date '2030-01-01');
    end tariff;
  begin
    insert into plans (code, name, monthly_fee) values (p_code, 'Test ' || p_code, p_fee)
    returning plan_id into l_plan;
    tariff('VOICE', 'NATIONAL', 'PEAK',    60, 60, 0.10, 60);
    tariff('VOICE', 'NATIONAL', 'OFFPEAK', 60,  1, 0.05, 60);
    tariff('VOICE', 'INTL',     'ANY',     60, 60, 1.00, 60);
    tariff('SMS',   'MOBILE',   'ANY',      1,  1, 0.05, 1);
    tariff('DATA',  'DATA',     'ANY',      1,  1, 0.01, 1024);
    insert into allowances (plan_id, service, units) values (l_plan, 'VOICE', 600);
    insert into allowances (plan_id, service, units) values (l_plan, 'DATA', 2048);
  end add_plan;

  procedure setup is
  begin
    add_plan('TEST1', 30);
    add_plan('TEST2', 60);
    g_customer := billing_admin.add_customer('Test customer', 0.18);
    g_subscriber := billing_admin.add_subscriber(g_customer, g_msisdn, 'TEST1', date '2031-01-01');
    g_jan := billing_admin.open_cycle(date '2031-01-01');
    g_feb := billing_admin.open_cycle(date '2031-02-01');
    g_mar := billing_admin.open_cycle(date '2031-03-01');
  end setup;

  function add_cdr(p_service varchar2, p_called varchar2, p_at date, p_quantity number)
    return cdrs.cdr_id%type
  is
    l_id cdrs.cdr_id%type;
  begin
    insert into cdrs (subscriber_id, service, called, started_at, quantity)
    values (g_subscriber, p_service, p_called, p_at, p_quantity)
    returning cdr_id into l_id;
    return l_id;
  end add_cdr;

  function cdr(p_cdr_id cdrs.cdr_id%type) return cdrs%rowtype is
    l cdrs%rowtype;
  begin
    select * into l from cdrs where cdr_id = p_cdr_id;
    return l;
  end cdr;

end test_fixture;
/
