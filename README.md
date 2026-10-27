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

## The Oracle parts

- **Interval partitioning.** `cdrs` gets a partition a month as calls
  arrive. Every index on it is local, including the primary key
  `(cdr_id, started_at)` and the duplicate check, so a month can be
  compressed or dropped without rebuilding anything. The bill run
  filters on `started_at`, so it only reads the cycle's month.
- **Bulk loading.** `load_staged` reads staging with `BULK COLLECT ...
  LIMIT`, checks each row in PL/SQL so a rejection names the field and
  the value, then inserts the whole batch with one `FORALL ... SAVE
  EXCEPTIONS` statement. `SQL%BULK_ROWCOUNT` tells a row that matched no
  subscriber from one that went in, and `SQL%BULK_EXCEPTIONS` picks out
  the duplicates the unique index refused, without stopping the batch.
- **A partial index.** Oracle doesn't index rows whose keys are all null,
  so `cdr_staging_new_ix` on `case status when 'NEW' then staging_id end`
  holds only the rows still to load, however many million are done.
- **Two raters.** `rate_pending_slow` is the obvious version: a cursor
  loop with a query for the plan, the destination, the tariff, the cycle
  and the allowance per record. `rate_pending` caches the reference
  tables in associative arrays, rates a batch in memory, writes it back
  with one `FORALL UPDATE`, and keeps allowance counters in memory,
  flushing them with a `FORALL MERGE` per batch. A test rates the same
  generated month both ways and checks every field matches.
- **Set based billing.** `bill_cycle` does its work in four statements: an insert of
  the invoices with gapless numbers from `row_number()`, an insert of all
  the lines (prorating with `CROSS APPLY`), a `MERGE` of the totals, and
  the cycle update. It doesn't commit, so it all goes in or none of it.
- **Locks.** Each process takes its row in `billing_locks` with `SELECT
  ... FOR UPDATE NOWAIT`, so a second copy of the rater fails at once
  with `-20005` instead of counting allowances twice.
- **Errors** are named constants and exceptions in `billing_errors`
  (`-20001` to `-20007`). `billing_log` writes in an autonomous
  transaction, so the log line about a failure survives the rollback of
  the work, with `format_error_backtrace`.
- **Triggers** keep billed cycles frozen: no update or delete of their
  invoices or lines, no adjustment booked against them.
- **Reports** are views using analytic functions: `cycle_revenue`
  (`lag` for the change on last month), `top_usage` (`rank` within a
  cycle), `usage_by_destination` (`ratio_to_report`), `usage_by_hour`
  (running totals), `problems` and `allowance_left`.
- **Jobs.** `billing_jobs.create_jobs` sets up the two DBMS_SCHEDULER
  jobs. The job procedures are the only code that commits: a batch at a
  time, so a crash loses one batch.

## Running it

Any Oracle 19c or later schema with CREATE TABLE, VIEW, PROCEDURE,
TRIGGER and JOB, and quota on its tablespace:

```
sqlplus billrun/password@//host/service @install.sql
sqlplus billrun/password@//host/service @uninstall.sql
```

A month of made up traffic, end to end:

```sql
exec billing_demo.add_customers(100, date '2026-01-01')
select billing_admin.open_cycle(date '2026-03-01') from dual;
exec billing_demo.stage_usage('switch-01.csv', 10000, date '2026-03-01')
exec billing_jobs.process_usage
select billing_run.bill_cycle(cycle_id) from bill_cycles where period_start = date '2026-03-01';
select * from problems;
select * from usage_by_destination;
```

With Docker or Podman, `make db` starts Oracle Free 23ai and `make ci`
installs utPLSQL and billrun, runs the tests and the benchmark: the same
`scripts/ci.sh` that GitHub Actions runs.

## Tests

utPLSQL suites in `test/`, one per package, each test in a transaction
that's rolled back. The fixture builds two plans with round prices, so
expected amounts can be worked out by hand: a plan change on the 11th of
January charges 10/31 of one fee and 21/31 of the other.

## Limits

- Bill cycles are calendar months, one for everyone.
- Allowances aren't prorated: a line that joins on the 20th gets the
  whole month's.
- One currency, and one tax rate per customer.
- Staging takes comma separated files without quoting.

## Credits

Tests run on [utPLSQL](https://github.com/utPLSQL/utPLSQL) (Apache 2.0).
CI uses Gerald Venzl's [Oracle Free images](https://github.com/gvenzl/oci-oracle-free)
and the [setup-oracle-free](https://github.com/gvenzl/setup-oracle-free)
action.

MIT licensed.
