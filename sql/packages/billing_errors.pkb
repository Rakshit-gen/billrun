create or replace package body billing_errors as

  procedure take_lock(p_name varchar2) is
    l_name billing_locks.name%type;
  begin
    select name into l_name from billing_locks where name = p_name for update nowait;
  exception
    when e_row_locked then
      raise_application_error(busy, p_name || ' is already running in another session');
  end take_lock;

end billing_errors;
/
