-- Rated call records, one partition a month (interval partitioning adds
-- them as calls arrive), so a month's usage can be scanned, compressed or
-- dropped on its own. Every index is local to the partitions, so none of
-- that ever invalidates them.

create table cdrs (
  cdr_id          number generated always as identity,
  subscriber_id   number not null constraint cdrs_subscriber_fk references subscribers,
  service         varchar2(5) not null
                  constraint cdrs_service_ck check (service in ('VOICE', 'SMS', 'DATA')),
  called          varchar2(15)
                  constraint cdrs_called_ck check (called is null or regexp_like(called, '^[0-9]{3,15}$')),
  started_at      date not null,
  quantity        number not null
                  constraint cdrs_quantity_ck check (quantity >= 0 and quantity = trunc(quantity)),
  staging_id      number,
  status          varchar2(6) default 'NEW' not null
                  constraint cdrs_status_ck check (status in ('NEW', 'RATED', 'FAILED')),
  -- Filled in by rating.
  cycle_id        number constraint cdrs_cycle_fk references bill_cycles,
  late            varchar2(1) default 'N' not null
                  constraint cdrs_late_ck check (late in ('Y', 'N')),
  dest_class      varchar2(10),
  peak            varchar2(1),
  tariff_id       number constraint cdrs_tariff_fk references tariffs,
  rated_units     number,
  included_units  number,
  charged_units   number,
  amount          number(14,4),
  fail_reason     varchar2(200),
  rated_at        date,
  constraint cdrs_called_needed_ck check (service = 'DATA' or called is not null),
  constraint cdrs_rated_ck check (status <> 'RATED' or (cycle_id is not null and amount is not null))
)
partition by range (started_at) interval (numtoyminterval(1, 'MONTH'))
(partition cdrs_old values less than (date '2024-01-01'));

-- A local unique index has to include the partition key, so the primary
-- key is (cdr_id, started_at); updates name both and touch one partition.
create unique index cdrs_pk_ix on cdrs (cdr_id, started_at) local;
alter table cdrs add constraint cdrs_pk primary key (cdr_id, started_at) using index cdrs_pk_ix;

-- Switches resend files. The same call twice is the same subscriber,
-- service, start and called number; the second copy fails this and the
-- loader rejects it as a duplicate.
create unique index cdrs_dedup_uk on cdrs (subscriber_id, service, started_at, called) local;

-- Rating reads NEW rows in subscriber and time order; the bill run reads
-- a cycle's rows.
create index cdrs_status_ix on cdrs (status, subscriber_id, started_at) local;
create index cdrs_cycle_ix on cdrs (cycle_id, subscriber_id) local;

-- How much of each allowance a subscriber has used in a cycle.
create table allowance_usage (
  subscriber_id  number not null references subscribers,
  cycle_id       number not null references bill_cycles,
  service        varchar2(5) not null,
  used_units     number not null constraint allowance_usage_used_ck check (used_units >= 0),
  constraint allowance_usage_pk primary key (subscriber_id, cycle_id, service)
);

create index allowance_usage_cycle_ix on allowance_usage (cycle_id);
