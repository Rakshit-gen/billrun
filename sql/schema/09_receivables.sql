-- What customers pay and which invoices it went to. A payment is spread
-- over the oldest unpaid invoices first; what's left over waits for the
-- next invoice. Invoices themselves never change once billed, so what's
-- owed is always total minus allocations.

create table payments (
  payment_id   number generated always as identity primary key,
  customer_id  number not null references customers,
  amount       number(12,2) not null constraint payments_amount_ck check (amount > 0),
  received_on  date not null constraint payments_day_ck check (received_on = trunc(received_on)),
  method       varchar2(4) not null constraint payments_method_ck check (method in ('BANK', 'CARD', 'CASH')),
  -- The bank's or card processor's reference. Feeds get resent; the
  -- unique key makes taking the same payment twice impossible.
  reference    varchar2(60) not null constraint payments_reference_uk unique,
  created_at   timestamp default systimestamp not null
);

create index payments_customer_ix on payments (customer_id, received_on);

create table payment_allocations (
  payment_id    number not null references payments,
  invoice_id    number not null references invoices,
  amount        number(12,2) not null constraint payment_allocations_amount_ck check (amount > 0),
  allocated_at  timestamp default systimestamp not null,
  constraint payment_allocations_pk primary key (payment_id, invoice_id)
);

create index payment_allocations_invoice_ix on payment_allocations (invoice_id);

-- Each step taken on an overdue invoice, once: a reminder, a warning,
-- then suspension of the customer.
create table dunning_actions (
  invoice_id    number not null references invoices,
  step          number(1) not null constraint dunning_actions_step_ck check (step between 1 and 3),
  action        varchar2(8) not null constraint dunning_actions_action_ck check (action in ('REMINDER', 'WARNING', 'SUSPEND')),
  days_overdue  number not null,
  open_amount   number(12,2) not null,
  taken_on      date not null,
  constraint dunning_actions_pk primary key (invoice_id, step)
);
