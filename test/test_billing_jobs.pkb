create or replace package body test_billing_jobs as

  function job_count return pls_integer is
    l_n pls_integer;
  begin
    select count(*) into l_n
      from user_scheduler_jobs
     where job_name in (billing_jobs.usage_job, billing_jobs.bill_job, billing_jobs.dun_job);
    return l_n;
  end job_count;

  procedure create_and_drop is
    l_action user_scheduler_jobs.job_action%type;
  begin
    billing_jobs.drop_jobs;
    billing_jobs.create_jobs;
    ut.expect(job_count).to_equal(3);
    select job_action into l_action from user_scheduler_jobs where job_name = billing_jobs.bill_job;
    ut.expect(l_action).to_equal('BILLING_JOBS.BILL_LAST_MONTH');
    billing_jobs.drop_jobs;
    ut.expect(job_count).to_equal(0);
    billing_jobs.drop_jobs;
  exception
    when others then
      billing_jobs.drop_jobs;
      raise;
  end create_and_drop;

end test_billing_jobs;
/
