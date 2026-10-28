# Changelog

## Unreleased

- The aging report sums allocations once instead of once per invoice
  and per payment: 0.10 s instead of 4.16 s for 2,000 customers.
- A bench workflow runs the benchmark at 10,000, 50,000 and 200,000
  call records on every push to main, or at chosen sizes by hand.
- The benchmark takes its size as arguments, runs each rater three
  times with the median and range, fails if the batch or parallel
  rater rates any record differently from the row by row one, and
  times payments, dunning and the aging report.
- `scripts/install.sh` and `scripts/bench.sh` split out of `ci.sh`, and
  `make bench`.

## 1.0.0, 2026-10-27

First release.

### Billing
- Call records loaded from switch files, by `stage_csv` or from a
  database directory by `stage_file`, checked field by field; bad rows
  are kept with the reason.
- Rating against plans, destinations by longest prefix, peak hours,
  holidays and allowances, in a batch rater, a row by row one that the
  tests compare it with, and a parallel one.
- Monthly bill run: prorated plan fees, usage, late calls, adjustments
  and tax, with gapless invoice numbers, in one transaction.
- Rerating of an open cycle after a price correction.

### Receivables
- Payments, idempotent on the bank reference, allocated oldest invoice
  first; credit on account pays the next invoice.
- Dunning at 7, 30 and 60 days, suspending at 60, and reactivation on
  payment.
- Aging report as a pipelined function.

### Integration and security
- Events for invoices, payments, dunning and allowance alerts on an
  Advanced Queuing queue, visible on commit only.
- JSON export of invoices.
- Reseller isolation with Virtual Private Database.

### Operations
- Scheduler jobs for usage, the bill run and dunning.
- Partition compression and purging by month.
- Progress in `v$session` through DBMS_APPLICATION_INFO.
- Reports: month end revenue, aged debt and switch feed quality.

### Fixed before release
- The bill run's line insert could reuse a plan built for a few
  invoices and reread the month's calls per invoice: 246 s for 2,000
  invoices, now 3.30 s. See `docs/rca.md`.
- `stage_file` failed with ORA-14355 because `position(1:4000)` read as
  a bind. See `docs/rca.md`.

### Upgrading
Nothing to upgrade from. `uninstall.sql` then `install.sql` replaces a
schema.
