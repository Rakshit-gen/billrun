-- The message type on the billing_events queue. payload is a JSON object
-- with the details for that kind of event.

create or replace type billing_event_t as object (
  event_type     varchar2(30),
  customer_id    number,
  subscriber_id  number,
  cycle_id       number,
  payload        varchar2(4000)
);
/
