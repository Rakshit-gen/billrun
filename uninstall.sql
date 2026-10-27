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
                                   'PROBLEMS', 'ALLOWANCE_LEFT', 'BILLING_ERRORS', 'BILLING_LOG', 'BILLING_EVENTS',
                                   'BILLING_REF', 'BILLING_ADMIN', 'BILLING_LOAD', 'BILLING_RATE',
                                   'BILLING_RUN', 'BILLING_AR', 'BILLING_EXPORT', 'BILLING_JOBS', 'BILLING_DEMO', 'INVOICES_FROZEN',
                                   'INVOICE_LINES_FROZEN', 'ADJUSTMENTS_OPEN_CYCLE')) loop
    execute immediate 'drop ' || o.object_type || ' ' || o.object_name;
  end loop;
  for q in (select queue_table from user_queue_tables where queue_table = 'BILLING_EVENTS_QT') loop
    dbms_aqadm.drop_queue_table(queue_table => q.queue_table, force => true);
  end loop;
  -- Children before parents.
  for t in (select column_value as name
              from table(sys.odcivarchar2list(
                'USAGE_ALERTS', 'DUNNING_ACTIONS', 'PAYMENT_ALLOCATIONS', 'PAYMENTS', 'INVOICE_LINES', 'INVOICES', 'ALLOWANCE_USAGE', 'CDRS', 'CDR_STAGING', 'ADJUSTMENTS',
                'BILL_CYCLES', 'ALLOWANCES', 'TARIFFS', 'SUBSCRIBER_PLANS', 'SUBSCRIBERS', 'CUSTOMERS',
                'DESTINATIONS', 'HOLIDAYS', 'DEST_CLASSES', 'PLANS', 'RUN_LOG', 'BILLING_LOCKS'))) loop
    for x in (select table_name from user_tables where table_name = t.name) loop
      execute immediate 'drop table ' || x.table_name || ' purge';
    end loop;
  end loop;
  -- Types after the packages that use them, the table type before its row type.
  for t in (select type_name from user_types
             where type_name in ('AR_AGING_TAB', 'AR_AGING_ROW', 'BILLING_EVENT_T')
             order by case type_name when 'AR_AGING_TAB' then 1 else 2 end) loop
    execute immediate 'drop type ' || t.type_name;
  end loop;
end;
/
prompt billrun is uninstalled
