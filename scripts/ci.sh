#!/usr/bin/env bash
# Installs billrun and utPLSQL into a running Oracle Free container, runs
# the tests and the benchmark. CI starts the container with
# gvenzl/setup-oracle-free; locally, something like
#   docker run -d --name oracledb -p 1521:1521 -e ORACLE_PASSWORD=billrun \
#     -e APP_USER=billrun -e APP_USER_PASSWORD=billrun gvenzl/oracle-free:23
#   RUNTIME=docker ./scripts/ci.sh
set -euo pipefail

RUNTIME=${RUNTIME:-podman}
CONTAINER=${CONTAINER:-oracledb}
SYS_PASSWORD=${SYS_PASSWORD:-billrun}
APP_USER=${APP_USER:-billrun}
APP_PASSWORD=${APP_PASSWORD:-billrun}
UTPLSQL_VERSION=3.2.2
UTPLSQL_SHA256=02bb981528e6f97f92b7faaced01ae56da91fe420aacf96624c5c12f4d4f1c5c
DB=//localhost/FREEPDB1

cd "$(dirname "$0")/.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# Runs sqlplus in the container, in directory $1, as $2, on the rest,
# reading stdin. $login is left unquoted so "as sysdba" is its own words. Scripts get </dev/null so sqlplus exits when they end.
sql() {
  local dir=$1 login=$2
  shift 2
  "$RUNTIME" exec -i -w "$dir" "$CONTAINER" sqlplus -s -L $login "$@"
}

echo "== Copying files into the container"
curl -fsSL -o "$work/utPLSQL.tar.gz" \
  "https://github.com/utPLSQL/utPLSQL/releases/download/v$UTPLSQL_VERSION/utPLSQL.tar.gz"
echo "$UTPLSQL_SHA256  $work/utPLSQL.tar.gz" | sha256sum -c -
tar -xzf "$work/utPLSQL.tar.gz" -C "$work"
"$RUNTIME" exec "$CONTAINER" rm -rf /tmp/billrun /tmp/utPLSQL
"$RUNTIME" cp "$work/utPLSQL" "$CONTAINER:/tmp/utPLSQL"
"$RUNTIME" cp . "$CONTAINER:/tmp/billrun"

echo "== Installing utPLSQL $UTPLSQL_VERSION"
sql /tmp/utPLSQL/source "sys/$SYS_PASSWORD@$DB as sysdba" @install_headless.sql UT3 "$SYS_PASSWORD" users </dev/null

echo "== Creating the directory switch files are dropped in"
"$RUNTIME" exec "$CONTAINER" mkdir -p /opt/oracle/billrun_in

echo "== Granting $APP_USER what billrun needs"
sql /tmp "sys/$SYS_PASSWORD@$DB as sysdba" <<SQL
whenever sqlerror exit failure
show parameter cursor_sharing
grant create session, create table, create view, create sequence, create procedure,
      create trigger, create type, create job to $APP_USER;
grant execute on dbms_aq to $APP_USER;
grant execute on dbms_aqadm to $APP_USER;
grant execute on utl_file to $APP_USER;
grant execute on dbms_lock to $APP_USER;
grant execute on dbms_parallel_execute to $APP_USER;
grant execute on dbms_rls to $APP_USER;
grant create any context, drop any context to $APP_USER;
create or replace directory billrun_in as '/opt/oracle/billrun_in';
grant read, write on directory billrun_in to $APP_USER;
alter user $APP_USER quota unlimited on users;
exit
SQL

app="$APP_USER/$APP_PASSWORD@$DB"

echo "== Installing billrun, removing it, and installing it again"
sql /tmp/billrun "$app" @install.sql </dev/null
sql /tmp/billrun "$app" @uninstall.sql </dev/null
sql /tmp/billrun "$app" @install.sql </dev/null

echo "== Compiler warnings"
sql /tmp/billrun "$app" @sql/lint.sql </dev/null

echo "== Installing the tests"
sql /tmp/billrun/test "$app" @install.sql </dev/null

echo "== Running the tests"
sql /tmp/billrun "$app" <<SQL | tee "$work/tests.txt"
set serveroutput on size unlimited
set linesize 200
exec ut.run('$APP_USER')
exit
SQL
if ! grep -Eq '^[1-9][0-9]* tests, 0 failed, 0 errored' "$work/tests.txt"; then
  echo "tests failed" >&2
  exit 1
fi

echo "== Coverage of the billrun packages by the tests"
mkdir -p build
sql /tmp "$app" <<SQL > build/coverage.xml
set pagesize 0 linesize 32767 long 100000000 longchunksize 32767 trimspool on feedback off heading off
select *
  from table(ut.run(a_path => '$APP_USER',
                    a_reporter => ut_coverage_cobertura_reporter(),
                    a_exclude_objects => ut_varchar2_list('$APP_USER.test_fixture')));
exit
SQL
rate=$(grep -o 'line-rate="[0-9.]*"' build/coverage.xml | head -1 | grep -o '[0-9.]*' || true)
if [ -z "$rate" ]; then
  echo "no coverage report" >&2
  head -40 build/coverage.xml >&2
  exit 1
fi
awk -v r="$rate" 'BEGIN { printf "line coverage: %.1f%%\n", r * 100 }'

echo "== Benchmark"
sql /tmp/billrun "$app" @bench/bench.sql </dev/null

echo "== Slowest statements in the benchmark, and the plan of the slowest SQL"
sql /tmp "sys/$SYS_PASSWORD@$DB as sysdba" <<SQL
set linesize 250 pagesize 100 long 100000
column sql_text format a120 word_wrapped
column secs format 9990.00
select sql_id, executions, round(elapsed_time / 1e6, 2) as secs, substr(sql_text, 1, 240) as sql_text
  from v\$sql
 where parsing_schema_name = upper('$APP_USER')
 order by elapsed_time desc
 fetch first 8 rows only;
column plan_table_output format a200
select t.plan_table_output
  from (select sql_id, child_number from v\$sql
         where parsing_schema_name = upper('$APP_USER')
           and command_type <> 47 -- PL/SQL blocks have no plan
         order by elapsed_time desc fetch first 1 row only) s,
       table(dbms_xplan.display_cursor(s.sql_id, s.child_number, 'TYPICAL')) t;
exit
SQL
