# billrun

A telecom billing engine in Oracle PL/SQL. It loads call records from
switch files, rates them against tariff plans with allowances, peak hours
and holidays, and bills each month with prorated plan fees, adjustments
and tax. Then it runs receivables: payments allocated oldest invoice
first, dunning up to suspension, and an aging report. Invoices, payments
and allowance alerts go out as events on an Advanced Queuing queue, and
resellers see only their own customers through Virtual Private Database.
It runs on Oracle 19c and later; CI tests it on Oracle Database 23ai Free
with utPLSQL, with line coverage, compiler warnings and a benchmark in
every run.

`docs/design.md` has the data model and why it's built the way it is.

## How it works

```
CSV from a switch
   |  billing_load.stage_file    a file in a directory, read as an
   |  billing_load.stage_csv     external table; or the text itself
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
   |  billing_ar.record_payment  allocated oldest first
   |  billing_ar.run_dunning     reminder, warning, suspension
   v
payments, allocations, dunning_actions

every step above  ------------>  billing_events queue (INVOICE_ISSUED,
                                 PAYMENT_RECEIVED, DUNNING_*, ALLOWANCE_*)
```

`billing_jobs` runs the first three steps every 15 minutes, the bill run
at 02:00 on the 1st and dunning at 06:00 every day, through
DBMS_SCHEDULER.

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
- **Payment terms.** An invoice is issued the day the month ends (or the
  day it's billed, if later) and due `terms_days` after, 14 by default.
- **Payments** go to the customer's oldest open invoices first. What's
  left stays on account and pays the next invoice when it's issued. A
  payment carries the bank's reference, so the same payment sent twice is
  recorded once, and a different payment with a reference already used
  is refused.
- **Dunning.** 7 days overdue gets a reminder, 30 a warning, and 60
  suspends the customer. Each step is taken once per invoice. A payment
  that clears everything overdue makes the customer active again.
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
- **Parallel rating.** `rate_parallel` splits the subscribers with
  waiting records into chunks (`ntile` over their ids) and rates them in
  scheduler jobs with DBMS_PARALLEL_EXECUTE. A chunk owns whole
  subscribers, so no two sessions count the same allowance. A chunk that
  fails is retried once; if it fails again the call raises the chunk's
  error, and the chunks that finished stay rated.
- **External tables.** `stage_file` reads a switch file from a database
  directory with an inline external table (`EXTERNAL (...)` in the
  `FROM` clause, new in 18c), so there's no table to create per file.
  Oracle won't take binds there, so the file name is checked against a
  plain name pattern and quoted with `DBMS_ASSERT`.
- **Set based billing.** `bill_cycle` does its work in four statements: an insert of
  the invoices with gapless numbers from `row_number()`, an insert of all
  the lines (prorating with `CROSS APPLY`), a `MERGE` of the totals, and
  the cycle update. It doesn't commit, so it all goes in or none of it.
- **Set based allocation.** `billing_ar.allocate` is one `MERGE`: money on
  account and open invoices are laid end to end as running totals with
  `SUM() OVER`, and each overlap between the two is an allocation.
- **Pipelined functions.** `billing_ar.aging` returns the aging buckets
  per customer as rows (`select * from billing_ar.aging(date '...')`),
  and `billing_maint.partitions` lists the call record partitions with
  their months.
- **JSON.** `billing_export.invoice_json` builds an invoice with its lines
  using `JSON_OBJECT` and `JSON_ARRAYAGG`, for a portal or an ORDS
  endpoint.
- **Advanced Queuing.** Events are enqueued with `visibility =>
  on_commit`, so a consumer sees an invoice event only if the bill run
  committed, and none if it rolled back.
- **Virtual Private Database.** Once a session calls
  `billing_security.set_reseller`, a policy on the customer facing tables
  adds the reseller to every query and checks every insert and update.
  The reseller lives in an application context only the package can set.
- **Partition maintenance.** `billing_maint.compress_month` compresses an
  old month online; `purge_before` drops whole months, but never one
  with records still to rate or in an open cycle.
- **Locks.** Each process takes a DBMS_LOCK user lock, so a second copy
  of the rater fails at once with `-20005` instead of counting
  allowances twice. The parallel rater holds its lock for the session,
  across its commits.
- **Instrumentation.** The loader and the batch rater report progress through
  DBMS_APPLICATION_INFO, so `v$session` shows what a run is doing and
  how far it has got.
- **Errors** are named constants and exceptions in `billing_errors`
  (`-20001` to `-20010`). `billing_log` writes in an autonomous
  transaction, so the log line about a failure survives the rollback of
  the work, with `format_error_backtrace`.
- **Triggers** keep billed cycles frozen: no update or delete of their
  invoices or lines, no adjustment booked against them.
- **Reports** are views using analytic functions: `cycle_revenue`
  (`lag` for the change on last month), `top_usage` (`rank` within a
  cycle), `usage_by_destination` (`ratio_to_report`), `usage_by_hour`
  (running totals), `problems` and `allowance_left`.
- **Jobs.** `billing_jobs.create_jobs` sets up the three DBMS_SCHEDULER
  jobs. The job procedures are the only code that commits: a batch at a
  time, so a crash loses one batch.

## Running it

A schema on Oracle 19c or later with the privileges listed at the top of
`install.sql`, and quota on its tablespace. `stage_file` also needs a
directory object and UTL_FILE for the tests that use it.

```
sqlplus billrun/password@//host/service @install.sql
sqlplus billrun/password@//host/service @uninstall.sql
```

A month of made up traffic, end to end:

```sql
declare
  l_cycle    number;
  l_invoices pls_integer;
begin
  billing_demo.add_customers(100, date '2026-01-01');
  l_cycle := billing_admin.open_cycle(date '2026-03-01');
  billing_demo.stage_usage('switch-01.csv', 10000, date '2026-03-01');
  billing_jobs.process_usage;  -- commits
  l_invoices := billing_run.bill_cycle(l_cycle);
  commit;
end;
/
select * from problems;
select * from usage_by_destination;
```

With Docker or Podman, `make db` starts Oracle Free 23ai and `make ci`
installs utPLSQL and billrun, runs the tests and the benchmark: the same
`scripts/ci.sh` that GitHub Actions runs.

## Tests

utPLSQL suites in `test/`, one per package, each test in a transaction
that's rolled back. The few that have to commit (the jobs, event
delivery, partition maintenance) clean up after themselves. The fixture builds two plans with round prices, so
expected amounts can be worked out by hand: a plan change on the 11th of
January charges 10/31 of one fee and 21/31 of the other.

## Editions

Partitioning, compression and VPD need Enterprise Edition on 19c, and
partitioning is a paid option there. Oracle Database Free, which CI uses,
has all three. On Standard Edition 2 `cdrs` would have to be a plain
table and `sql/security/vpd.sql` left out.

## Not done on purpose

- No materialized view over the call records: a fast refresh needs a log
  on `cdrs`, and every rating update would write to it.
- No migration framework. `install.sql` builds the current schema.
- No ORDS module, though the JSON functions are what one would call.

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
