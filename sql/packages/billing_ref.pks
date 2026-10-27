create or replace package billing_ref as
  -- The rules rating is built from, one call at a time. The batch rater
  -- in billing_rate caches the tables these read and applies the same
  -- rules from memory.

  -- Peak is Monday to Friday, from peak_from to before peak_to o'clock,
  -- except on public holidays.
  peak_from  constant pls_integer := 8;
  peak_to    constant pls_integer := 20;

  -- 'Y' if p_at is in peak hours on a weekday, ignoring holidays.
  function weekday_peak(p_at date) return varchar2 deterministic;

  -- 'Y' if a call starting at p_at is billed at peak rates.
  function is_peak(p_at date) return varchar2;

  -- The class of the longest prefix that matches p_called, or null.
  function dest_class(p_called varchar2) return varchar2;

  -- What a call of p_quantity units is billed as, in increments of
  -- p_first units and then p_next.
  function rated_units(p_quantity number, p_first number, p_next number) return number deterministic;

  -- The charge for p_units at p_price per p_price_units, to 4 places.
  function charge(p_units number, p_price number, p_price_units number) return number deterministic;
end billing_ref;
/
