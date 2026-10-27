# billrun

A telecom billing engine in Oracle PL/SQL. It loads call records from
switch files, rates them against tariff plans with allowances, peak hours
and holidays, and bills each month with prorated plan fees, adjustments
and tax. It runs on Oracle 19c and later; CI tests it on Oracle Database
23ai Free with utPLSQL.

## How it works

```
CSV from a switch
   |  billing_load.stage_csv     one row per line, all text
   v
cdr_staging (NEW)
   |  billing_load.load_staged   check every field, find the subscriber
   v                             who had the number at the time
cdrs (NEW)  ------------------>  cdr_staging REJECTED, with the reason
   |  billing_rate.rate_pending  plan, destination, peak, tariff,
   v                             allowance, bill cycle
cdrs (RATED or FAILED, with the reason)
   |  billing_run.bill_cycle     fees, usage, adjustments, tax
   v
invoices + invoice_lines         frozen once the cycle is BILLED
```

`billing_jobs` runs the first three steps every 15 minutes and the bill
run at 02:00 on the 1st, through DBMS_SCHEDULER.

## The billing rules

- **Numbers change hands.** A subscriber holds an MSISDN from
  `active_from` to `active_to`, and a call record goes to whoever had the
  number when the call started. A number can't be given out while anyone
  holds it.
- **Destinations** are found by longest prefix: `4420` is London (LOCAL),
  `447` is a UK mobile, `44` the rest of the UK, `33` France.
- **Peak** is 08:00 to 20:00 on weekdays that aren't public holidays.
- **Tariffs** belong to a plan and say how a service to a destination
  class is counted and priced: a first increment, the increments after
  it, and a price per so many units. "60/60 at 0.10 per 60" is whole
  minutes; "60/1" is a minute and then by the second. A tariff for PEAK
  or OFFPEAK wins over one for ANY, and prices have `valid_from` and
  `valid_to`, so a price change applies to calls from that day.
- **Allowances** (Plus has 300 minutes, 500 texts and 5 GB of data)
  cover destinations in the bundle, not international or premium rate. They're used up in call time order, whatever order the
  records arrive in, and a call that runs past the end is split: part
  included, the rest charged.
- **Plan changes** take effect from a day. Calls are rated on the plan of
  the day they were made, and the bill charges each plan's fee for the
  days it was held.
- **Late calls.** Once a cycle is billed it's closed. A call that arrives
  for it afterwards goes on the next open cycle as its own line, marked
  "arrived late".
- **Invoices** are numbered `INV-YYYYMM-000001` upward without gaps. Tax
  is the customer's rate on the sum of the rounded lines, so the invoice
  always adds up to what's printed on it. A billed cycle's invoices and
  adjustments can't be changed; a correction is an adjustment on the next
  cycle.
- **Nothing is dropped.** A row that can't be loaded stays in staging as
  REJECTED with the reason; a record that can't be rated stays in `cdrs`
  as FAILED with the reason, and can be set back to NEW once the
  reference data is fixed. The `problems` view counts both by reason.
