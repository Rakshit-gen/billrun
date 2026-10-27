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
