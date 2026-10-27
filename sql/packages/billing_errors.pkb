create or replace package body billing_errors as

  function lock_id(p_name varchar2) return number is
    l_id billing_locks.lock_id%type;
  begin
    select lock_id into l_id from billing_locks where name = p_name;
    return l_id;
  end lock_id;

  procedure request(p_name varchar2, p_release_on_commit boolean) is
    l_rc pls_integer;
  begin
    l_rc := dbms_lock.request(
              id                => lock_id(p_name),
              lockmode          => dbms_lock.x_mode,
              timeout           => 0,
              release_on_commit => p_release_on_commit);
    -- 0 granted, 4 this session has it already.
    if l_rc = 1 then
      raise_application_error(busy, p_name || ' is already running in another session');
    elsif l_rc not in (0, 4) then
      raise_application_error(busy, 'could not lock ' || p_name || ': dbms_lock.request returned ' || l_rc);
    end if;
  end request;

  procedure take_lock(p_name varchar2) is
  begin
    request(p_name, p_release_on_commit => true);
  end take_lock;

  procedure hold_lock(p_name varchar2) is
  begin
    request(p_name, p_release_on_commit => false);
  end hold_lock;

  procedure release_lock(p_name varchar2) is
    l_rc pls_integer;
  begin
    l_rc := dbms_lock.release(lock_id(p_name));
  end release_lock;

end billing_errors;
/
