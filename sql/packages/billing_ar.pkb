create or replace package body billing_ar as

  -- Serialises payment work for one customer, so two sessions can't
  -- spread the same payment twice.
  procedure lock_customer(p_customer_id customers.customer_id%type) is
    l_id customers.customer_id%type;
  begin
    select customer_id into l_id from customers where customer_id = p_customer_id for update;
  end lock_customer;

  -- Back to ACTIVE once nothing is past due on p_as_of.
  procedure reactivate(p_customer_id customers.customer_id%type, p_as_of date) is
  begin
    update customers c
       set c.status = 'ACTIVE'
     where c.customer_id = p_customer_id
       and c.status = 'SUSPENDED'
       and not exists (select null
                         from invoices i
                        where i.customer_id = c.customer_id
                          and i.due_date < trunc(p_as_of)
                          and i.total > (select nvl(sum(a.amount), 0)
                                           from payment_allocations a
                                          where a.invoice_id = i.invoice_id));
    if sql%rowcount > 0 then
      billing_log.info('billing_ar', 'customer ' || p_customer_id || ' is paid up and active again');
    end if;
  end reactivate;

  function record_payment(
    p_customer_id  customers.customer_id%type,
    p_amount       number,
    p_reference    varchar2,
    p_received_on  date,
    p_method       varchar2 default 'BANK'
  ) return payments.payment_id%type
  is
    l_id    payments.payment_id%type;
    l_seen  payments%rowtype;
    l_n     pls_integer;
  begin
    lock_customer(p_customer_id);
    begin
      insert into payments (customer_id, amount, received_on, method, reference)
      values (p_customer_id, p_amount, trunc(p_received_on), upper(p_method), p_reference)
      returning payment_id into l_id;
    exception
      when dup_val_on_index then
        select * into l_seen from payments where reference = p_reference;
        if l_seen.customer_id = p_customer_id and l_seen.amount = p_amount then
          return l_seen.payment_id;
        end if;
        raise_application_error(billing_errors.payment_clash,
          'payment ' || p_reference || ' was already taken for customer ' || l_seen.customer_id
          || ', amount ' || to_char(l_seen.amount, 'FM999999990.00'));
    end;
    billing_events.publish('PAYMENT_RECEIVED', p_customer_id, null, null,
      '{"paymentId":' || l_id || ',"amount":' || to_char(p_amount, 'TM9', 'NLS_NUMERIC_CHARACTERS=.,')
      || ',"reference":"' || replace(replace(p_reference, '\', '\\'), '"', '\"') || '"}');
    l_n := allocate(p_customer_id);
    reactivate(p_customer_id, p_received_on);
    return l_id;
  end record_payment;

  function allocate(p_customer_id customers.customer_id%type) return pls_integer is
    l_n pls_integer;
  begin
    lock_customer(p_customer_id);
    -- Lay the unallocated money end to end on one line, oldest payment
    -- first, and the unpaid amounts on another, oldest due first. Each
    -- overlap of a payment's stretch with an invoice's is an allocation.
    merge into payment_allocations a
    using (
      with pay as (
        select p.payment_id, p.received_on,
               p.amount - nvl((select sum(x.amount) from payment_allocations x
                                where x.payment_id = p.payment_id), 0) as amount
          from payments p
         where p.customer_id = p_customer_id
      ), pay_line as (
        select payment_id,
               sum(amount) over (order by received_on, payment_id) - amount as lo,
               sum(amount) over (order by received_on, payment_id) as hi
          from pay
         where amount > 0
      ), inv as (
        select i.invoice_id, i.due_date,
               i.total - nvl((select sum(x.amount) from payment_allocations x
                               where x.invoice_id = i.invoice_id), 0) as amount
          from invoices i
         where i.customer_id = p_customer_id
      ), inv_line as (
        select invoice_id,
               sum(amount) over (order by due_date, invoice_id) - amount as lo,
               sum(amount) over (order by due_date, invoice_id) as hi
          from inv
         where amount > 0
      )
      select p.payment_id, i.invoice_id, least(p.hi, i.hi) - greatest(p.lo, i.lo) as amount
        from pay_line p
        join inv_line i on p.lo < i.hi and i.lo < p.hi
    ) s
    on (a.payment_id = s.payment_id and a.invoice_id = s.invoice_id)
    when matched then
      update set a.amount = a.amount + s.amount
    when not matched then
      insert (payment_id, invoice_id, amount) values (s.payment_id, s.invoice_id, s.amount);
    l_n := sql%rowcount;
    return l_n;
  end allocate;

  function allocate_all return pls_integer is
    l_n pls_integer := 0;
  begin
    for c in (select distinct customer_id from payments order by customer_id) loop
      l_n := l_n + allocate(c.customer_id);
    end loop;
    return l_n;
  end allocate_all;

  function open_amount(p_invoice_id invoices.invoice_id%type) return number is
    l_open number;
  begin
    select i.total - nvl(sum(a.amount), 0) into l_open
      from invoices i
      left join payment_allocations a on a.invoice_id = i.invoice_id
     where i.invoice_id = p_invoice_id
     group by i.total;
    return l_open;
  end open_amount;

  function run_dunning(p_as_of date) return pls_integer is
    type t_steps is table of dunning_actions%rowtype index by pls_integer;
    l_as_of      date := trunc(p_as_of);
    l_new        t_steps;
    l_steps      pls_integer;
    l_suspended  pls_integer;
    l_customer   customers.customer_id%type;
    l_payload    varchar2(4000);
  begin
    -- Every step an invoice has reached and not had yet. An invoice
    -- found 65 days overdue the first time gets all three.
    select o.invoice_id, s.step, s.action, l_as_of - o.due_date, o.open_amount, l_as_of
      bulk collect into l_new
      from (select i.invoice_id, i.due_date,
                   i.total - nvl((select sum(a.amount) from payment_allocations a
                                   where a.invoice_id = i.invoice_id), 0) as open_amount
              from invoices i
             where i.due_date < l_as_of) o
      join (select 1 as step, 'REMINDER' as action, reminder_days as days from dual union all
            select 2, 'WARNING', warning_days from dual union all
            select 3, 'SUSPEND', suspend_days from dual) s
        on l_as_of - o.due_date >= s.days
     where o.open_amount > 0
       and not exists (select null from dunning_actions d
                        where d.invoice_id = o.invoice_id and d.step = s.step)
     order by o.invoice_id, s.step;
    forall i in 1 .. l_new.count
      insert into dunning_actions values l_new(i);
    l_steps := l_new.count;

    for i in 1 .. l_new.count loop
      select i.customer_id,
             json_object('invoiceNo' value i.invoice_no, 'daysOverdue' value l_new(i).days_overdue,
                         'open' value l_new(i).open_amount)
        into l_customer, l_payload
        from invoices i
       where i.invoice_id = l_new(i).invoice_id;
      billing_events.publish('DUNNING_' || l_new(i).action, l_customer, null, null, l_payload);
    end loop;

    update customers c
       set c.status = 'SUSPENDED'
     where c.status = 'ACTIVE'
       and exists (select null
                     from dunning_actions d
                     join invoices i on i.invoice_id = d.invoice_id
                    where i.customer_id = c.customer_id
                      and d.step = 3
                      and d.taken_on = l_as_of);
    l_suspended := sql%rowcount;

    if l_steps > 0 then
      billing_log.info('billing_ar', 'dunning on ' || to_char(l_as_of, 'YYYY-MM-DD') || ': '
        || l_steps || ' steps, ' || l_suspended || ' customers suspended');
    end if;
    return l_steps;
  end run_dunning;

  function aging(p_as_of date) return ar_aging_tab pipelined is
    l_as_of date := trunc(p_as_of);
  begin
    for r in (
      with open_invoices as (
        -- Only money received by p_as_of counts, so a past date gives
        -- the picture as it was then.
        select i.customer_id, l_as_of - i.due_date as overdue,
               i.total - nvl((select sum(a.amount)
                                from payment_allocations a
                                join payments p on p.payment_id = a.payment_id
                               where a.invoice_id = i.invoice_id
                                 and p.received_on <= l_as_of), 0) as open_amount
          from invoices i
         where i.issued_at <= l_as_of
      ), unallocated as (
        select p.customer_id,
               sum(p.amount - nvl((select sum(a.amount)
                                     from payment_allocations a
                                     join invoices i on i.invoice_id = a.invoice_id
                                    where a.payment_id = p.payment_id
                                      and i.issued_at <= l_as_of), 0)) as amount
          from payments p
         where p.received_on <= l_as_of
         group by p.customer_id
      ), buckets as (
        select customer_id,
               sum(case when overdue <= 0 then open_amount else 0 end) as not_due,
               sum(case when overdue between 1 and 30 then open_amount else 0 end) as d30,
               sum(case when overdue between 31 and 60 then open_amount else 0 end) as d60,
               sum(case when overdue between 61 and 90 then open_amount else 0 end) as d90,
               sum(case when overdue > 90 then open_amount else 0 end) as d90plus,
               sum(open_amount) as total_open
          from open_invoices
         where open_amount > 0
         group by customer_id
      )
      select c.customer_id, c.name, c.status,
             nvl(b.not_due, 0) as not_due, nvl(b.d30, 0) as d30, nvl(b.d60, 0) as d60,
             nvl(b.d90, 0) as d90, nvl(b.d90plus, 0) as d90plus,
             nvl(b.total_open, 0) as total_open, nvl(u.amount, 0) as unallocated
        from customers c
        left join buckets b on b.customer_id = c.customer_id
        left join unallocated u on u.customer_id = c.customer_id
       where nvl(b.total_open, 0) > 0 or nvl(u.amount, 0) > 0
       order by nvl(b.total_open, 0) desc, c.customer_id
    ) loop
      pipe row (ar_aging_row(r.customer_id, r.name, r.status, r.not_due, r.d30, r.d60,
                             r.d90, r.d90plus, r.total_open, r.unallocated));
    end loop;
    return;
  end aging;

end billing_ar;
/
