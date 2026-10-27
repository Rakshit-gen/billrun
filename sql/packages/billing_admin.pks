create or replace package billing_admin as
  -- Customers, subscribers, plan changes and cycles. Nothing here
  -- commits; the caller decides when the change is done.

  function plan_id(p_code plans.code%type) return plans.plan_id%type;

  function add_customer(p_name varchar2, p_tax_rate number default 0.18)
    return customers.customer_id%type;

  -- Gives p_msisdn to a new subscriber on plan p_plan_code from the day
  -- p_from. Raises number_in_use if the number is anyone's on that day
  -- or later.
  function add_subscriber(
    p_customer_id  customers.customer_id%type,
    p_msisdn       subscribers.msisdn%type,
    p_plan_code    plans.code%type,
    p_from         date
  ) return subscribers.subscriber_id%type;

  -- Moves a subscriber to another plan from the day p_from. The bill run
  -- charges each plan's fee for the days it was on it.
  procedure change_plan(
    p_subscriber_id  subscribers.subscriber_id%type,
    p_plan_code      plans.code%type,
    p_from           date
  );

  -- Ends a subscriber's service at the start of the day p_on, after
  -- which the number can be given to someone else.
  procedure deactivate(p_subscriber_id subscribers.subscriber_id%type, p_on date);

  -- The cycle for the month p_month falls in, created if it's not there.
  function open_cycle(p_month date) return bill_cycles.cycle_id%type;
end billing_admin;
/
