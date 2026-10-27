-- Removes everything install.sql created, data included.
set define off
set feedback off
set serveroutput on

begin
  billing_jobs.drop_jobs;
exception
  when others then
    -- billing_jobs may be the thing that's missing.
    null;
end;
/

begin
  for o in (select object_type, object_name
              from user_objects
             where object_type in ('VIEW', 'PACKAGE', 'TRIGGER')
               and object_name in ('CYCLE_REVENUE', 'TOP_USAGE', 'USAGE_BY_DESTINATION', 'USAGE_BY_HOUR',
                                   'PROBLEMS', 'ALLOWANCE_LEFT', 'BILLING_ERRORS', 'BILLING_LOG',
                                   'BILLING_REF', 'BILLING_ADMIN', 'BILLING_LOAD', 'BILLING_RATE',
                                   'BILLING_RUN', 'BILLING_JOBS', 'BILLING_DEMO', 'INVOICES_FROZEN',
                                   'INVOICE_LINES_FROZEN', 'ADJUSTMENTS_OPEN_CYCLE')) loop
    execute immediate 'drop ' || o.object_type || ' ' || o.object_name;
  end loop;
  -- Children before parents.
  for t in (select column_value as name
              from table(sys.odcivarchar2list(
                'INVOICE_LINES', 'INVOICES', 'ALLOWANCE_USAGE', 'CDRS', 'CDR_STAGING', 'ADJUSTMENTS',
                'BILL_CYCLES', 'ALLOWANCES', 'TARIFFS', 'SUBSCRIBER_PLANS', 'SUBSCRIBERS', 'CUSTOMERS',
                'DESTINATIONS', 'HOLIDAYS', 'DEST_CLASSES', 'PLANS', 'RUN_LOG', 'BILLING_LOCKS'))) loop
    for x in (select table_name from user_tables where table_name = t.name) loop
      execute immediate 'drop table ' || x.table_name || ' purge';
    end loop;
  end loop;
end;
/
prompt billrun is uninstalled
