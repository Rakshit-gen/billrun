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
# reading stdin. Scripts get </dev/null so sqlplus exits when they end.
sql() {
  local dir=$1 login=$2
  shift 2
  "$RUNTIME" exec -i -w "$dir" "$CONTAINER" sqlplus -s -L "$login" "$@"
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

echo "== Granting $APP_USER what billrun needs"
sql /tmp "sys/$SYS_PASSWORD@$DB as sysdba" <<SQL
whenever sqlerror exit failure
grant create session, create table, create view, create sequence, create procedure,
      create trigger, create type, create job to $APP_USER;
alter user $APP_USER quota unlimited on users;
exit
SQL

app="$APP_USER/$APP_PASSWORD@$DB"

echo "== Installing billrun, removing it, and installing it again"
sql /tmp/billrun "$app" @install.sql </dev/null
sql /tmp/billrun "$app" @uninstall.sql </dev/null
sql /tmp/billrun "$app" @install.sql </dev/null

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

echo "== Benchmark"
sql /tmp/billrun "$app" @bench/bench.sql </dev/null
