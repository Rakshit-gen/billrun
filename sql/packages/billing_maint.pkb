create or replace package body billing_maint as

  -- The upper bound of a partition. high_value is a LONG holding SQL
  -- text such as TO_DATE(' 2030-04-01 00:00:00', ...); PL/SQL can read
  -- a LONG into a string, and the database can evaluate the text.
  function upper_bound(p_high_value varchar2) return date is
    l_date date;
  begin
    execute immediate 'select ' || p_high_value || ' from dual' into l_date;
    return l_date;
  end upper_bound;

  procedure compress_month(p_month date) is
    l_month date := trunc(p_month, 'MM');
  begin
    execute immediate
      'alter table cdrs move partition for (date ''' || to_char(l_month, 'YYYY-MM-DD') || ''')'
      || ' row store compress basic online update indexes';
    billing_log.info('billing_maint', 'compressed call records for ' || to_char(l_month, 'YYYY-MM'));
  end compress_month;

  function partition_of(p_month date) return varchar2 is
    l_month date := trunc(p_month, 'MM');
  begin
    for p in (select partition_name, high_value
                from user_tab_partitions
               where table_name = 'CDRS'
               order by partition_position) loop
      if l_month < upper_bound(p.high_value) then
        -- The first partition whose bound is above the month; it's that
        -- month's only if the bound is the month after.
        return case when upper_bound(p.high_value) = add_months(l_month, 1) then p.partition_name end;
      end if;
    end loop;
    return null;
  end partition_of;

  function purge_before(p_before date, p_from date default null) return pls_integer is
    l_before   date := trunc(p_before, 'MM');
    l_from     date := trunc(nvl(p_from, date '0001-01-01'), 'MM');
    l_upper    date;
    l_lower    date;
    l_open     pls_integer;
    l_dropped  pls_integer := 0;
  begin
    -- interval = 'YES' leaves out the first, range, partition, which an
    -- interval partitioned table can't drop.
    for p in (select partition_name, high_value
                from user_tab_partitions
               where table_name = 'CDRS'
                 and interval = 'YES'
               order by partition_position) loop
      l_upper := upper_bound(p.high_value);
      exit when l_upper > l_before;
      l_lower := add_months(l_upper, -1);
      continue when l_lower < l_from;
      select count(*) into l_open
        from cdrs c
       where c.started_at >= l_lower and c.started_at < l_upper
         and (c.status = 'NEW'
              or c.cycle_id in (select cycle_id from bill_cycles where status = 'OPEN'));
      if l_open > 0 then
        billing_log.warn('billing_maint', 'kept ' || to_char(l_lower, 'YYYY-MM') || ': '
          || l_open || ' records are unrated or in an open cycle');
      else
        execute immediate 'alter table cdrs drop partition ' || dbms_assert.simple_sql_name(p.partition_name);
        l_dropped := l_dropped + 1;
        billing_log.info('billing_maint', 'dropped call records for ' || to_char(l_lower, 'YYYY-MM'));
      end if;
    end loop;
    return l_dropped;
  end purge_before;

  function partitions return sys.odcivarchar2list pipelined is
  begin
    for p in (select p.partition_name, p.high_value, p.compression, p.num_rows,
                     (select sum(s.bytes) from user_segments s
                       where s.segment_name = 'CDRS' and s.partition_name = p.partition_name) as bytes
                from user_tab_partitions p
               where p.table_name = 'CDRS'
               order by p.partition_position) loop
      pipe row (rpad(p.partition_name, 16) || ' below ' || to_char(upper_bound(p.high_value), 'YYYY-MM-DD')
                || '  ' || rpad(p.compression, 8) || lpad(nvl(to_char(round(p.bytes / 1048576, 1)), '-'), 8) || ' MB');
    end loop;
    return;
  end partitions;

end billing_maint;
/
