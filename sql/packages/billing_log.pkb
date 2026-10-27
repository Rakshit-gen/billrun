create or replace package body billing_log as

  procedure write(p_lvl varchar2, p_source varchar2, p_message varchar2, p_backtrace varchar2) is
    pragma autonomous_transaction;
  begin
    insert into run_log (lvl, source, message, backtrace)
    values (p_lvl, substr(p_source, 1, 60), substr(p_message, 1, 4000), substr(p_backtrace, 1, 4000));
    commit;
  end write;

  procedure info(p_source varchar2, p_message varchar2) is
  begin
    write('INFO', p_source, p_message, null);
  end info;

  procedure warn(p_source varchar2, p_message varchar2) is
  begin
    write('WARN', p_source, p_message, null);
  end warn;

  procedure error(p_source varchar2, p_message varchar2) is
  begin
    write('ERROR', p_source, p_message || ': ' || dbms_utility.format_error_stack,
          dbms_utility.format_error_backtrace);
  end error;

  procedure progress(p_action varchar2, p_done number) is
  begin
    dbms_application_info.set_module('billrun', p_action);
    dbms_application_info.set_client_info(p_done || ' rows done');
  end progress;

  procedure idle is
  begin
    dbms_application_info.set_module(null, null);
    dbms_application_info.set_client_info(null);
  end idle;

end billing_log;
/
