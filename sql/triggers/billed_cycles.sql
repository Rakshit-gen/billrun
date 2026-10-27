-- A billed cycle's invoices have gone to customers. These keep anyone
-- from changing them, or booking an adjustment against the cycle,
-- afterwards; a correction is an adjustment on the next cycle.

create or replace trigger invoices_frozen
  before update or delete on invoices
  for each row
declare
  l_status bill_cycles.status%type;
begin
  select status into l_status from bill_cycles where cycle_id = :old.cycle_id;
  if l_status = 'BILLED' then
    raise_application_error(billing_errors.cycle_not_open,
      'invoice ' || :old.invoice_no || ' is in a billed cycle and can''t change');
  end if;
end;
/

create or replace trigger invoice_lines_frozen
  before insert or update or delete on invoice_lines
  for each row
declare
  l_status bill_cycles.status%type;
begin
  select c.status into l_status
    from invoices i
    join bill_cycles c on c.cycle_id = i.cycle_id
   where i.invoice_id = coalesce(:new.invoice_id, :old.invoice_id);
  if l_status = 'BILLED' then
    raise_application_error(billing_errors.cycle_not_open,
      'invoice ' || coalesce(:new.invoice_id, :old.invoice_id) || ' is in a billed cycle and can''t change');
  end if;
end;
/

create or replace trigger adjustments_open_cycle
  before insert or update on adjustments
  for each row
declare
  l_status bill_cycles.status%type;
begin
  select status into l_status from bill_cycles where cycle_id = :new.cycle_id;
  if l_status = 'BILLED' then
    raise_application_error(billing_errors.cycle_not_open,
      'cycle ' || :new.cycle_id || ' is billed; put the adjustment on an open cycle');
  end if;
end;
/
