-- Month end revenue, for finance closing a billed month.
--   @reports/month_end.sql YYYY-MM
--
-- Requirement: for the month, the number of invoices and what was
-- invoiced by reseller (customers with no reseller are Direct), split
-- into plan fees, usage and adjustments, with tax and total, and a total
-- row. The figures must agree with the invoices to the cent, and the
-- report says so or fails.

column reseller    format a20             heading 'Reseller'
column invoices    format 99990           heading 'Invoices'
column fees        format 9,999,990.00    heading 'Plan fees'
column usage       format 9,999,990.00    heading 'Usage'
column adjustments format 9,999,990.00    heading 'Adjustments'
column subtotal    format 9,999,990.00    heading 'Subtotal'
column tax         format 9,999,990.00    heading 'Tax'
column total       format 99,999,990.00   heading 'Total'

prompt
prompt Month end revenue, &1
prompt

-- Lines are summed per invoice first, so each invoice is counted once
-- and its header can be compared with its lines.
with per_invoice as (
  select nvl(r.name, 'Direct') as reseller,
         i.subtotal, i.tax, i.total,
         nvl(sum(case l.kind when 'RECURRING' then l.amount end), 0) as fees,
         nvl(sum(case l.kind when 'USAGE' then l.amount end), 0) as usage,
         nvl(sum(case l.kind when 'ADJUSTMENT' then l.amount end), 0) as adjustments
    from invoices i
    join bill_cycles c on c.cycle_id = i.cycle_id
    join customers cu on cu.customer_id = i.customer_id
    left join resellers r on r.reseller_id = cu.reseller_id
    left join invoice_lines l on l.invoice_id = i.invoice_id
   where c.period_start = to_date('&1', 'YYYY-MM')
   group by i.invoice_id, nvl(r.name, 'Direct'), i.subtotal, i.tax, i.total)
select case grouping(reseller) when 1 then 'Total' else reseller end as reseller,
       count(*) as invoices,
       sum(fees) as fees, sum(usage) as usage, sum(adjustments) as adjustments,
       sum(subtotal) as subtotal, sum(tax) as tax, sum(total) as total
  from per_invoice
 group by rollup (reseller)
 order by grouping(reseller), reseller;

declare
  l_bad pls_integer;
begin
  select count(*)
    into l_bad
    from (select i.invoice_id
            from invoices i
            join bill_cycles c on c.cycle_id = i.cycle_id
            left join invoice_lines l on l.invoice_id = i.invoice_id
           where c.period_start = to_date('&1', 'YYYY-MM')
           group by i.invoice_id, i.subtotal, i.tax, i.total
          having nvl(sum(l.amount), 0) <> i.subtotal or i.subtotal + i.tax <> i.total);
  if l_bad > 0 then
    raise_application_error(-20000, l_bad || ' invoices don''t agree with their lines');
  end if;
  dbms_output.put_line('Check: every invoice equals the sum of its lines plus tax.');
end;
/
