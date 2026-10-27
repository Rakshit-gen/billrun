-- Events for the systems around billing: the customer portal, SMS
-- notifications, the print house, collections. They go on an Advanced
-- Queuing queue in the same transaction as the work, so an event is
-- delivered if and only if the work commits; nothing has to reconcile a
-- "sent" flag with what happened.

begin
  dbms_aqadm.create_queue_table(
    queue_table        => 'billing_events_qt',
    queue_payload_type => 'billing_event_t',
    comment            => 'billrun events');
  dbms_aqadm.create_queue(
    queue_name  => 'billing_events',
    queue_table => 'billing_events_qt');
  dbms_aqadm.start_queue(queue_name => 'billing_events');
end;
/

-- Each allowance threshold a line crosses in a cycle, once, so the "80%
-- used" text message goes out once however often rating runs.
create table usage_alerts (
  subscriber_id  number not null references subscribers,
  cycle_id       number not null references bill_cycles,
  service        varchar2(5) not null,
  threshold_pct  number(3) not null constraint usage_alerts_pct_ck check (threshold_pct in (80, 100)),
  used_units     number not null,
  allowance      number not null,
  raised_at      timestamp default systimestamp not null,
  constraint usage_alerts_pk primary key (subscriber_id, cycle_id, service, threshold_pct)
);
