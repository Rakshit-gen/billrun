-- Row and table types for billing_ar.aging, a pipelined function: SQL
-- can select from it like a view that takes an as-of date.

create or replace type ar_aging_row as object (
  customer_id   number,
  name          varchar2(200),
  status        varchar2(9),
  not_due       number(12,2),
  days_1_30     number(12,2),
  days_31_60    number(12,2),
  days_61_90    number(12,2),
  days_over_90  number(12,2),
  total_open    number(12,2),
  unallocated   number(12,2)
);
/

create or replace type ar_aging_tab as table of ar_aging_row;
/
