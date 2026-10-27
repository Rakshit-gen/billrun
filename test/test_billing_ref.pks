create or replace package test_billing_ref as
  --%suite(billing_ref: the rules rating is built from)

  --%test(Weekdays from 08:00 to before 20:00 are peak)
  procedure weekday_peak;

  --%test(Weekends are off peak)
  procedure weekend;

  --%test(Public holidays are off peak)
  procedure holiday;

  --%test(The longest matching prefix decides the class)
  procedure longest_prefix;

  --%test(A number no prefix matches has no class)
  procedure no_prefix;

  --%test(Calls are rounded up to the billing increments)
  procedure increments;

  --%test(Charges are per price units, to four places)
  procedure charges;
end test_billing_ref;
/
