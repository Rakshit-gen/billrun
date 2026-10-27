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

-- The processes that must not run twice at once, each with the id of
-- its DBMS_LOCK user lock. A second copy fails at once instead of double
-- counting allowances or numbering invoices twice. User locks rather than
-- a row lock, because a parallel rating run commits after every chunk and
-- still has to hold its lock until the last one is done.
create table billing_locks (
  name     varchar2(30) primary key,
  lock_id  number not null constraint billing_locks_id_uk unique
);

insert into billing_locks (name, lock_id) values ('LOADER', 72610001);
insert into billing_locks (name, lock_id) values ('RATER', 72610002);
insert into billing_locks (name, lock_id) values ('BILLRUN', 72610003);
insert into billing_locks (name, lock_id) values ('NUMBERS', 72610004);
commit;
