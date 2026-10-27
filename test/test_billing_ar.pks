create or replace package test_billing_ar as
  --%suite(billing_ar: payments, dunning and aging)

  --%beforeeach
  procedure setup;

  --%test(Invoices are dated after the cycle and due after the customer's terms)
  procedure due_dates;

  --%test(A payment pays the oldest invoice first and the rest goes to the next)
  procedure oldest_first;

  --%test(Money on account pays the next invoice once it's billed)
  procedure credit_on_account;

  --%test(A resent payment is taken once)
  procedure resent_payment;

  --%test(A reference reused for a different payment is refused)
  --%throws(-20008)
  procedure reference_clash;

  --%test(Dunning reminds, warns, then suspends, each once, and payment reactivates)
  procedure dunning_steps;

  --%test(Aging puts open amounts in buckets by days overdue)
  procedure aging_buckets;
end test_billing_ar;
/
