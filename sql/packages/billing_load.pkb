create or replace package body billing_load as

  type t_text is table of varchar2(400) index by pls_integer;
  type t_num  is table of number index by pls_integer;
  type t_date is table of date index by pls_integer;
  type t_code is table of pls_integer index by pls_integer;

  -- ORA-24381, raised at the end of a FORALL ... SAVE EXCEPTIONS that had
  -- rows fail.
  e_bulk_errors exception;
  pragma exception_init(e_bulk_errors, -24381);

  -- Field p_n of a comma separated line, trimmed and cut to fit staging.
  function field(p_line varchar2, p_n pls_integer) return varchar2 is
  begin
    return substr(trim(regexp_substr(p_line, '([^,]*)(,|$)', 1, p_n, null, 1)), 1, 100);
  end field;

  function stage_csv(p_file_name varchar2, p_csv clob) return pls_integer is
    l_len      pls_integer := dbms_lob.getlength(p_csv);
    l_pos      pls_integer := 1;
    l_end      pls_integer;
    l_line     varchar2(4000);
    l_line_no  pls_integer := 0;
    l_n        pls_integer := 0;
    l_staged   pls_integer := 0;
    l_nos      t_num;
    l_fields   t_num;
    l_msisdn   t_text;
    l_service  t_text;
    l_called   t_text;
    l_started  t_text;
    l_qty      t_text;

    procedure flush is
    begin
      forall i in 1 .. l_n
        insert into cdr_staging (file_name, line_no, fields, msisdn, service, called, started_at, quantity)
        values (p_file_name, l_nos(i), l_fields(i), l_msisdn(i), l_service(i), l_called(i), l_started(i), l_qty(i));
      l_staged := l_staged + l_n;
      l_n := 0;
    end flush;
  begin
    while l_pos <= l_len loop
      l_end := dbms_lob.instr(p_csv, chr(10), l_pos);
      if l_end = 0 then
        l_end := l_len + 1;
      end if;
      l_line := null;
      if l_end > l_pos then
        l_line := rtrim(dbms_lob.substr(p_csv, least(l_end - l_pos, 4000), l_pos), chr(13));
      end if;
      l_pos := l_end + 1;
      l_line_no := l_line_no + 1;

      if trim(l_line) is null or (l_line_no = 1 and lower(l_line) like 'msisdn,%') then
        continue;
      end if;
      l_n := l_n + 1;
      l_nos(l_n) := l_line_no;
      l_fields(l_n) := regexp_count(l_line, ',') + 1;
      l_msisdn(l_n) := field(l_line, 1);
      l_service(l_n) := field(l_line, 2);
      l_called(l_n) := field(l_line, 3);
      l_started(l_n) := field(l_line, 4);
      l_qty(l_n) := field(l_line, 5);
      if l_n = 1000 then
        flush;
      end if;
    end loop;
    flush;
    return l_staged;
  end stage_csv;

  function stage_file(p_directory varchar2, p_file_name varchar2) return pls_integer is
    l_directory  varchar2(128) := dbms_assert.simple_sql_name(p_directory);
    l_n          pls_integer;
  begin
    -- Oracle refuses binds in a statement with an inline external table
    -- (ORA-14355), so the names go into its text, and both are checked
    -- first: a directory has to be a plain identifier and a file
    -- a plain name, with no path in it.
    if not regexp_like(p_file_name, '^[A-Za-z0-9][A-Za-z0-9._-]{0,99}$') then
      raise_application_error(billing_errors.bad_file, 'not a plain file name: "' || p_file_name || '"');
    end if;

    -- Serial, so rownum follows the file's line order. A line has to be
    -- trimmed of CR here, as stage_csv does, before it's split.
    execute immediate q'[
      insert into cdr_staging (file_name, line_no, fields, msisdn, service, called, started_at, quantity)
      select ]' || dbms_assert.enquote_literal(p_file_name) || q'[, line_no, regexp_count(line, ',') + 1,
             substr(trim(regexp_substr(line, '([^,]*)(,|$)', 1, 1, null, 1)), 1, 100),
             substr(trim(regexp_substr(line, '([^,]*)(,|$)', 1, 2, null, 1)), 1, 100),
             substr(trim(regexp_substr(line, '([^,]*)(,|$)', 1, 3, null, 1)), 1, 100),
             substr(trim(regexp_substr(line, '([^,]*)(,|$)', 1, 4, null, 1)), 1, 100),
             substr(trim(regexp_substr(line, '([^,]*)(,|$)', 1, 5, null, 1)), 1, 100)
        from (select rownum as line_no, rtrim(line, chr(13)) as line
                from external ((line varchar2(4000))
                       type oracle_loader
                       default directory ]' || l_directory || q'[
                       access parameters (
                         records delimited by newline
                         nobadfile nologfile nodiscardfile
                         fields notrim missing field values are null
                         (line position(1:4000) char(4000)))
                       location (]' || dbms_assert.enquote_literal(p_file_name) || q'[)
                       reject limit unlimited) f)
       where trim(line) is not null
         and not (line_no = 1 and lower(line) like 'msisdn,%')]';
    l_n := sql%rowcount;
    billing_log.info('billing_load', 'staged ' || l_n || ' lines from ' || l_directory || '/' || p_file_name);
    return l_n;
  end stage_file;

  -- Why a row failed the insert, for the codes the table's constraints
  -- raise; anything else gets Oracle's own message.
  function reason_for(p_code pls_integer) return varchar2 is
  begin
    return case p_code
             when 1 then 'duplicate of a call record already loaded'
             when 2291 then 'subscriber missing'
             else substr(sqlerrm(-p_code), 1, 400)
           end;
  end reason_for;

  function load_staged(p_max_rows pls_integer default 100000, p_batch_size pls_integer default 1000)
    return pls_integer
  is
    -- The case expression matches cdr_staging_new_ix, which holds only
    -- the NEW rows.
    cursor c_new is
      select staging_id, fields, msisdn, service, called, started_at, quantity
        from cdr_staging
       where case status when 'NEW' then staging_id end is not null
       order by staging_id
       fetch first p_max_rows rows only;
    type t_new is table of c_new%rowtype index by pls_integer;

    l_rows      t_new;
    l_reason    t_text;
    l_msisdn    t_text;
    l_service   t_text;
    l_called    t_text;
    l_start     t_date;
    l_qty       t_num;
    l_status    t_text;
    l_ids       t_num;
    l_inserted  t_num;
    l_failed    t_code;
    l_done      pls_integer := 0;

    -- Checks row i and fills in its parsed fields, or its reason for
    -- rejection. The database's constraints would catch most of this
    -- too, but only with a bare error code; this way the reason names
    -- the field and the value.
    procedure check_row(i pls_integer) is
      r c_new%rowtype := l_rows(i);
    begin
      l_reason(i) := null;
      l_msisdn(i) := null;
      l_service(i) := null;
      l_called(i) := null;
      l_start(i) := null;
      l_qty(i) := null;

      if r.fields <> 5 then
        l_reason(i) := 'expected 5 fields, found ' || r.fields;
        return;
      end if;

      l_msisdn(i) := regexp_replace(r.msisdn, '[+ ()-]');
      if l_msisdn(i) is null or not regexp_like(l_msisdn(i), '^[0-9]{6,15}$') then
        l_reason(i) := 'bad msisdn "' || r.msisdn || '"';
        return;
      end if;

      l_service(i) := upper(r.service);
      if l_service(i) is null or l_service(i) not in ('VOICE', 'SMS', 'DATA') then
        l_reason(i) := 'unknown service "' || r.service || '"';
        return;
      end if;

      -- Data sessions carry an access point name, not a number.
      if l_service(i) <> 'DATA' then
        l_called(i) := regexp_replace(r.called, '[+ ()-]');
        if l_called(i) is null then
          l_reason(i) := l_service(i) || ' record without a called number';
          return;
        elsif not regexp_like(l_called(i), '^[0-9]{3,15}$') then
          l_reason(i) := 'bad called number "' || r.called || '"';
          return;
        end if;
      end if;

      if r.started_at is null then
        l_reason(i) := 'missing start time';
        return;
      end if;
      begin
        l_start(i) := to_date(r.started_at, 'FXYYYY-MM-DD"T"HH24:MI:SS');
      exception
        -- to_date raises one of a dozen ORA-018xx errors depending on
        -- what's wrong; all of them mean the same thing here.
        when others then
          l_reason(i) := 'bad start time "' || r.started_at || '", expected YYYY-MM-DDTHH:MI:SS';
          return;
      end;

      if r.quantity is null or not regexp_like(r.quantity, '^[0-9]{1,12}$') then
        l_reason(i) := 'quantity "' || r.quantity || '" is not a whole number';
        return;
      end if;
      l_qty(i) := to_number(r.quantity);
    end check_row;
  begin
    billing_errors.take_lock('LOADER');
    open c_new;
    loop
      fetch c_new bulk collect into l_rows limit p_batch_size;
      exit when l_rows.count = 0;

      l_failed.delete;
      for i in 1 .. l_rows.count loop
        check_row(i);
      end loop;

      -- One statement for the whole batch. A row that fails a check above
      -- inserts nothing (the where clause), and so does one whose number
      -- nobody had at the time; SQL%BULK_ROWCOUNT tells those apart from
      -- the rows that went in. A row the table refuses, a duplicate say,
      -- is set aside by SAVE EXCEPTIONS while the rest carry on.
      begin
        forall i in 1 .. l_rows.count save exceptions
          insert into cdrs (subscriber_id, service, called, started_at, quantity, staging_id)
          select s.subscriber_id, l_service(i), l_called(i), l_start(i), l_qty(i), l_rows(i).staging_id
            from subscribers s
           where l_reason(i) is null
             and s.msisdn = l_msisdn(i)
             and s.active_from <= l_start(i)
             and (s.active_to is null or s.active_to > l_start(i));
        for i in 1 .. l_rows.count loop
          l_inserted(i) := sql%bulk_rowcount(i);
        end loop;
      exception
        when e_bulk_errors then
          for j in 1 .. sql%bulk_exceptions.count loop
            l_failed(sql%bulk_exceptions(j).error_index) := sql%bulk_exceptions(j).error_code;
          end loop;
          for i in 1 .. l_rows.count loop
            if not l_failed.exists(i) then
              l_inserted(i) := sql%bulk_rowcount(i);
            end if;
          end loop;
      end;

      for i in 1 .. l_rows.count loop
        l_ids(i) := l_rows(i).staging_id;
        l_status(i) := 'REJECTED';
        if l_reason(i) is not null then
          null;
        elsif l_failed.exists(i) then
          l_reason(i) := reason_for(l_failed(i));
        elsif l_inserted(i) = 0 then
          l_reason(i) := 'nobody had ' || l_msisdn(i) || ' at ' || to_char(l_start(i), 'YYYY-MM-DD HH24:MI:SS');
        else
          l_status(i) := 'LOADED';
        end if;
      end loop;

      forall i in 1 .. l_rows.count
        update cdr_staging
           set status = l_status(i),
               reject_reason = l_reason(i),
               processed_at = systimestamp
         where staging_id = l_ids(i);

      l_done := l_done + l_rows.count;
      billing_log.progress('load_staged', l_done);
    end loop;
    close c_new;
    billing_log.idle;
    return l_done;
  exception
    when others then
      if c_new%isopen then
        close c_new;
      end if;
      billing_log.idle;
      raise;
  end load_staged;

end billing_load;
/
