create or replace package billing_log as
  -- Writes to run_log in an autonomous transaction: the line is kept
  -- even when the caller rolls back.

  procedure info(p_source varchar2, p_message varchar2);
  procedure warn(p_source varchar2, p_message varchar2);

  -- Logs p_message with the current error stack and backtrace. Call it
  -- from an exception handler, then raise.
  procedure error(p_source varchar2, p_message varchar2);

  -- What a long running step is doing, for operations to watch in
  -- V$SESSION (module, action and client_info) while it runs.
  procedure progress(p_action varchar2, p_done number);
  procedure idle;
end billing_log;
/
