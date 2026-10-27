create or replace package body billing_jobs as

  procedure process_usage is
    l_n       pls_integer;
    l_loaded  pls_integer := 0;
    l_rated   pls_integer := 0;
  begin
    loop
      l_n := billing_load.load_staged(p_max_rows => 50000);
      commit;
      l_loaded := l_loaded + l_n;
      exit when l_n = 0;
    end loop;
    loop
      l_n := billing_rate.rate_pending(p_max_rows => 50000);
      commit;
      l_rated := l_rated + l_n;
      exit when l_n = 0;
    end loop;
    l_n := billing_events.raise_allowance_alerts;
    commit;
    if l_loaded + l_rated > 0 then
      billing_log.info('process_usage', l_loaded || ' staged rows processed, ' || l_rated || ' call records rated');
    end if;
  exception
    when others then
      rollback;
      billing_log.error('process_usage', 'usage processing stopped');
      raise;
  end process_usage;

  procedure bill_last_month is
    l_this_month  date := trunc(sysdate, 'MM');
    l_cycle       bill_cycles.cycle_id%type;
    l_invoices    pls_integer;
  begin
    l_cycle := billing_admin.open_cycle(l_this_month);
    l_cycle := billing_admin.open_cycle(add_months(l_this_month, 1));
    commit;
    process_usage;
    l_cycle := billing_admin.open_cycle(add_months(l_this_month, -1));
    l_invoices := billing_run.bill_cycle(l_cycle);
    commit;
    l_invoices := billing_ar.allocate_all;
    commit;
  exception
    when others then
      rollback;
      billing_log.error('bill_last_month', 'billing ' || to_char(add_months(l_this_month, -1), 'YYYY-MM') || ' stopped');
      raise;
  end bill_last_month;

  procedure chase_overdue is
    l_steps pls_integer;
  begin
    l_steps := billing_ar.run_dunning(sysdate);
    commit;
  exception
    when others then
      rollback;
      billing_log.error('chase_overdue', 'dunning stopped');
      raise;
  end chase_overdue;

  procedure create_jobs is
  begin
    dbms_scheduler.create_job(
      job_name        => usage_job,
      job_type        => 'STORED_PROCEDURE',
      job_action      => 'BILLING_JOBS.PROCESS_USAGE',
      repeat_interval => 'FREQ=MINUTELY;INTERVAL=15',
      enabled         => true,
      comments        => 'Load and rate staged call records');
    dbms_scheduler.create_job(
      job_name        => bill_job,
      job_type        => 'STORED_PROCEDURE',
      job_action      => 'BILLING_JOBS.BILL_LAST_MONTH',
      repeat_interval => 'FREQ=MONTHLY;BYMONTHDAY=1;BYHOUR=2;BYMINUTE=0;BYSECOND=0',
      enabled         => true,
      comments        => 'Bill last month');
    dbms_scheduler.create_job(
      job_name        => dun_job,
      job_type        => 'STORED_PROCEDURE',
      job_action      => 'BILLING_JOBS.CHASE_OVERDUE',
      repeat_interval => 'FREQ=DAILY;BYHOUR=6;BYMINUTE=0;BYSECOND=0',
      enabled         => true,
      comments        => 'Remind, warn and suspend customers with overdue invoices');
  end create_jobs;

  procedure drop_jobs is
    -- ORA-27475, the job isn't there.
    e_no_job exception;
    pragma exception_init(e_no_job, -27475);

    procedure drop_one(p_name varchar2) is
    begin
      dbms_scheduler.drop_job(p_name, force => true);
    exception
      when e_no_job then
        null;
    end drop_one;
  begin
    drop_one(usage_job);
    drop_one(bill_job);
    drop_one(dun_job);
  end drop_jobs;

end billing_jobs;
/
