create or replace package test_billing_events as
  --%suite(billing_events: what billing tells other systems)

  --%beforeeach
  procedure setup;

  --%test(Billing publishes an event per invoice)
  procedure invoice_issued;

  --%test(A payment publishes an event)
  procedure payment_received;

  --%test(Each dunning step publishes an event)
  procedure dunning_events;

  --%test(Allowance alerts go out once at 80% and once at 100%)
  procedure allowance_alerts;
end test_billing_events;
/
