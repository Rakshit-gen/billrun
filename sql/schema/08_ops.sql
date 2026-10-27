-- What the jobs did, written in autonomous transactions so a log line
-- survives the rollback of the work it describes.
create table run_log (
  log_id     number generated always as identity primary key,
  logged_at  timestamp default systimestamp not null,
  lvl        varchar2(5) not null constraint run_log_lvl_ck check (lvl in ('INFO', 'WARN', 'ERROR')),
  source     varchar2(60) not null,
  message    varchar2(4000),
  backtrace  varchar2(4000)
);

-- One row per process that must not run twice at once. A process locks
-- its row with select for update nowait; a second copy fails at once
-- instead of double counting allowances or numbering invoices twice.
create table billing_locks (
  name  varchar2(30) primary key
);

insert into billing_locks (name) values ('LOADER');
insert into billing_locks (name) values ('RATER');
insert into billing_locks (name) values ('BILLRUN');
insert into billing_locks (name) values ('NUMBERS');
commit;
