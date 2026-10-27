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
@@test_billing_ar.pks
@@test_billing_export.pks
@@test_billing_events.pks
@@test_event_delivery.pks
@@test_billing_security.pks
@@test_billing_admin.pks
@@test_billing_jobs.pks
@@test_fixture.pkb
@@test_billing_ref.pkb
@@test_billing_load.pkb
@@test_billing_rate.pkb
@@test_billing_run.pkb
@@test_billing_ar.pkb
@@test_billing_export.pkb
@@test_billing_events.pkb
@@test_event_delivery.pkb
@@test_billing_security.pkb
@@test_billing_admin.pkb
@@test_billing_jobs.pkb

@@../sql/check_errors.sql
prompt Tests are installed
