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

echo "== Copying utPLSQL into the container"
curl -fsSL -o "$work/utPLSQL.tar.gz" \
  "https://github.com/utPLSQL/utPLSQL/releases/download/v$UTPLSQL_VERSION/utPLSQL.tar.gz"
echo "$UTPLSQL_SHA256  $work/utPLSQL.tar.gz" | sha256sum -c -
tar -xzf "$work/utPLSQL.tar.gz" -C "$work"
"$RUNTIME" exec "$CONTAINER" rm -rf /tmp/utPLSQL
"$RUNTIME" cp "$work/utPLSQL" "$CONTAINER:/tmp/utPLSQL"

echo "== Installing utPLSQL $UTPLSQL_VERSION"
sql /tmp/utPLSQL/source "sys/$SYS_PASSWORD@$DB as sysdba" @install_headless.sql UT3 "$SYS_PASSWORD" users </dev/null

app="$APP_USER/$APP_PASSWORD@$DB"

./scripts/install.sh

echo "== Removing billrun and installing it again"
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

./scripts/bench.sh

echo "== Reports on three generated months"
mkdir -p build
sql /tmp/billrun "$app" @reports/run.sql </dev/null | tee build/reports.txt
