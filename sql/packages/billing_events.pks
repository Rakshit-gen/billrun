create or replace package billing_events as
  -- Publishing to and reading from the billing_events queue. Publishing
  -- doesn't commit: the event is seen by consumers when, and only if,
  -- the caller's transaction commits.
  --
  -- Event types:
  --   INVOICE_ISSUED     an invoice was billed
  --   PAYMENT_RECEIVED   a payment was taken
  --   DUNNING_REMINDER, DUNNING_WARNING, DUNNING_SUSPEND
  --   ALLOWANCE_80, ALLOWANCE_100   a line used that much of an allowance

  queue_name constant varchar2(30) := 'BILLING_EVENTS';

  procedure publish(
    p_event_type     varchar2,
    p_customer_id    number,
    p_subscriber_id  number default null,
    p_cycle_id       number default null,
    p_payload        varchar2 default null
  );

  -- The next event, waiting up to p_wait seconds, or null if none came.
  -- The dequeue is part of the caller's transaction: roll back and the
  -- event goes back on the queue.
  function next_event(p_wait pls_integer default 0) return billing_event_t;

  -- Records and publishes each 80% and 100% allowance threshold crossed
  -- in an open cycle and not alerted yet. Returns the number of alerts.
  function raise_allowance_alerts return pls_integer;
end billing_events;
/
