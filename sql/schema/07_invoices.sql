-- One invoice per customer per cycle. Invoice numbers run without gaps
-- within a cycle (INV-202601-000001 and on), which tax authorities often
-- ask for and a sequence can't promise.

create table invoices (
  invoice_id   number generated always as identity primary key,
  invoice_no   varchar2(20) not null constraint invoices_no_uk unique,
  customer_id  number not null references customers,
  cycle_id     number not null references bill_cycles,
  subtotal     number(12,2) default 0 not null,
  tax          number(12,2) default 0 not null,
  total        number(12,2) default 0 not null,
  issued_at    date default sysdate not null,
  constraint invoices_customer_cycle_uk unique (customer_id, cycle_id),
  constraint invoices_total_ck check (total = subtotal + tax)
);

create index invoices_cycle_ix on invoices (cycle_id);

create table invoice_lines (
  invoice_id     number not null references invoices,
  line_no        number not null,
  kind           varchar2(10) not null
                 constraint invoice_lines_kind_ck check (kind in ('RECURRING', 'USAGE', 'ADJUSTMENT')),
  subscriber_id  number references subscribers,
  description    varchar2(200) not null,
  quantity       number,
  amount         number(12,2) not null,
  constraint invoice_lines_pk primary key (invoice_id, line_no)
);

create index invoice_lines_subscriber_ix on invoice_lines (subscriber_id);
