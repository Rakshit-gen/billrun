# Root cause analyses

Two problems found in CI while building billrun, written up the way
they were worked out. Every number is from a CI log; the run ids are
GitHub Actions runs of this repository.

## 1. The bill run took four minutes for 2,000 invoices

**Symptom.** The benchmark bills a generated month: 2,000 customers,
49,499 rated call records. `bill_cycle` took 246.23 s in run
40534843576 and 287.33 s in run 40535939566, while `rate_pending`
rated the same records in 3.20 s in the first of those runs. Billing does less work than rating, so it should
have been faster.

**Finding the statement.** CI was changed to print the most expensive
statements in `v$sql` after the benchmark. In run 40534843576 one
statement took 244.51 s of the 246.23: the `INSERT INTO invoice_lines`,
with 9 executions. The plan print picked the benchmark's PL/SQL block,
which has no plan, so the next change skipped PL/SQL (`command_type <>
47`) and run 40535939566 printed the insert's plan (hash 730689316):

```
| Id | Operation                                      | Name          | Rows |
|  3 |    NESTED LOOPS                                |               |    3 |
|* 4 |     TABLE ACCESS FULL                          | INVOICES      |    1 |
|  5 |     VIEW                                       |               |    3 |
|  6 |      UNION ALL PUSHED PREDICATE                |               |    3 |
| 21 |         PARTITION RANGE ALL                    |               |    1 |
|*22 |          TABLE ACCESS BY LOCAL INDEX ROWID ... | CDRS          |    1 |
|*23 |           INDEX RANGE SCAN                     | CDRS_CYCLE_IX |    1 |
|*27 |         TABLE ACCESS BY INDEX ROWID            | SUBSCRIBERS   |    1 |

  23 - access("C"."CYCLE_ID"=:B4)
  27 - filter("S"."CUSTOMER_ID"="I"."CUSTOMER_ID")
```

**What the plan says.** The insert joined `invoices` to a union of the
fee, usage and adjustment lines. The optimizer expected one invoice
(step 4, Rows 1), so it drove a nested loop from `invoices` and pushed
the join into each branch of the union. For each invoice, step 23 read
every rated record in the cycle, through the local index in every
partition (step 21, partitions 1 to 1048575), and only step 27, after
the join to `subscribers`, threw away the ones belonging to other
customers. 2,000 invoices meant reading the month's call records 2,000
times.

**Why it expected one invoice.** 9 executions under one cursor: the
bill runs in the test suite and the benchmark's shared a plan. The tests
bill a handful of customers, so a plan built for a tiny `invoices` was
right when it was made, and the benchmark reused it at 2,000.

**Root cause.** The shape of the statement let its plan depend on the
size of `invoices`. The join to `invoices` was only there to get each
line its invoice id and number the lines per invoice.

**Fix** (commit 9dc8beb). The lines no longer join `invoices`. They're
numbered per customer (`row_number() over (partition by customer_id
...)`), which is the same thing because a customer has one invoice per
cycle, and each line gets its invoice id from a scalar subquery on the
unique key `(customer_id, cycle_id)`. Oracle caches a scalar subquery's
result per input value, so that's one index lookup per customer. With
nothing to drive a loop from, the call records are read once.

**Result.** Run 40538698448: `bill_cycle` 3.30 s for the same month.
The new insert (sql id 2jmgf5x1up6mq) took 1.35 s over its 14
executions.

**Prevention.** CI prints the slowest statements and the plan of the
slowest one on every run, so a plan like this shows up in the log of
the push that causes it.

## 2. ORA-14355 on a statement with no binds

**Symptom.** `billing_load.stage_file` reads a switch file through an
inline external table. Its test failed in run 40537164981 with
`ORA-14355: cannot use bind variables in the access parameters clause`.

**First change.** The statement did bind the file name, in the
`LOCATION` clause. That was replaced by a literal, checked against a
plain file name pattern and quoted with `DBMS_ASSERT.ENQUOTE_LITERAL`.
Run 40537915386 failed with the same error. The statement now had no
binds at all.

**A wrong guess.** With `cursor_sharing = FORCE` Oracle turns literals
into binds. A `cursor_sharing_exact` hint went in, with a `show
parameter cursor_sharing` in the CI grants. Run 40538267478 printed
`cursor_sharing EXACT` and failed the same way, so that wasn't it.

**Root cause.** Reading the access parameters again for anything SQL
could take for a bind: `(line position(1:4000) char(4000))`. To SQL,
`:4000` is a bind variable placeholder, and the access parameters are
part of the SQL text. The ORACLE_LOADER driver also takes a field
position as `start-end`.

**Fix** (commit 12832b6). `position(1-4000)`, and the hint and the
debugging line removed. Run 40538698448 passed, 63 tests.

**What I'd do sooner next time.** The error named the access parameters
clause and the first change was to the `LOCATION` clause. Reading the
clause the error named, character by character, would have found the
colon in one run instead of three. Removing the file name bind didn't
change the error, so it may never have been part of the problem; the
validated literal stays, as it's no less safe.
