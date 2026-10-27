create or replace package body billing_events as

  -- ORA-25228, dequeue timed out with nothing on the queue.
  e_no_message exception;
  pragma exception_init(e_no_message, -25228);

  procedure publish(
    p_event_type     varchar2,
    p_customer_id    number,
    p_subscriber_id  number default null,
    p_cycle_id       number default null,
    p_payload        varchar2 default null
  ) is
    l_options     dbms_aq.enqueue_options_t;
    l_properties  dbms_aq.message_properties_t;
    l_msgid       raw(16);
  begin
    l_options.visibility := dbms_aq.on_commit;
    dbms_aq.enqueue(
      queue_name         => queue_name,
      enqueue_options    => l_options,
      message_properties => l_properties,
      payload            => billing_event_t(p_event_type, p_customer_id, p_subscriber_id, p_cycle_id, p_payload),
      msgid              => l_msgid);
  end publish;

  function next_event(p_wait pls_integer default 0) return billing_event_t is
    l_options     dbms_aq.dequeue_options_t;
    l_properties  dbms_aq.message_properties_t;
    l_msgid       raw(16);
    l_event       billing_event_t;
  begin
    l_options.wait := p_wait;
    l_options.navigation := dbms_aq.first_message;
    l_options.visibility := dbms_aq.on_commit;
    dbms_aq.dequeue(
      queue_name         => queue_name,
      dequeue_options    => l_options,
      message_properties => l_properties,
      payload            => l_event,
      msgid              => l_msgid);
    return l_event;
  exception
    when e_no_message then
      return null;
  end next_event;

  function raise_allowance_alerts return pls_integer is
    type t_alerts is table of usage_alerts%rowtype index by pls_integer;
    l_alerts    t_alerts;
    l_customer  customers.customer_id%type;
    l_payload   varchar2(4000);
  begin
    -- The allowance is the one on the line's last plan in the cycle.
    select u.subscriber_id, u.cycle_id, u.service, t.pct, u.used_units, a.units, systimestamp
      bulk collect into l_alerts
      from allowance_usage u
      join bill_cycles c on c.cycle_id = u.cycle_id and c.status = 'OPEN'
      join (select sp.subscriber_id, c2.cycle_id,
                   max(sp.plan_id) keep (dense_rank last order by sp.valid_from) as plan_id
              from subscriber_plans sp
              join bill_cycles c2 on sp.valid_from < c2.period_end
                                 and (sp.valid_to is null or sp.valid_to > c2.period_start)
             where c2.status = 'OPEN'
             group by sp.subscriber_id, c2.cycle_id) p
        on p.subscriber_id = u.subscriber_id and p.cycle_id = u.cycle_id
      join allowances a on a.plan_id = p.plan_id and a.service = u.service and a.units > 0
      join (select 80 as pct from dual union all select 100 from dual) t
        on u.used_units * 100 >= a.units * t.pct
     where not exists (select null from usage_alerts x
                        where x.subscriber_id = u.subscriber_id and x.cycle_id = u.cycle_id
                          and x.service = u.service and x.threshold_pct = t.pct)
     order by u.subscriber_id, u.service, t.pct;

    forall i in 1 .. l_alerts.count
      insert into usage_alerts values l_alerts(i);

    for i in 1 .. l_alerts.count loop
      select s.customer_id,
             json_object('msisdn' value s.msisdn, 'service' value l_alerts(i).service,
                         'used' value l_alerts(i).used_units, 'allowance' value l_alerts(i).allowance)
        into l_customer, l_payload
        from subscribers s
       where s.subscriber_id = l_alerts(i).subscriber_id;
      publish('ALLOWANCE_' || l_alerts(i).threshold_pct, l_customer,
              l_alerts(i).subscriber_id, l_alerts(i).cycle_id, l_payload);
    end loop;
    return l_alerts.count;
  end raise_allowance_alerts;

end billing_events;
/
