create or replace package body billing_run as

  function bill_cycle(p_cycle_id bill_cycles.cycle_id%type) return pls_integer is
    l_cycle     bill_cycles%rowtype;
    l_days      number;
    l_pending   pls_integer;
    l_failed    pls_integer;
    l_invoices  pls_integer;
  begin
    billing_errors.take_lock('BILLRUN');
    begin
      select * into l_cycle from bill_cycles where cycle_id = p_cycle_id for update;
    exception
      when no_data_found then
        raise_application_error(billing_errors.no_such_cycle, 'no bill cycle ' || p_cycle_id);
    end;
    if l_cycle.status <> 'OPEN' then
      raise_application_error(billing_errors.cycle_not_open,
        'cycle ' || to_char(l_cycle.period_start, 'YYYY-MM') || ' is already billed');
    end if;

    -- The partition key range, so only the cycle's month is scanned.
    select count(case status when 'NEW' then 1 end), count(case status when 'FAILED' then 1 end)
      into l_pending, l_failed
      from cdrs
     where started_at >= l_cycle.period_start
       and started_at < l_cycle.period_end;
    if l_pending > 0 then
      raise_application_error(billing_errors.usage_not_rated,
        l_pending || ' call records in ' || to_char(l_cycle.period_start, 'YYYY-MM') || ' are not rated yet');
    end if;

    l_days := l_cycle.period_end - l_cycle.period_start;

    -- Invoice numbers count up from 1 in customer order, all in this
    -- one statement, so there are no gaps. An invoice is dated the day
    -- after the cycle ends, or today if the run is later than that.
    insert into invoices (invoice_no, customer_id, cycle_id, issued_at, due_date)
    select 'INV-' || to_char(l_cycle.period_start, 'YYYYMM') || '-'
           || to_char(row_number() over (order by b.customer_id), 'FM000000'),
           b.customer_id, p_cycle_id,
           greatest(trunc(sysdate), l_cycle.period_end),
           greatest(trunc(sysdate), l_cycle.period_end) + cu.terms_days
      from customers cu
      join (select s.customer_id
              from subscriber_plans sp
              join subscribers s on s.subscriber_id = sp.subscriber_id
             where sp.valid_from < l_cycle.period_end
               and (sp.valid_to is null or sp.valid_to > l_cycle.period_start)
            union
            select s.customer_id
              from cdrs c
              join subscribers s on s.subscriber_id = c.subscriber_id
             where c.cycle_id = p_cycle_id
               and c.status = 'RATED'
            union
            select customer_id
              from adjustments
             where cycle_id = p_cycle_id) b on b.customer_id = cu.customer_id;
    l_invoices := sql%rowcount;

    -- The lines don't join invoices: a join let the optimizer drive from
    -- invoices and push the join into each branch, which is fine while
    -- invoices is small and ruinous when a plan made then is reused for
    -- thousands (every invoice rescanned the cycle's calls). There's one
    -- invoice per customer per cycle, so lines are numbered by customer,
    -- and each customer's invoice is a unique index lookup, which scalar
    -- subquery caching does once per customer.
    insert into invoice_lines (invoice_id, line_no, kind, subscriber_id, description, quantity, amount)
    select (select i.invoice_id from invoices i
             where i.customer_id = l.customer_id and i.cycle_id = p_cycle_id),
           row_number() over (partition by l.customer_id order by l.sort_order, l.subscriber_id, l.description),
           l.kind, l.subscriber_id, l.description, l.quantity, l.amount
      from (
            -- Each stretch of days on a plan, clipped to the cycle.
            select s.customer_id, 1 as sort_order, 'RECURRING' as kind, sp.subscriber_id,
                   p.name || ', ' || o.days || ' of ' || l_days || ' days' as description,
                   o.days as quantity,
                   round(p.monthly_fee * o.days / l_days, 2) as amount
              from subscriber_plans sp
              join subscribers s on s.subscriber_id = sp.subscriber_id
              join plans p on p.plan_id = sp.plan_id
             cross apply (select least(nvl(sp.valid_to, l_cycle.period_end), l_cycle.period_end)
                                 - greatest(sp.valid_from, l_cycle.period_start) as days
                            from dual) o
             where o.days > 0
            union all
            select s.customer_id, 2, 'USAGE', c.subscriber_id,
                   case c.service
                     when 'VOICE' then 'Calls to ' || dc.name
                     when 'SMS' then 'Texts to ' || dc.name
                     else 'Mobile data'
                   end || case c.late when 'Y' then ', arrived late' end,
                   sum(c.rated_units),
                   round(sum(c.amount), 2)
              from cdrs c
              join subscribers s on s.subscriber_id = c.subscriber_id
              join dest_classes dc on dc.dest_class = c.dest_class
             where c.cycle_id = p_cycle_id
               and c.status = 'RATED'
             group by s.customer_id, c.subscriber_id, c.service, dc.name, c.late
            union all
            select customer_id, 3, 'ADJUSTMENT', null, reason, null, amount
              from adjustments
             where cycle_id = p_cycle_id
           ) l;

    merge into invoices i
    using (select inv.invoice_id,
                  nvl(sum(il.amount), 0) as subtotal,
                  round(nvl(sum(il.amount), 0) * max(cu.tax_rate), 2) as tax
             from invoices inv
             join customers cu on cu.customer_id = inv.customer_id
             left join invoice_lines il on il.invoice_id = inv.invoice_id
            where inv.cycle_id = p_cycle_id
            group by inv.invoice_id) t
       on (i.invoice_id = t.invoice_id)
     when matched then
       update set i.subtotal = t.subtotal, i.tax = t.tax, i.total = t.subtotal + t.tax;

    update bill_cycles
       set status = 'BILLED', billed_at = systimestamp
     where cycle_id = p_cycle_id;

    for r in (select i.invoice_id, i.customer_id,
                     json_object('invoiceId' value i.invoice_id, 'invoiceNo' value i.invoice_no,
                                 'total' value i.total, 'due' value to_char(i.due_date, 'YYYY-MM-DD')) as payload
                from invoices i
               where i.cycle_id = p_cycle_id) loop
      billing_events.publish('INVOICE_ISSUED', r.customer_id, null, p_cycle_id, r.payload);
    end loop;

    billing_log.info('billing_run',
      'billed ' || to_char(l_cycle.period_start, 'YYYY-MM') || ': ' || l_invoices || ' invoices'
      || case when l_failed > 0 then ', ' || l_failed || ' failed call records left out' end);
    return l_invoices;
  end bill_cycle;

end billing_run;
/
