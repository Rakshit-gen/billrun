-- Customers pay the invoices; subscribers are their lines. A number can
-- be given to someone else once its last subscriber leaves, so msisdn is
-- unique only over time, and call records are matched on the number and
-- the time of the call.

create table customers (
  customer_id  number generated always as identity primary key,
  name         varchar2(200) not null,
  tax_rate     number(5,4) default 0.18 not null
               constraint customers_tax_ck check (tax_rate between 0 and 1),
  -- Days from the invoice to its due date.
  terms_days   number(3) default 14 not null
               constraint customers_terms_ck check (terms_days between 0 and 120),
  -- SUSPENDED by dunning once an invoice is long overdue, ACTIVE again
  -- when nothing is overdue.
  status       varchar2(9) default 'ACTIVE' not null
               constraint customers_status_ck check (status in ('ACTIVE', 'SUSPENDED')),
  created_at   timestamp default systimestamp not null
);

create table subscribers (
  subscriber_id  number generated always as identity primary key,
  customer_id    number not null references customers,
  msisdn         varchar2(15) not null
                 constraint subscribers_msisdn_ck check (regexp_like(msisdn, '^[0-9]{6,15}$')),
  active_from    date not null,
  active_to      date,
  constraint subscribers_days_ck check (active_from = trunc(active_from) and (active_to is null or active_to = trunc(active_to))),
  constraint subscribers_range_ck check (active_to is null or active_to > active_from)
);

create index subscribers_customer_ix on subscribers (customer_id);
create index subscribers_msisdn_ix on subscribers (msisdn, active_from);

-- Which plan a subscriber was on, day by day. A plan change closes the
-- open segment and starts a new one, which is what the bill run prorates.
create table subscriber_plans (
  subscriber_id  number not null references subscribers,
  plan_id        number not null references plans,
  valid_from     date not null,
  valid_to       date,
  constraint subscriber_plans_pk primary key (subscriber_id, valid_from),
  constraint subscriber_plans_days_ck check (valid_from = trunc(valid_from) and (valid_to is null or valid_to = trunc(valid_to))),
  constraint subscriber_plans_range_ck check (valid_to is null or valid_to > valid_from)
);

create index subscriber_plans_plan_ix on subscriber_plans (plan_id);
