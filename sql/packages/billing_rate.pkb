create or replace package body billing_rate as

  -- What rating decided for one call record.
  type t_result is record (
    status          cdrs.status%type,
    cycle_id        cdrs.cycle_id%type,
    late            cdrs.late%type,
    dest_class      cdrs.dest_class%type,
    peak            cdrs.peak%type,
    tariff_id       cdrs.tariff_id%type,
    rated_units     cdrs.rated_units%type,
    included_units  cdrs.included_units%type,
    charged_units   cdrs.charged_units%type,
    amount          cdrs.amount%type,
    fail_reason     cdrs.fail_reason%type
  );

  -- The caches rate_pending builds at the start of each call.
  type t_text_map is table of varchar2(10) index by varchar2(20);
  type t_units_map is table of number index by varchar2(20);
  type t_tariff is record (
    tariff_id    tariffs.tariff_id%type,
    first_units  tariffs.first_units%type,
    next_units   tariffs.next_units%type,
    price        tariffs.price%type,
    price_units  tariffs.price_units%type,
    valid_from   tariffs.valid_from%type,
    valid_to     tariffs.valid_to%type
  );
  type t_tariff_list is table of t_tariff index by pls_integer;
  type t_tariff_map is table of t_tariff_list index by varchar2(60);
  type t_segment is record (
    plan_id     subscriber_plans.plan_id%type,
    valid_from  subscriber_plans.valid_from%type,
    valid_to    subscriber_plans.valid_to%type
  );
  type t_segment_list is table of t_segment index by pls_integer;
  type t_segment_map is table of t_segment_list index by pls_integer;
  type t_cycle is record (
    cycle_id      bill_cycles.cycle_id%type,
    period_start  bill_cycles.period_start%type,
    period_end    bill_cycles.period_end%type,
    status        bill_cycles.status%type
  );
  type t_cycle_list is table of t_cycle index by pls_integer;
  type t_usage is record (
    subscriber_id  allowance_usage.subscriber_id%type,
    cycle_id       allowance_usage.cycle_id%type,
    service        allowance_usage.service%type,
    used           allowance_usage.used_units%type,
    dirty          boolean
  );
  type t_usage_map is table of t_usage index by varchar2(60);

  g_prefixes    t_text_map;     -- prefix to destination class
  g_max_prefix  pls_integer;
  g_bundle      t_text_map;     -- destination class to in_bundle
  g_holidays    t_text_map;     -- YYYYMMDD to Y
  g_allowances  t_units_map;    -- plan|service to units
  g_tariffs     t_tariff_map;   -- plan|service|class|period to tariffs, oldest first
  g_segments    t_segment_map;  -- subscriber to plan segments
  g_cycles      t_cycle_list;   -- by period_start
  g_usage       t_usage_map;    -- subscriber|cycle|service to allowance used

  -- Failure reasons, shared by both raters so their results compare.
  function failed(p_reason varchar2) return t_result is
    l t_result;
  begin
    l.status := 'FAILED';
    l.late := 'N';
    l.fail_reason := substr(p_reason, 1, 200);
    return l;
  end failed;

  function no_plan(p_at date) return varchar2 is
  begin
    return 'not on any plan on ' || to_char(p_at, 'YYYY-MM-DD');
  end no_plan;

  function no_destination(p_called varchar2) return varchar2 is
  begin
    return 'no destination matches ' || p_called;
  end no_destination;

  function no_tariff(p_plan number, p_service varchar2, p_class varchar2, p_peak varchar2) return varchar2 is
  begin
    return 'plan ' || p_plan || ' has no ' || p_service || ' tariff for ' || p_class
           || case p_peak when 'Y' then ' at peak' else ' off peak' end;
  end no_tariff;

  function no_cycle(p_at date) return varchar2 is
  begin
    return 'no open bill cycle for ' || to_char(p_at, 'YYYY-MM-DD');
  end no_cycle;

  -- Prices a call once its tariff is known. p_remaining is what's left
  -- of the allowance, null if none applies. The caller fills in the
  -- rest of the result and takes included_units off the allowance.
  function price(
    p_quantity     number,
    p_first        number,
    p_next         number,
    p_price        number,
    p_price_units  number,
    p_remaining    number
  ) return t_result is
    l t_result;
  begin
    l.status := 'RATED';
    l.rated_units := billing_ref.rated_units(p_quantity, p_first, p_next);
    l.included_units := least(l.rated_units, greatest(nvl(p_remaining, 0), 0));
    l.charged_units := l.rated_units - l.included_units;
    l.amount := billing_ref.charge(l.charged_units, p_price, p_price_units);
    return l;
  end price;

  ---------------------------------------------------------------------
  -- The batch rater.

  function tariff_key(p_plan number, p_service varchar2, p_class varchar2, p_period varchar2) return varchar2 is
  begin
    return p_plan || '|' || p_service || '|' || p_class || '|' || p_period;
  end tariff_key;

  function usage_key(p_subscriber number, p_cycle number, p_service varchar2) return varchar2 is
  begin
    return p_subscriber || '|' || p_cycle || '|' || p_service;
  end usage_key;

  procedure load_caches(p_from_sub number, p_to_sub number) is
    l_tariffs   t_tariff_list;
    l_tariff    t_tariff;
    l_segments  t_segment_list;
    l_segment   t_segment;
    l_key       varchar2(60);
  begin
    g_prefixes.delete;
    g_bundle.delete;
    g_holidays.delete;
    g_allowances.delete;
    g_tariffs.delete;
    g_segments.delete;
    g_cycles.delete;
    g_usage.delete;

    g_max_prefix := 0;
    for r in (select prefix, dest_class from destinations) loop
      g_prefixes(r.prefix) := r.dest_class;
      g_max_prefix := greatest(g_max_prefix, length(r.prefix));
    end loop;
    for r in (select dest_class, in_bundle from dest_classes) loop
      g_bundle(r.dest_class) := r.in_bundle;
    end loop;
    for r in (select to_char(holiday, 'YYYYMMDD') as day from holidays) loop
      g_holidays(r.day) := 'Y';
    end loop;
    for r in (select plan_id, service, units from allowances) loop
      g_allowances(r.plan_id || '|' || r.service) := r.units;
    end loop;

    for r in (select tariff_id, plan_id, service, dest_class, period, first_units, next_units,
                     price, price_units, valid_from, valid_to
                from tariffs
               order by valid_from) loop
      l_key := tariff_key(r.plan_id, r.service, r.dest_class, r.period);
      l_tariffs.delete;
      if g_tariffs.exists(l_key) then
        l_tariffs := g_tariffs(l_key);
      end if;
      l_tariff.tariff_id := r.tariff_id;
      l_tariff.first_units := r.first_units;
      l_tariff.next_units := r.next_units;
      l_tariff.price := r.price;
      l_tariff.price_units := r.price_units;
      l_tariff.valid_from := r.valid_from;
      l_tariff.valid_to := r.valid_to;
      l_tariffs(l_tariffs.count + 1) := l_tariff;
      g_tariffs(l_key) := l_tariffs;
    end loop;

    -- Plan history, only for subscribers with something to rate.
    for r in (select sp.subscriber_id, sp.plan_id, sp.valid_from, sp.valid_to
                from subscriber_plans sp
               where sp.subscriber_id in (select subscriber_id from cdrs
                                           where status = 'NEW'
                                             and subscriber_id between p_from_sub and p_to_sub)
               order by sp.subscriber_id, sp.valid_from) loop
      l_segments.delete;
      if g_segments.exists(r.subscriber_id) then
        l_segments := g_segments(r.subscriber_id);
      end if;
      l_segment.plan_id := r.plan_id;
      l_segment.valid_from := r.valid_from;
      l_segment.valid_to := r.valid_to;
      l_segments(l_segments.count + 1) := l_segment;
      g_segments(r.subscriber_id) := l_segments;
    end loop;

    select cycle_id, period_start, period_end, status
      bulk collect into g_cycles
      from bill_cycles
     order by period_start;
  end load_caches;

  function cached_plan(p_subscriber number, p_at date) return number is
  begin
    if g_segments.exists(p_subscriber) then
      for i in 1 .. g_segments(p_subscriber).count loop
        if g_segments(p_subscriber)(i).valid_from <= p_at
           and (g_segments(p_subscriber)(i).valid_to is null or p_at < g_segments(p_subscriber)(i).valid_to) then
          return g_segments(p_subscriber)(i).plan_id;
        end if;
      end loop;
    end if;
    return null;
  end cached_plan;

  -- The longest matching prefix: at most g_max_prefix lookups, longest
  -- first, instead of a LIKE over the whole table.
  function cached_class(p_called varchar2) return varchar2 is
  begin
    for n in reverse 1 .. least(nvl(length(p_called), 0), g_max_prefix) loop
      if g_prefixes.exists(substr(p_called, 1, n)) then
        return g_prefixes(substr(p_called, 1, n));
      end if;
    end loop;
    return null;
  end cached_class;

  function cached_peak(p_at date) return varchar2 is
  begin
    if billing_ref.weekday_peak(p_at) = 'N' or g_holidays.exists(to_char(p_at, 'YYYYMMDD')) then
      return 'N';
    end if;
    return 'Y';
  end cached_peak;

  function find_tariff(p_key varchar2, p_at date, p_found out t_tariff) return boolean is
  begin
    if g_tariffs.exists(p_key) then
      for i in 1 .. g_tariffs(p_key).count loop
        if g_tariffs(p_key)(i).valid_from <= p_at
           and (g_tariffs(p_key)(i).valid_to is null or p_at < g_tariffs(p_key)(i).valid_to) then
          p_found := g_tariffs(p_key)(i);
          return true;
        end if;
      end loop;
    end if;
    return false;
  end find_tariff;

  -- A tariff for the call's own period wins over one for ANY.
  function cached_tariff(
    p_plan     number,
    p_service  varchar2,
    p_class    varchar2,
    p_peak     varchar2,
    p_at       date,
    p_found    out t_tariff
  ) return boolean is
    l_period varchar2(7) := case p_peak when 'Y' then 'PEAK' else 'OFFPEAK' end;
  begin
    return find_tariff(tariff_key(p_plan, p_service, p_class, l_period), p_at, p_found)
        or find_tariff(tariff_key(p_plan, p_service, p_class, 'ANY'), p_at, p_found);
  end cached_tariff;

  -- The open cycle a call at p_at goes into: its own, or if that's
  -- billed the first open one after it. Null if there's none.
  procedure find_cycle(p_at date, p_cycle out number, p_late out varchar2) is
  begin
    p_cycle := null;
    p_late := 'N';
    for i in 1 .. g_cycles.count loop
      if p_at >= g_cycles(i).period_start and p_at < g_cycles(i).period_end then
        if g_cycles(i).status = 'OPEN' then
          p_cycle := g_cycles(i).cycle_id;
          return;
        end if;
        for j in i + 1 .. g_cycles.count loop
          if g_cycles(j).status = 'OPEN' then
            p_cycle := g_cycles(j).cycle_id;
            p_late := 'Y';
            return;
          end if;
        end loop;
        return;
      end if;
    end loop;
  end find_cycle;

  function stored_usage(p_subscriber number, p_cycle number, p_service varchar2) return number is
    l_used number;
  begin
    select nvl(max(used_units), 0) into l_used
      from allowance_usage
     where subscriber_id = p_subscriber
       and cycle_id = p_cycle
       and service = p_service;
    return l_used;
  end stored_usage;

  function rate_cached(
    p_subscriber  number,
    p_service     varchar2,
    p_called      varchar2,
    p_at          date,
    p_quantity    number
  ) return t_result is
    l           t_result;
    l_plan      number;
    l_class     varchar2(10);
    l_peak      varchar2(1);
    l_tariff    t_tariff;
    l_cycle     number;
    l_late      varchar2(1);
    l_akey      varchar2(20);
    l_ukey      varchar2(60);
    l_usage     t_usage;
    l_remaining number;
  begin
    l_plan := cached_plan(p_subscriber, p_at);
    if l_plan is null then
      return failed(no_plan(p_at));
    end if;
    l_class := case p_service when 'DATA' then 'DATA' else cached_class(p_called) end;
    if l_class is null then
      return failed(no_destination(p_called));
    end if;
    l_peak := cached_peak(p_at);
    if not cached_tariff(l_plan, p_service, l_class, l_peak, p_at, l_tariff) then
      return failed(no_tariff(l_plan, p_service, l_class, l_peak));
    end if;
    find_cycle(p_at, l_cycle, l_late);
    if l_cycle is null then
      return failed(no_cycle(p_at));
    end if;

    l_akey := l_plan || '|' || p_service;
    if g_bundle.exists(l_class) and g_bundle(l_class) = 'Y' and g_allowances.exists(l_akey) then
      l_ukey := usage_key(p_subscriber, l_cycle, p_service);
      if not g_usage.exists(l_ukey) then
        l_usage.subscriber_id := p_subscriber;
        l_usage.cycle_id := l_cycle;
        l_usage.service := p_service;
        l_usage.used := stored_usage(p_subscriber, l_cycle, p_service);
        l_usage.dirty := false;
        g_usage(l_ukey) := l_usage;
      end if;
      l_remaining := g_allowances(l_akey) - g_usage(l_ukey).used;
    end if;

    l := price(p_quantity, l_tariff.first_units, l_tariff.next_units, l_tariff.price,
               l_tariff.price_units, l_remaining);
    if l.included_units > 0 then
      g_usage(l_ukey).used := g_usage(l_ukey).used + l.included_units;
      g_usage(l_ukey).dirty := true;
    end if;
    l.cycle_id := l_cycle;
    l.late := l_late;
    l.dest_class := l_class;
    l.peak := l_peak;
    l.tariff_id := l_tariff.tariff_id;
    return l;
  end rate_cached;

  -- Writes the allowance counters that changed in the last batch.
  procedure flush_usage is
    type t_num is table of number index by pls_integer;
    type t_service is table of varchar2(5) index by pls_integer;
    l_subscribers  t_num;
    l_cycles       t_num;
    l_services     t_service;
    l_used         t_num;
    l_n            pls_integer := 0;
    l_key          varchar2(60) := g_usage.first;
  begin
    while l_key is not null loop
      if g_usage(l_key).dirty then
        l_n := l_n + 1;
        l_subscribers(l_n) := g_usage(l_key).subscriber_id;
        l_cycles(l_n) := g_usage(l_key).cycle_id;
        l_services(l_n) := g_usage(l_key).service;
        l_used(l_n) := g_usage(l_key).used;
        g_usage(l_key).dirty := false;
      end if;
      l_key := g_usage.next(l_key);
    end loop;

    forall i in 1 .. l_n
      merge into allowance_usage u
      using (select l_subscribers(i) as subscriber_id, l_cycles(i) as cycle_id,
                    l_services(i) as service, l_used(i) as used_units
               from dual) s
         on (u.subscriber_id = s.subscriber_id and u.cycle_id = s.cycle_id and u.service = s.service)
       when matched then
         update set u.used_units = s.used_units
       when not matched then
         insert (subscriber_id, cycle_id, service, used_units)
         values (s.subscriber_id, s.cycle_id, s.service, s.used_units);
  end flush_usage;

  -- Rates NEW records of subscribers p_from_sub to p_to_sub. The caller
  -- holds the RATER lock.
  function rate_range(p_max_rows pls_integer, p_batch_size pls_integer, p_from_sub number, p_to_sub number)
    return pls_integer
  is
    cursor c_new is
      select cdr_id, subscriber_id, service, called, started_at, quantity
        from cdrs
       where status = 'NEW'
         and subscriber_id between p_from_sub and p_to_sub
       order by subscriber_id, started_at, cdr_id
       fetch first p_max_rows rows only;
    type t_new is table of c_new%rowtype index by pls_integer;
    type t_results is table of t_result index by pls_integer;
    l_rows  t_new;
    l_out   t_results;
    l_done  pls_integer := 0;
  begin
    -- Open the cursor before reading the plan history: every subscriber
    -- the cursor will return is then in the cache.
    open c_new;
    load_caches(p_from_sub, p_to_sub);
    loop
      fetch c_new bulk collect into l_rows limit p_batch_size;
      exit when l_rows.count = 0;

      for i in 1 .. l_rows.count loop
        l_out(i) := rate_cached(l_rows(i).subscriber_id, l_rows(i).service, l_rows(i).called,
                                l_rows(i).started_at, l_rows(i).quantity);
      end loop;

      forall i in 1 .. l_rows.count
        update cdrs
           set status = l_out(i).status,
               cycle_id = l_out(i).cycle_id,
               late = l_out(i).late,
               dest_class = l_out(i).dest_class,
               peak = l_out(i).peak,
               tariff_id = l_out(i).tariff_id,
               rated_units = l_out(i).rated_units,
               included_units = l_out(i).included_units,
               charged_units = l_out(i).charged_units,
               amount = l_out(i).amount,
               fail_reason = l_out(i).fail_reason,
               rated_at = sysdate
         where cdr_id = l_rows(i).cdr_id
           and started_at = l_rows(i).started_at;
      flush_usage;

      l_done := l_done + l_rows.count;
    end loop;
    close c_new;
    return l_done;
  exception
    when others then
      if c_new%isopen then
        close c_new;
      end if;
      raise;
  end rate_range;

  function rate_pending(p_max_rows pls_integer default 100000, p_batch_size pls_integer default 1000)
    return pls_integer
  is
  begin
    billing_errors.take_lock('RATER');
    return rate_range(p_max_rows, p_batch_size, 0, 1e38);
  end rate_pending;

  procedure rate_chunk(p_start_id number, p_end_id number) is
    l_n pls_integer;
  begin
    l_n := rate_range(1e9, 1000, p_start_id, p_end_id);
  end rate_chunk;

  function rate_parallel(p_parallel_level pls_integer default 4, p_chunks pls_integer default 16)
    return pls_integer
  is
    l_task    varchar2(128);
    l_before  pls_integer;
    l_after   pls_integer;
    l_status  pls_integer;
    l_error   varchar2(4000);

    procedure clean_up is
    begin
      if l_task is not null then
        dbms_parallel_execute.drop_task(l_task);
      end if;
      billing_errors.release_lock('RATER');
    end clean_up;
  begin
    billing_errors.hold_lock('RATER');
    select count(*) into l_before from cdrs where status = 'NEW';
    if l_before = 0 then
      clean_up;
      return 0;
    end if;

    l_task := dbms_parallel_execute.generate_task_name('BILLRUN_RATE_');
    dbms_parallel_execute.create_task(l_task);
    -- Equal numbers of subscribers per chunk, from those with work, in
    -- id order so the ranges don't overlap.
    dbms_parallel_execute.create_chunks_by_sql(l_task,
      'select min(subscriber_id), max(subscriber_id)
         from (select subscriber_id, ntile(' || to_char(p_chunks) || ') over (order by subscriber_id) as chunk
                 from (select distinct subscriber_id from cdrs where status = ''NEW''))
        group by chunk',
      by_rowid => false);
    dbms_parallel_execute.run_task(l_task,
      'begin billing_rate.rate_chunk(:start_id, :end_id); end;',
      dbms_sql.native,
      parallel_level => p_parallel_level);

    -- A chunk that failed (a lock timeout, say) gets one more go.
    l_status := dbms_parallel_execute.task_status(l_task);
    if l_status = dbms_parallel_execute.finished_with_error then
      dbms_parallel_execute.resume_task(l_task);
      l_status := dbms_parallel_execute.task_status(l_task);
    end if;
    if l_status <> dbms_parallel_execute.finished then
      select max(error_message) into l_error
        from user_parallel_execute_chunks
       where task_name = l_task and status = 'PROCESSED_WITH_ERROR';
      raise_application_error(billing_errors.busy, 'parallel rating did not finish: ' || l_error);
    end if;

    select count(*) into l_after from cdrs where status = 'NEW';
    billing_log.info('billing_rate', 'rated ' || (l_before - l_after) || ' records in parallel, '
      || p_chunks || ' chunks, ' || p_parallel_level || ' at a time');
    clean_up;
    return l_before - l_after;
  exception
    when others then
      clean_up;
      raise;
  end rate_parallel;

  ---------------------------------------------------------------------
  -- The row by row rater.

  function rate_queried(
    p_subscriber  number,
    p_service     varchar2,
    p_called      varchar2,
    p_at          date,
    p_quantity    number
  ) return t_result is
    l            t_result;
    l_plan       number;
    l_class      varchar2(10);
    l_peak       varchar2(1);
    l_tariff_id  number;
    l_first      number;
    l_next       number;
    l_price      number;
    l_units      number;
    l_cycle      number;
    l_status     varchar2(6);
    l_late       varchar2(1) := 'N';
    l_allowance  number;
    l_used       number;
    l_remaining  number;
  begin
    begin
      select plan_id into l_plan
        from subscriber_plans
       where subscriber_id = p_subscriber
         and valid_from <= p_at
         and (valid_to is null or p_at < valid_to);
    exception
      when no_data_found then
        return failed(no_plan(p_at));
    end;

    if p_service = 'DATA' then
      l_class := 'DATA';
    else
      l_class := billing_ref.dest_class(p_called);
    end if;
    if l_class is null then
      return failed(no_destination(p_called));
    end if;

    l_peak := billing_ref.is_peak(p_at);
    begin
      select tariff_id, first_units, next_units, price, price_units
        into l_tariff_id, l_first, l_next, l_price, l_units
        from tariffs
       where plan_id = l_plan
         and service = p_service
         and dest_class = l_class
         and period in (case l_peak when 'Y' then 'PEAK' else 'OFFPEAK' end, 'ANY')
         and valid_from <= p_at
         and (valid_to is null or p_at < valid_to)
       order by case period when 'ANY' then 1 else 0 end, valid_from
       fetch first 1 row only;
    exception
      when no_data_found then
        return failed(no_tariff(l_plan, p_service, l_class, l_peak));
    end;

    begin
      select cycle_id, status into l_cycle, l_status
        from bill_cycles
       where p_at >= period_start
         and p_at < period_end;
      if l_status = 'BILLED' then
        select cycle_id into l_cycle
          from bill_cycles
         where status = 'OPEN'
           and period_start > p_at
         order by period_start
         fetch first 1 row only;
        l_late := 'Y';
      end if;
    exception
      when no_data_found then
        return failed(no_cycle(p_at));
    end;

    -- max() gives null when there's no row, where into would raise.
    select max(a.units) into l_allowance
      from allowances a
      join dest_classes d on d.dest_class = l_class and d.in_bundle = 'Y'
     where a.plan_id = l_plan
       and a.service = p_service;
    if l_allowance is not null then
      select nvl(max(used_units), 0) into l_used
        from allowance_usage
       where subscriber_id = p_subscriber
         and cycle_id = l_cycle
         and service = p_service;
      l_remaining := l_allowance - l_used;
    end if;

    l := price(p_quantity, l_first, l_next, l_price, l_units, l_remaining);
    l.cycle_id := l_cycle;
    l.late := l_late;
    l.dest_class := l_class;
    l.peak := l_peak;
    l.tariff_id := l_tariff_id;
    return l;
  end rate_queried;

  function rate_pending_slow(p_max_rows pls_integer default 100000) return pls_integer is
    l       t_result;
    l_done  pls_integer := 0;
  begin
    billing_errors.take_lock('RATER');
    for r in (select cdr_id, subscriber_id, service, called, started_at, quantity
                from cdrs
               where status = 'NEW'
               order by subscriber_id, started_at, cdr_id
               fetch first p_max_rows rows only) loop
      l := rate_queried(r.subscriber_id, r.service, r.called, r.started_at, r.quantity);

      update cdrs
         set status = l.status,
             cycle_id = l.cycle_id,
             late = l.late,
             dest_class = l.dest_class,
             peak = l.peak,
             tariff_id = l.tariff_id,
             rated_units = l.rated_units,
             included_units = l.included_units,
             charged_units = l.charged_units,
             amount = l.amount,
             fail_reason = l.fail_reason,
             rated_at = sysdate
       where cdr_id = r.cdr_id
         and started_at = r.started_at;

      if l.included_units > 0 then
        merge into allowance_usage u
        using (select r.subscriber_id as subscriber_id, l.cycle_id as cycle_id,
                      r.service as service from dual) s
           on (u.subscriber_id = s.subscriber_id and u.cycle_id = s.cycle_id and u.service = s.service)
         when matched then
           update set u.used_units = u.used_units + l.included_units
         when not matched then
           insert (subscriber_id, cycle_id, service, used_units)
           values (s.subscriber_id, s.cycle_id, s.service, l.included_units);
      end if;
      l_done := l_done + 1;
    end loop;
    return l_done;
  end rate_pending_slow;

  function rerate_cycle(p_cycle_id bill_cycles.cycle_id%type) return pls_integer is
    l_cycle  bill_cycles%rowtype;
    l_n      pls_integer;
  begin
    billing_errors.take_lock('RATER');
    begin
      select * into l_cycle from bill_cycles where cycle_id = p_cycle_id for update;
    exception
      when no_data_found then
        raise_application_error(billing_errors.no_such_cycle, 'no bill cycle ' || p_cycle_id);
    end;
    if l_cycle.status <> 'OPEN' then
      raise_application_error(billing_errors.cycle_not_open,
        'cycle ' || to_char(l_cycle.period_start, 'YYYY-MM') || ' is billed; correct it with an adjustment');
    end if;

    update cdrs
       set status = 'NEW', cycle_id = null, late = 'N', dest_class = null, peak = null, tariff_id = null,
           rated_units = null, included_units = null, charged_units = null, amount = null,
           fail_reason = null, rated_at = null
     where cycle_id = p_cycle_id
        or (status = 'FAILED' and started_at >= l_cycle.period_start and started_at < l_cycle.period_end);
    l_n := sql%rowcount;
    delete from allowance_usage where cycle_id = p_cycle_id;
    billing_log.info('billing_rate', 'rerating ' || to_char(l_cycle.period_start, 'YYYY-MM') || ': ' || l_n || ' records reset');
    return l_n;
  end rerate_cycle;

end billing_rate;
/
