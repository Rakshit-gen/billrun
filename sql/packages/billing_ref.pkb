create or replace package body billing_ref as

  function weekday_peak(p_at date) return varchar2 deterministic is
    -- Days since Monday. trunc(d, 'IW') is the Monday of d's ISO week,
    -- which doesn't depend on NLS_TERRITORY the way to_char(d, 'D') does.
    l_day   pls_integer := trunc(p_at) - trunc(p_at, 'IW');
    l_hour  pls_integer := to_number(to_char(p_at, 'HH24'));
  begin
    if l_day < 5 and l_hour >= peak_from and l_hour < peak_to then
      return 'Y';
    end if;
    return 'N';
  end weekday_peak;

  function is_peak(p_at date) return varchar2 is
    l_holidays pls_integer;
  begin
    if weekday_peak(p_at) = 'N' then
      return 'N';
    end if;
    select count(*) into l_holidays from holidays where holiday = trunc(p_at);
    return case when l_holidays > 0 then 'N' else 'Y' end;
  end is_peak;

  function dest_class(p_called varchar2) return varchar2 is
    l_class destinations.dest_class%type;
  begin
    select dest_class into l_class
      from destinations
     where p_called like prefix || '%'
     order by length(prefix) desc
     fetch first 1 row only;
    return l_class;
  exception
    when no_data_found then
      return null;
  end dest_class;

  function rated_units(p_quantity number, p_first number, p_next number) return number deterministic is
  begin
    if p_quantity <= 0 then
      return 0;
    elsif p_quantity <= p_first then
      return p_first;
    end if;
    return p_first + ceil((p_quantity - p_first) / p_next) * p_next;
  end rated_units;

  function charge(p_units number, p_price number, p_price_units number) return number deterministic is
  begin
    return round(p_units * p_price / p_price_units, 4);
  end charge;

end billing_ref;
/
