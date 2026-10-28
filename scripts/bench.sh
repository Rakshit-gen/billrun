#!/usr/bin/env bash
# Runs bench/bench.sql once for each size in $SIZES, given as
# records:customers:runs, on a billrun already installed by install.sh,
# then prints the slowest statements and the plan of the slowest one.
#   SIZES="10000:500:3 50000:2000:3" ./scripts/bench.sh
set -euo pipefail

RUNTIME=${RUNTIME:-podman}
CONTAINER=${CONTAINER:-oracledb}
SYS_PASSWORD=${SYS_PASSWORD:-billrun}
APP_USER=${APP_USER:-billrun}
APP_PASSWORD=${APP_PASSWORD:-billrun}
DB=//localhost/FREEPDB1

SIZES=${SIZES:-50000:2000:3}
app="$APP_USER/$APP_PASSWORD@$DB"

cd "$(dirname "$0")/.."

# Runs sqlplus in the container, in directory $1, as $2, on the rest,
# reading stdin. $login is left unquoted so "as sysdba" is its own words. Scripts get </dev/null so sqlplus exits when they end.
sql() {
  local dir=$1 login=$2
  shift 2
  "$RUNTIME" exec -i -w "$dir" "$CONTAINER" sqlplus -s -L $login "$@"
}

echo "== Where the benchmark runs"
echo "runner: $(nproc) CPUs, $(lscpu 2>/dev/null | sed -n 's/^Model name: *//p' | head -1), $(free -g 2>/dev/null | awk '/^Mem:/ { print $2 " GB" }') memory"
sql /tmp "sys/$SYS_PASSWORD@$DB as sysdba" <<SQL
set heading off feedback off pagesize 0
select banner_full from v\$version;
select 'cpu_count ' || value from v\$parameter where name = 'cpu_count';
select 'sga_target ' || round(value / 1048576) || ' MB' from v\$parameter where name = 'sga_target';
exit
SQL
for size in $SIZES; do
  IFS=: read -r records customers runs <<<"$size"
  echo "== Benchmark, $records records"
  sql /tmp/billrun "$app" @bench/bench.sql "$records" "$customers" "$runs" </dev/null
done

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

