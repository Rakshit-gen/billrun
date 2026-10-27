create or replace package body billing_demo as

  type t_text is table of varchar2(100) index by pls_integer;
  type t_num  is table of number index by pls_integer;

  -- A whole number from p_low to p_high.
  function pick(p_low pls_integer, p_high pls_integer) return pls_integer is
  begin
    return trunc(dbms_random.value(p_low, p_high + 1));
  end pick;

  procedure add_customers(p_customers pls_integer, p_from date, p_seed binary_integer default 1) is
    l_plans     sys.odcivarchar2list := sys.odcivarchar2list('BASIC', 'PLUS', 'MAX');
    l_next      number;
    l_customer  customers.customer_id%type;
    l_line      subscribers.subscriber_id%type;
  begin
    dbms_random.seed(p_seed);
    select nvl(max(to_number(msisdn)), 447000000000) into l_next
      from subscribers
     where msisdn like '4470%';
    for c in 1 .. p_customers loop
      l_customer := billing_admin.add_customer('Demo customer ' || c);
      for s in 1 .. pick(1, 3) loop
        l_next := l_next + 1;
        l_line := billing_admin.add_subscriber(l_customer, to_char(l_next), l_plans(pick(1, 3)), p_from);
      end loop;
    end loop;
  end add_customers;

  procedure stage_usage(
    p_file_name  varchar2,
    p_records    pls_integer,
    p_month      date,
    p_seed       binary_integer default 1,
    p_bad_share  number default 0.01
  ) is
    -- Weighted towards mobiles, the way real traffic is.
    l_prefixes  sys.odcivarchar2list :=
      sys.odcivarchar2list('4420', '44161', '447', '447', '447', '447', '1', '33', '49', '91', '449');
    l_start     date := trunc(p_month, 'MM');
    l_seconds   pls_integer := (add_months(l_start, 1) - l_start) * 86400;
    l_numbers   t_text;
    l_base      pls_integer;
    l_n         pls_integer := 0;
    l_at        date;
    l_roll      number;
    l_lines     t_num;
    l_msisdn    t_text;
    l_service   t_text;
    l_called    t_text;
    l_started   t_text;
    l_qty       t_text;

    procedure flush is
    begin
      forall i in 1 .. l_n
        insert into cdr_staging (file_name, line_no, fields, msisdn, service, called, started_at, quantity)
        values (p_file_name, l_lines(i), 5, l_msisdn(i), l_service(i), l_called(i), l_started(i), l_qty(i));
      l_n := 0;
    end flush;
  begin
    dbms_random.seed(p_seed);
    select msisdn bulk collect into l_numbers
      from subscribers
     where active_from <= l_start
       and (active_to is null or active_to >= add_months(l_start, 1))
     order by subscriber_id;
    if l_numbers.count = 0 then
      raise_application_error(billing_errors.bad_date,
        'nobody is active all of ' || to_char(l_start, 'YYYY-MM') || '; add customers first');
    end if;
    select nvl(max(line_no), 0) into l_base from cdr_staging where file_name = p_file_name;

    for i in 1 .. p_records loop
      l_n := l_n + 1;
      l_lines(l_n) := l_base + i;
      l_msisdn(l_n) := l_numbers(pick(1, l_numbers.count));
      l_at := l_start + pick(0, l_seconds - 1) / 86400;
      l_started(l_n) := to_char(l_at, 'YYYY-MM-DD"T"HH24:MI:SS');
      l_roll := dbms_random.value;
      if l_roll < 0.6 then
        l_service(l_n) := 'VOICE';
        l_called(l_n) := l_prefixes(pick(1, l_prefixes.count)) || to_char(pick(0, 99999999), 'FM00000000');
        l_qty(l_n) := to_char(pick(1, 900));
      elsif l_roll < 0.85 then
        l_service(l_n) := 'SMS';
        l_called(l_n) := l_prefixes(pick(1, l_prefixes.count)) || to_char(pick(0, 99999999), 'FM00000000');
        l_qty(l_n) := '1';
      else
        l_service(l_n) := 'DATA';
        l_called(l_n) := 'internet';
        l_qty(l_n) := to_char(pick(1, 60000));
      end if;

      if dbms_random.value < p_bad_share then
        case pick(1, 3)
          when 1 then
            l_started(l_n) := to_char(l_at, 'DD/MM/YYYY HH24:MI');
          when 2 then
            l_msisdn(l_n) := '4479' || to_char(pick(0, 99999999), 'FM00000000');
          else
            -- A resend of the record before, under a new line number.
            if l_n > 1 then
              l_msisdn(l_n) := l_msisdn(l_n - 1);
              l_service(l_n) := l_service(l_n - 1);
              l_called(l_n) := l_called(l_n - 1);
              l_started(l_n) := l_started(l_n - 1);
              l_qty(l_n) := l_qty(l_n - 1);
            end if;
        end case;
      end if;

      if l_n = 10000 then
        flush;
      end if;
    end loop;
    flush;
  end stage_usage;

end billing_demo;
/
