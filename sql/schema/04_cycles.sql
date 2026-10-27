-- A bill cycle is a calendar month. Once billed it's closed: calls that
-- arrive late for it are rated into the next open cycle instead.

create table bill_cycles (
  cycle_id      number generated always as identity primary key,
  period_start  date not null constraint bill_cycles_start_uk unique,
  period_end    date not null,
  status        varchar2(6) default 'OPEN' not null
                constraint bill_cycles_status_ck check (status in ('OPEN', 'BILLED')),
  billed_at     timestamp,
  constraint bill_cycles_range_ck check (period_end > period_start),
  constraint bill_cycles_billed_ck check ((status = 'BILLED' and billed_at is not null) or (status = 'OPEN' and billed_at is null))
);

-- Credits and one-off charges, put on the customer's next invoice.
create table adjustments (
  adjustment_id  number generated always as identity primary key,
  customer_id    number not null references customers,
  cycle_id       number not null references bill_cycles,
  amount         number(12,2) not null constraint adjustments_amount_ck check (amount <> 0),
  reason         varchar2(200) not null,
  created_at     timestamp default systimestamp not null
);

create index adjustments_cycle_ix on adjustments (cycle_id, customer_id);
create index adjustments_customer_ix on adjustments (customer_id);
