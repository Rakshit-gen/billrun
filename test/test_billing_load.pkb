create or replace package body test_billing_load as

  nl constant varchar2(1) := chr(10);
  header constant varchar2(50) := 'msisdn,service,called,started_at,quantity';

  procedure setup is
  begin
    test_fixture.setup;
  end setup;

  function staged(p_file varchar2, p_line pls_integer) return cdr_staging%rowtype is
    l cdr_staging%rowtype;
  begin
    select * into l from cdr_staging where file_name = p_file and line_no = p_line;
    return l;
  end staged;

  procedure stages_lines is
    l_n     pls_integer;
    l_rows  pls_integer;
    l_last  pls_integer;
  begin
    l_n := billing_load.stage_csv('lines.csv',
      header || nl
      || '447000999001,VOICE,441614960000,2031-01-06T10:00:00,61' || chr(13) || nl
      || nl
      || '447000999001,SMS,447700900123,2031-01-06T10:05:00,1' || chr(13) || nl);
    ut.expect(l_n).to_equal(2);
    select count(*), max(line_no) into l_rows, l_last from cdr_staging where file_name = 'lines.csv';
    ut.expect(l_rows).to_equal(2);
    ut.expect(l_last).to_equal(4);
    ut.expect(staged('lines.csv', 2).quantity).to_equal('61');
    ut.expect(staged('lines.csv', 4).service).to_equal('SMS');
  end stages_lines;

  procedure loads_good_rows is
    l_n       pls_integer;
    l_called  cdrs.called%type;
    l_data    pls_integer;
  begin
    l_n := billing_load.stage_csv('good.csv',
      '447000999001,VOICE,+44 161 496 0000,2031-01-06T10:00:00,61' || nl
      || '447000999001,DATA,internet,2031-01-06T11:00:00,5000');
    l_n := billing_load.load_staged;
    ut.expect(l_n).to_equal(2);
    ut.expect(staged('good.csv', 1).status).to_equal('LOADED');
    ut.expect(staged('good.csv', 2).status).to_equal('LOADED');

    select called into l_called
      from cdrs
     where subscriber_id = test_fixture.g_subscriber and service = 'VOICE';
    ut.expect(l_called).to_equal('441614960000');
    select count(*) into l_data
      from cdrs
     where subscriber_id = test_fixture.g_subscriber and service = 'DATA' and called is null;
    ut.expect(l_data).to_equal(1);
  end loads_good_rows;

  procedure rejects_with_reasons is
    l_n pls_integer;
  begin
    l_n := billing_load.stage_csv('bad.csv',
      header || nl
      || '447000999001,VOICE,441614960000,06/01/2031 10:00,61' || nl
      || '447000999002,VOICE,441614960000,2031-01-06T10:00:00,61' || nl
      || '447000999001,VOICE,441614960000,2030-12-31T10:00:00,61' || nl
      || '447000999001,FAX,441614960000,2031-01-06T10:00:00,61' || nl
      || '447000999001,VOICE,441614960000,2031-01-06T10:00:00' || nl
      || '447000999001,VOICE,,2031-01-06T10:00:00,61' || nl
      || '447000999001,VOICE,441614960000,2031-01-06T10:00:00,1.5' || nl
      || 'not-a-number,VOICE,441614960000,2031-01-06T10:00:00,61');
    l_n := billing_load.load_staged;
    ut.expect(l_n).to_equal(8);

    ut.expect(staged('bad.csv', 2).reject_reason).to_be_like('bad start time "06/01/2031 10:00"%');
    ut.expect(staged('bad.csv', 3).reject_reason).to_equal('nobody had 447000999002 at 2031-01-06 10:00:00');
    -- The line only became this number's on 2031-01-01.
    ut.expect(staged('bad.csv', 4).reject_reason).to_equal('nobody had 447000999001 at 2030-12-31 10:00:00');
    ut.expect(staged('bad.csv', 5).reject_reason).to_equal('unknown service "FAX"');
    ut.expect(staged('bad.csv', 6).reject_reason).to_equal('expected 5 fields, found 4');
    ut.expect(staged('bad.csv', 7).reject_reason).to_equal('VOICE record without a called number');
    ut.expect(staged('bad.csv', 8).reject_reason).to_equal('quantity "1.5" is not a whole number');
    ut.expect(staged('bad.csv', 9).reject_reason).to_equal('bad msisdn "not-a-number"');
    for line in 2 .. 9 loop
      ut.expect(staged('bad.csv', line).status).to_equal('REJECTED');
    end loop;
  end rejects_with_reasons;

  procedure rejects_duplicates is
    l_n     pls_integer;
    l_line  constant varchar2(100) := '447000999001,VOICE,441614960000,2031-01-06T10:00:00,61';
    l_cdrs  pls_integer;
  begin
    -- Twice in one file: the second copy fails inside the same batch.
    l_n := billing_load.stage_csv('first.csv', l_line || nl || l_line);
    l_n := billing_load.load_staged;
    ut.expect(staged('first.csv', 1).status).to_equal('LOADED');
    ut.expect(staged('first.csv', 2).reject_reason).to_equal('duplicate of a call record already loaded');

    -- And resent in a later file.
    l_n := billing_load.stage_csv('resent.csv', l_line);
    l_n := billing_load.load_staged;
    ut.expect(staged('resent.csv', 1).reject_reason).to_equal('duplicate of a call record already loaded');

    select count(*) into l_cdrs from cdrs where subscriber_id = test_fixture.g_subscriber;
    ut.expect(l_cdrs).to_equal(1);
  end rejects_duplicates;

  procedure loads_once is
    l_n pls_integer;
  begin
    l_n := billing_load.stage_csv('once.csv', '447000999001,SMS,447700900123,2031-01-06T10:05:00,1');
    l_n := billing_load.load_staged;
    ut.expect(l_n).to_equal(1);
    l_n := billing_load.load_staged;
    ut.expect(l_n).to_equal(0);
  end loads_once;

  -- Needs the BILLRUN_IN directory, readable and writable; scripts/ci.sh
  -- creates it.
  procedure stages_file is
    c_dir   constant varchar2(30) := 'BILLRUN_IN';
    c_file  constant varchar2(30) := 'switch-test.csv';
    l_out   utl_file.file_type;
    l_n     pls_integer;
    l_from_file  sys_refcursor;
    l_from_clob  sys_refcursor;
  begin
    l_out := utl_file.fopen(c_dir, c_file, 'w');
    utl_file.put_line(l_out, header);
    utl_file.put_line(l_out, '447000999001,VOICE,441614960000,2031-01-06T10:00:00,61' || chr(13));
    utl_file.put_line(l_out, '');
    utl_file.put_line(l_out, ' 447000999001 , sms ,447700900123,2031-01-06T10:05:00,1');
    utl_file.put_line(l_out, 'too,few,fields');
    utl_file.fclose(l_out);

    l_n := billing_load.stage_file(c_dir, c_file);
    utl_file.fremove(c_dir, c_file);
    ut.expect(l_n).to_equal(3);

    l_n := billing_load.stage_csv('switch-clob.csv',
      header || nl
      || '447000999001,VOICE,441614960000,2031-01-06T10:00:00,61' || chr(13) || nl
      || nl
      || ' 447000999001 , sms ,447700900123,2031-01-06T10:05:00,1' || nl
      || 'too,few,fields' || nl);
    open l_from_file for
      select line_no, fields, msisdn, service, called, started_at, quantity
        from cdr_staging where file_name = c_file order by line_no;
    open l_from_clob for
      select line_no, fields, msisdn, service, called, started_at, quantity
        from cdr_staging where file_name = 'switch-clob.csv' order by line_no;
    ut.expect(l_from_file).to_equal(l_from_clob);
  exception
    when others then
      if utl_file.is_open(l_out) then
        utl_file.fclose(l_out);
      end if;
      raise;
  end stages_file;

  procedure refuses_paths is
    l_n pls_integer;
  begin
    l_n := billing_load.stage_file('BILLRUN_IN', '../etc/passwd');
  end refuses_paths;

end test_billing_load;
/
