create or replace package body billing_admin as

  function plan_id(p_code plans.code%type) return plans.plan_id%type is
    l_id plans.plan_id%type;
  begin
    select plan_id into l_id from plans where code = p_code;
    return l_id;
  exception
    when no_data_found then
      raise_application_error(billing_errors.no_such_plan, 'no plan ' || p_code);
  end plan_id;

  function add_customer(p_name varchar2, p_tax_rate number default 0.18)
    return customers.customer_id%type
  is
    l_id customers.customer_id%type;
  begin
    insert into customers (name, tax_rate) values (p_name, p_tax_rate)
    returning customer_id into l_id;
    return l_id;
  end add_customer;

  function add_subscriber(
    p_customer_id  customers.customer_id%type,
    p_msisdn       subscribers.msisdn%type,
    p_plan_code    plans.code%type,
    p_from         date
  ) return subscribers.subscriber_id%type
  is
    l_from   date := trunc(p_from);
    l_plan   plans.plan_id%type := plan_id(p_plan_code);
    l_taken  pls_integer;
    l_id     subscribers.subscriber_id%type;
  begin
    -- Two sessions checking the same number at once could both find it
    -- free; taking the lock first makes them check one after the other.
    billing_errors.take_lock('NUMBERS');
    select count(*) into l_taken
      from subscribers
     where msisdn = p_msisdn
       and (active_to is null or active_to > l_from);
    if l_taken > 0 then
      raise_application_error(billing_errors.number_in_use,
        p_msisdn || ' is in use on ' || to_char(l_from, 'YYYY-MM-DD') || ' or later');
    end if;

    insert into subscribers (customer_id, msisdn, active_from)
    values (p_customer_id, p_msisdn, l_from)
    returning subscriber_id into l_id;
    insert into subscriber_plans (subscriber_id, plan_id, valid_from)
    values (l_id, l_plan, l_from);
    return l_id;
  end add_subscriber;

  procedure change_plan(
    p_subscriber_id  subscribers.subscriber_id%type,
    p_plan_code      plans.code%type,
    p_from           date
  ) is
    l_from     date := trunc(p_from);
    l_plan     plans.plan_id%type := plan_id(p_plan_code);
    l_current  subscriber_plans.valid_from%type;
  begin
    begin
      select valid_from into l_current
        from subscriber_plans
       where subscriber_id = p_subscriber_id
         and valid_to is null
         for update;
    exception
      when no_data_found then
        raise_application_error(billing_errors.bad_date,
          'subscriber ' || p_subscriber_id || ' has no open plan');
    end;
    if l_from <= l_current then
      raise_application_error(billing_errors.bad_date,
        'a plan change has to come after ' || to_char(l_current, 'YYYY-MM-DD'));
    end if;

    update subscriber_plans
       set valid_to = l_from
     where subscriber_id = p_subscriber_id
       and valid_from = l_current;
    insert into subscriber_plans (subscriber_id, plan_id, valid_from)
    values (p_subscriber_id, l_plan, l_from);
  end change_plan;

  procedure deactivate(p_subscriber_id subscribers.subscriber_id%type, p_on date) is
    l_on date := trunc(p_on);
  begin
    update subscribers
       set active_to = l_on
     where subscriber_id = p_subscriber_id
       and active_to is null
       and active_from < l_on;
    if sql%rowcount = 0 then
      raise_application_error(billing_errors.bad_date,
        'subscriber ' || p_subscriber_id || ' is not active before ' || to_char(l_on, 'YYYY-MM-DD'));
    end if;
    update subscriber_plans
       set valid_to = l_on
     where subscriber_id = p_subscriber_id
       and valid_to is null;
  end deactivate;

  function open_cycle(p_month date) return bill_cycles.cycle_id%type is
    l_start  date := trunc(p_month, 'MM');
    l_id     bill_cycles.cycle_id%type;
  begin
    insert into bill_cycles (period_start, period_end)
    values (l_start, add_months(l_start, 1))
    returning cycle_id into l_id;
    return l_id;
  exception
    when dup_val_on_index then
      select cycle_id into l_id from bill_cycles where period_start = l_start;
      return l_id;
  end open_cycle;

end billing_admin;
/
