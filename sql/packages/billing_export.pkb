create or replace package body billing_export as

  function invoice_json(p_invoice_id invoices.invoice_id%type) return clob is
    l_doc clob;
  begin
    select json_object(
             'invoiceNo' value i.invoice_no,
             'period' value to_char(c.period_start, 'YYYY-MM'),
             'issued' value to_char(i.issued_at, 'YYYY-MM-DD'),
             'due' value to_char(i.due_date, 'YYYY-MM-DD'),
             'currency' value 'GBP',
             'customer' value json_object('id' value cu.customer_id, 'name' value cu.name,
                                          'taxRate' value cu.tax_rate),
             -- A scalar subquery's result is text to SQL/JSON; format json
             -- says it's already JSON, so it's nested, not quoted.
             'lines' value (select json_arrayagg(
                                     json_object('line' value l.line_no, 'kind' value l.kind,
                                                 'msisdn' value s.msisdn, 'description' value l.description,
                                                 'quantity' value l.quantity, 'amount' value l.amount
                                                 absent on null)
                                     order by l.line_no returning clob)
                              from invoice_lines l
                              left join subscribers s on s.subscriber_id = l.subscriber_id
                             where l.invoice_id = i.invoice_id) format json,
             'subtotal' value i.subtotal,
             'tax' value i.tax,
             'total' value i.total,
             'paid' value (select nvl(sum(a.amount), 0) from payment_allocations a
                            where a.invoice_id = i.invoice_id),
             'payments' value (select json_arrayagg(
                                        json_object('reference' value p.reference,
                                                    'received' value to_char(p.received_on, 'YYYY-MM-DD'),
                                                    'amount' value a.amount)
                                        order by p.received_on, p.payment_id returning clob)
                                 from payment_allocations a
                                 join payments p on p.payment_id = a.payment_id
                                where a.invoice_id = i.invoice_id) format json
             null on null
             returning clob)
      into l_doc
      from invoices i
      join bill_cycles c on c.cycle_id = i.cycle_id
      join customers cu on cu.customer_id = i.customer_id
     where i.invoice_id = p_invoice_id;
    return l_doc;
  exception
    when no_data_found then
      return null;
  end invoice_json;

  function cycle_json(p_cycle_id bill_cycles.cycle_id%type) return clob is
    l_doc  clob;
    l_sep  varchar2(1);
  begin
    dbms_lob.createtemporary(l_doc, true);
    dbms_lob.writeappend(l_doc, 1, '[');
    for r in (select invoice_id from invoices where cycle_id = p_cycle_id order by invoice_no) loop
      if l_sep is not null then
        dbms_lob.writeappend(l_doc, 1, l_sep);
      end if;
      dbms_lob.append(l_doc, invoice_json(r.invoice_id));
      l_sep := ',';
    end loop;
    dbms_lob.writeappend(l_doc, 1, ']');
    return l_doc;
  end cycle_json;

end billing_export;
/
