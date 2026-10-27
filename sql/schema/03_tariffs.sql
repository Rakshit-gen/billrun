-- What a plan charges. A call is billed in increments: the first
-- first_units, then next_units at a time, so with 60 and 60 a 61 second
-- call is billed as 120 seconds, and with 60 and 1 as 61. The price is
-- per price_units of what's billed. Units are seconds for VOICE, messages
-- for SMS and kilobytes for DATA.
--
-- A tariff for PEAK or OFFPEAK wins over one for ANY. Prices change by
-- adding a row with a later valid_from and closing the old one.

create table tariffs (
  tariff_id    number generated always as identity primary key,
  plan_id      number not null references plans,
  service      varchar2(5) not null
               constraint tariffs_service_ck check (service in ('VOICE', 'SMS', 'DATA')),
  dest_class   varchar2(10) not null references dest_classes,
  period       varchar2(7) not null
               constraint tariffs_period_ck check (period in ('PEAK', 'OFFPEAK', 'ANY')),
  first_units  number not null constraint tariffs_first_ck check (first_units > 0),
  next_units   number not null constraint tariffs_next_ck check (next_units > 0),
  price        number(12,6) not null constraint tariffs_price_ck check (price >= 0),
  price_units  number not null constraint tariffs_price_units_ck check (price_units > 0),
  valid_from   date not null,
  valid_to     date,
  constraint tariffs_uk unique (plan_id, service, dest_class, period, valid_from),
  constraint tariffs_range_ck check (valid_to is null or valid_to > valid_from)
);

create index tariffs_class_ix on tariffs (dest_class);

-- Units a plan includes each cycle, in the same units as the tariffs.
-- They're used up by calls to classes in the bundle, earliest call first.
create table allowances (
  plan_id  number not null references plans,
  service  varchar2(5) not null
           constraint allowances_service_ck check (service in ('VOICE', 'SMS', 'DATA')),
  units    number not null constraint allowances_units_ck check (units > 0),
  constraint allowances_pk primary key (plan_id, service)
);
