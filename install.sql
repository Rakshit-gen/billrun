-- Installs billrun into the current schema:
--   sqlplus billrun/password@//localhost/FREEPDB1 @install.sql
-- The schema needs CREATE TABLE, VIEW, PROCEDURE, TRIGGER, TYPE and JOB,
-- EXECUTE on DBMS_AQ, DBMS_AQADM, DBMS_LOCK and DBMS_PARALLEL_EXECUTE,
-- and quota on its tablespace.

whenever sqlerror exit failure rollback
set define off
set feedback off
set serveroutput on

prompt Creating tables
@@sql/schema/01_reference.sql
@@sql/schema/02_customers.sql
@@sql/schema/03_tariffs.sql
@@sql/schema/04_cycles.sql
@@sql/schema/05_staging.sql
@@sql/schema/06_cdrs.sql
@@sql/schema/07_invoices.sql
@@sql/schema/08_ops.sql
@@sql/schema/09_receivables.sql

prompt Creating types and the events queue
@@sql/types/ar_types.sql
@@sql/types/event_types.sql
@@sql/schema/10_events.sql

prompt Compiling packages
@@sql/packages/billing_errors.pks
@@sql/packages/billing_log.pks
@@sql/packages/billing_events.pks
@@sql/packages/billing_ref.pks
@@sql/packages/billing_admin.pks
@@sql/packages/billing_load.pks
@@sql/packages/billing_rate.pks
@@sql/packages/billing_run.pks
@@sql/packages/billing_ar.pks
@@sql/packages/billing_export.pks
@@sql/packages/billing_jobs.pks
@@sql/packages/billing_demo.pks
@@sql/packages/billing_errors.pkb
@@sql/packages/billing_log.pkb
@@sql/packages/billing_events.pkb
@@sql/packages/billing_ref.pkb
@@sql/packages/billing_admin.pkb
@@sql/packages/billing_load.pkb
@@sql/packages/billing_rate.pkb
@@sql/packages/billing_run.pkb
@@sql/packages/billing_ar.pkb
@@sql/packages/billing_export.pkb
@@sql/packages/billing_jobs.pkb
@@sql/packages/billing_demo.pkb

prompt Creating triggers and views
@@sql/triggers/billed_cycles.sql
@@sql/views/reports.sql

prompt Loading reference data
@@sql/data/seed.sql

@@sql/check_errors.sql
prompt billrun is installed
