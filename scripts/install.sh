#!/usr/bin/env bash
# Copies billrun into a running Oracle Free container, grants the app
# user what billrun needs and installs it. ci.sh and bench.sh start with
# this; the container is the one ci.sh describes.
set -euo pipefail

RUNTIME=${RUNTIME:-podman}
CONTAINER=${CONTAINER:-oracledb}
SYS_PASSWORD=${SYS_PASSWORD:-billrun}
APP_USER=${APP_USER:-billrun}
APP_PASSWORD=${APP_PASSWORD:-billrun}
DB=//localhost/FREEPDB1

cd "$(dirname "$0")/.."

# Runs sqlplus in the container, in directory $1, as $2, on the rest,
# reading stdin. $login is left unquoted so "as sysdba" is its own words. Scripts get </dev/null so sqlplus exits when they end.
sql() {
  local dir=$1 login=$2
  shift 2
  "$RUNTIME" exec -i -w "$dir" "$CONTAINER" sqlplus -s -L $login "$@"
}

echo "== Copying billrun into the container"
"$RUNTIME" exec "$CONTAINER" rm -rf /tmp/billrun
"$RUNTIME" cp . "$CONTAINER:/tmp/billrun"

echo "== Creating the directory switch files are dropped in"
"$RUNTIME" exec "$CONTAINER" mkdir -p /opt/oracle/billrun_in

echo "== Granting $APP_USER what billrun needs"
sql /tmp "sys/$SYS_PASSWORD@$DB as sysdba" <<SQL
whenever sqlerror exit failure
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

echo "== Installing billrun"
sql /tmp/billrun "$APP_USER/$APP_PASSWORD@$DB" @install.sql </dev/null
