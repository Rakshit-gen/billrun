create or replace package body test_billing_ref as

  function ts(p_text varchar2) return date is
  begin
    return to_date(p_text, 'YYYY-MM-DD HH24:MI:SS');
  end ts;

  procedure weekday_peak is
  begin
    ut.expect(billing_ref.is_peak(ts('2031-01-06 07:59:59'))).to_equal('N');
    ut.expect(billing_ref.is_peak(ts('2031-01-06 08:00:00'))).to_equal('Y');
    ut.expect(billing_ref.is_peak(ts('2031-01-06 19:59:59'))).to_equal('Y');
    ut.expect(billing_ref.is_peak(ts('2031-01-06 20:00:00'))).to_equal('N');
    ut.expect(billing_ref.is_peak(ts('2031-01-10 12:00:00'))).to_equal('Y');
  end weekday_peak;

  procedure weekend is
  begin
    ut.expect(billing_ref.is_peak(ts('2031-01-04 12:00:00'))).to_equal('N');
    ut.expect(billing_ref.is_peak(ts('2031-01-05 12:00:00'))).to_equal('N');
  end weekend;

  procedure holiday is
  begin
    insert into holidays (holiday, name) values (date '2031-01-07', 'Test holiday');
    ut.expect(billing_ref.weekday_peak(ts('2031-01-07 12:00:00'))).to_equal('Y');
    ut.expect(billing_ref.is_peak(ts('2031-01-07 12:00:00'))).to_equal('N');
    ut.expect(billing_ref.is_peak(ts('2031-01-08 12:00:00'))).to_equal('Y');
  end holiday;

  procedure longest_prefix is
  begin
    ut.expect(billing_ref.dest_class('447700900123')).to_equal('MOBILE');
    ut.expect(billing_ref.dest_class('442079460000')).to_equal('LOCAL');
    ut.expect(billing_ref.dest_class('441614960000')).to_equal('NATIONAL');
    ut.expect(billing_ref.dest_class('33140000000')).to_equal('INTL');
  end longest_prefix;

  procedure no_prefix is
  begin
    ut.expect(billing_ref.dest_class('8613800000000')).to_be_null();
  end no_prefix;

  procedure increments is
  begin
    ut.expect(billing_ref.rated_units(0, 60, 60)).to_equal(0);
    ut.expect(billing_ref.rated_units(1, 60, 60)).to_equal(60);
    ut.expect(billing_ref.rated_units(60, 60, 60)).to_equal(60);
    ut.expect(billing_ref.rated_units(61, 60, 60)).to_equal(120);
    ut.expect(billing_ref.rated_units(61, 60, 1)).to_equal(61);
    ut.expect(billing_ref.rated_units(121, 60, 60)).to_equal(180);
  end increments;

  procedure charges is
  begin
    ut.expect(billing_ref.charge(120, 0.10, 60)).to_equal(0.2);
    ut.expect(billing_ref.charge(1536, 0.01, 1024)).to_equal(0.015);
    ut.expect(billing_ref.charge(1, 0.01, 1024)).to_equal(0);
  end charges;

end test_billing_ref;
/
