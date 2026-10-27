create or replace package billing_ar as
  -- Accounts receivable: payments, what's owed, and chasing it. Nothing
  -- here commits.

  -- Dunning steps, by days past the due date.
  reminder_days  constant pls_integer := 7;
  warning_days   constant pls_integer := 30;
  suspend_days   constant pls_integer := 60;

  -- Takes a payment and allocates it. A reference seen before returns
  -- the payment already taken if it's the same customer and amount (a
  -- resent feed), and raises payment_clash if it isn't.
  function record_payment(
    p_customer_id  customers.customer_id%type,
    p_amount       number,
    p_reference    varchar2,
    p_received_on  date,
    p_method       varchar2 default 'BANK'
  ) return payments.payment_id%type;

  -- Spreads the customer's unallocated payments over their unpaid
  -- invoices, oldest due first, in one statement. The bill run's job
  -- calls this after billing so credit on account pays the new invoice.
  -- Returns the number of allocations made.
  function allocate(p_customer_id customers.customer_id%type) return pls_integer;

  -- What's still owed on an invoice.
  function open_amount(p_invoice_id invoices.invoice_id%type) return number;

  -- Takes the dunning steps due on p_as_of: a reminder 7 days after the
  -- due date, a warning at 30, and at 60 the customer is suspended.
  -- Each step happens once per invoice. Returns the number of steps.
  function run_dunning(p_as_of date) return pls_integer;

  -- Open balances by age on p_as_of, one row per customer that owes
  -- anything or has money on account:
  --   select * from table(billing_ar.aging(date '2026-03-31'))
  function aging(p_as_of date) return ar_aging_tab pipelined;
end billing_ar;
/
