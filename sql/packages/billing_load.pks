create or replace package billing_load as
  -- Gets call records from the switches into cdrs. Neither function
  -- commits.

  -- Splits a CSV file into cdr_staging, a row per line. Lines are
  --   msisdn,service,called,started_at,quantity
  -- with started_at as YYYY-MM-DDTHH:MI:SS and quantity in seconds,
  -- messages or kilobytes. A first line starting "msisdn," is a header
  -- and skipped, as are empty lines. Returns the number of rows staged.
  function stage_csv(p_file_name varchar2, p_csv clob) return pls_integer;

  -- Checks up to p_max_rows NEW staging rows and moves the good ones to
  -- cdrs, p_batch_size at a time. The rest are marked REJECTED with the
  -- reason: a malformed field, a number nobody had at the time of the
  -- call, or a call that's already loaded. Returns rows processed.
  function load_staged(p_max_rows pls_integer default 100000, p_batch_size pls_integer default 1000)
    return pls_integer;
end billing_load;
/
