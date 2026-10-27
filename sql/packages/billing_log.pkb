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

end billing_log;
/
