-- Installs the utPLSQL suites into the billrun schema, after install.sql.
-- Run them with:
--   exec ut.run('billrun')

whenever sqlerror exit failure rollback
set define off
set feedback off

prompt Compiling tests
@@test_fixture.pks
@@test_billing_ref.pks
@@test_billing_load.pks
@@test_billing_rate.pks
@@test_billing_run.pks
@@test_billing_admin.pks
@@test_billing_jobs.pks
@@test_fixture.pkb
@@test_billing_ref.pkb
@@test_billing_load.pkb
@@test_billing_rate.pkb
@@test_billing_run.pkb
@@test_billing_admin.pkb
@@test_billing_jobs.pkb

@@../sql/check_errors.sql
prompt Tests are installed
