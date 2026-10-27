-- Reference data: plans, destination classes, the numbering plan that
-- maps a called number to a class, and public holidays (rated off peak).

create table plans (
  plan_id      number generated always as identity primary key,
  code         varchar2(20)  not null constraint plans_code_uk unique,
  name         varchar2(100) not null,
  monthly_fee  number(10,2)  not null constraint plans_fee_ck check (monthly_fee >= 0)
);

-- A class groups destinations that cost the same. Calls to classes
-- outside the bundle never use the plan's allowance.
create table dest_classes (
  dest_class  varchar2(10) primary key,
  name        varchar2(50) not null,
  in_bundle   varchar2(1) default 'Y' not null
              constraint dest_classes_bundle_ck check (in_bundle in ('Y', 'N'))
);

-- Called numbers are matched on their longest prefix, so 447 (mobile)
-- wins over 44 (national) for 447700900123.
create table destinations (
  prefix      varchar2(15) primary key
              constraint destinations_prefix_ck check (regexp_like(prefix, '^[0-9]+$')),
  dest_class  varchar2(10) not null references dest_classes,
  name        varchar2(100) not null
);

create index destinations_class_ix on destinations (dest_class);

create table holidays (
  holiday  date primary key
           constraint holidays_day_ck check (holiday = trunc(holiday)),
  name     varchar2(100) not null
);
