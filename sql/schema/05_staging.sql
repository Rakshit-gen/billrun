-- Call records as they arrive from the switches, one row per CSV line,
-- all text. The loader checks each one and moves it to cdrs, or marks it
-- REJECTED with the reason, so nothing a switch sent is ever lost.

create table cdr_staging (
  staging_id     number generated always as identity primary key,
  file_name      varchar2(200) not null,
  line_no        number not null,
  fields         number not null,
  msisdn         varchar2(100),
  service        varchar2(100),
  called         varchar2(100),
  started_at     varchar2(100),
  quantity       varchar2(100),
  status         varchar2(8) default 'NEW' not null
                 constraint cdr_staging_status_ck check (status in ('NEW', 'LOADED', 'REJECTED')),
  reject_reason  varchar2(400),
  staged_at      timestamp default systimestamp not null,
  processed_at   timestamp,
  constraint cdr_staging_line_uk unique (file_name, line_no)
);

-- Only rows still to load are in this index: the expression is null for
-- the rest, and Oracle doesn't index rows whose keys are all null. It
-- stays small however many million rows have been loaded.
create index cdr_staging_new_ix on cdr_staging (case status when 'NEW' then staging_id end);
