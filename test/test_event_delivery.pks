create or replace package test_event_delivery as
  --%suite(billing_events: delivery follows the transaction)
  --%rollback(manual)

  -- These commit, to show what a consumer in another transaction sees.

  --%test(A committed event is delivered)
  procedure committed_is_delivered;

  --%test(A rolled back event never is)
  procedure rolled_back_is_not;
end test_event_delivery;
/
