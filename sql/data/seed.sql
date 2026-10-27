-- Reference data for a small operator: three plans, a numbering plan
-- with country code 44 at home, and 2026's public holidays.

insert into dest_classes (dest_class, name, in_bundle) values ('LOCAL', 'local numbers', 'Y');
insert into dest_classes (dest_class, name, in_bundle) values ('NATIONAL', 'national numbers', 'Y');
insert into dest_classes (dest_class, name, in_bundle) values ('MOBILE', 'mobile numbers', 'Y');
insert into dest_classes (dest_class, name, in_bundle) values ('INTL', 'international numbers', 'N');
insert into dest_classes (dest_class, name, in_bundle) values ('PREMIUM', 'premium rate numbers', 'N');
insert into dest_classes (dest_class, name, in_bundle) values ('DATA', 'mobile data', 'Y');

insert into destinations (prefix, dest_class, name) values ('44', 'NATIONAL', 'United Kingdom');
insert into destinations (prefix, dest_class, name) values ('4420', 'LOCAL', 'London');
insert into destinations (prefix, dest_class, name) values ('447', 'MOBILE', 'United Kingdom mobile');
insert into destinations (prefix, dest_class, name) values ('449', 'PREMIUM', 'United Kingdom premium rate');
insert into destinations (prefix, dest_class, name) values ('1', 'INTL', 'United States and Canada');
insert into destinations (prefix, dest_class, name) values ('33', 'INTL', 'France');
insert into destinations (prefix, dest_class, name) values ('49', 'INTL', 'Germany');
insert into destinations (prefix, dest_class, name) values ('353', 'INTL', 'Ireland');
insert into destinations (prefix, dest_class, name) values ('61', 'INTL', 'Australia');
insert into destinations (prefix, dest_class, name) values ('91', 'INTL', 'India');

insert into plans (code, name, monthly_fee) values ('BASIC', 'Basic', 10.00);
insert into plans (code, name, monthly_fee) values ('PLUS', 'Plus', 25.00);
insert into plans (code, name, monthly_fee) values ('MAX', 'Max', 45.00);

-- Allowances: minutes (as seconds), texts and megabytes (as kilobytes).
insert into allowances (plan_id, service, units)
select p.plan_id, a.service, a.units
  from plans p
  join (select 'BASIC' code, 'VOICE' service, 100 * 60 units from dual union all
        select 'BASIC', 'SMS', 100 from dual union all
        select 'BASIC', 'DATA', 1024 * 1024 from dual union all
        select 'PLUS', 'VOICE', 300 * 60 from dual union all
        select 'PLUS', 'SMS', 500 from dual union all
        select 'PLUS', 'DATA', 5 * 1024 * 1024 from dual union all
        select 'MAX', 'VOICE', 1000 * 60 from dual union all
        select 'MAX', 'SMS', 2000 from dual union all
        select 'MAX', 'DATA', 20 * 1024 * 1024 from dual) a on a.code = p.code;

-- Calls are priced per minute: local and national by the minute at
-- peak, by the second after the first minute off peak; international
-- and premium rate by the minute. Texts per message, data per megabyte.
declare
  procedure tariff(
    p_service varchar2, p_class varchar2, p_period varchar2, p_first number, p_next number,
    p_basic number, p_plus number, p_max number, p_per number
  ) is
  begin
    insert into tariffs (plan_id, service, dest_class, period, first_units, next_units, price, price_units, valid_from)
    select plan_id, p_service, p_class, p_period, p_first, p_next,
           case code when 'BASIC' then p_basic when 'PLUS' then p_plus else p_max end,
           p_per, date '2024-01-01'
      from plans;
  end tariff;
begin
  tariff('VOICE', 'LOCAL',    'PEAK',    60, 60, 0.12, 0.10, 0.08, 60);
  tariff('VOICE', 'LOCAL',    'OFFPEAK', 60,  1, 0.06, 0.05, 0.04, 60);
  tariff('VOICE', 'NATIONAL', 'PEAK',    60, 60, 0.12, 0.10, 0.08, 60);
  tariff('VOICE', 'NATIONAL', 'OFFPEAK', 60,  1, 0.06, 0.05, 0.04, 60);
  tariff('VOICE', 'MOBILE',   'ANY',     60,  1, 0.15, 0.12, 0.10, 60);
  tariff('VOICE', 'INTL',     'ANY',     60, 60, 0.90, 0.75, 0.50, 60);
  tariff('VOICE', 'PREMIUM',  'ANY',     60, 60, 1.50, 1.50, 1.50, 60);
  tariff('SMS',   'LOCAL',    'ANY',      1,  1, 0.10, 0.08, 0.05, 1);
  tariff('SMS',   'NATIONAL', 'ANY',      1,  1, 0.10, 0.08, 0.05, 1);
  tariff('SMS',   'MOBILE',   'ANY',      1,  1, 0.10, 0.08, 0.05, 1);
  tariff('SMS',   'INTL',     'ANY',      1,  1, 0.30, 0.25, 0.20, 1);
  tariff('SMS',   'PREMIUM',  'ANY',      1,  1, 0.50, 0.50, 0.50, 1);
  tariff('DATA',  'DATA',     'ANY',      1,  1, 0.02, 0.015, 0.01, 1024);
end;
/

insert into holidays (holiday, name) values (date '2026-01-01', 'New Year''s Day');
insert into holidays (holiday, name) values (date '2026-04-03', 'Good Friday');
insert into holidays (holiday, name) values (date '2026-04-06', 'Easter Monday');
insert into holidays (holiday, name) values (date '2026-05-04', 'Early May bank holiday');
insert into holidays (holiday, name) values (date '2026-05-25', 'Spring bank holiday');
insert into holidays (holiday, name) values (date '2026-08-31', 'Summer bank holiday');
insert into holidays (holiday, name) values (date '2026-12-25', 'Christmas Day');
insert into holidays (holiday, name) values (date '2026-12-28', 'Boxing Day (substitute day)');

commit;
