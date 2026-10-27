create or replace package billing_maint as
  -- Housekeeping on the call record partitions. These are DDL, so each
  -- call commits.

  -- Rewrites a month's partition compressed, online, keeping its local
  -- indexes usable: for months that are billed and won't change much.
  procedure compress_month(p_month date);

  -- Drops the partitions of months from p_from (all of them if null) to
  -- before p_before, the way a
  -- retention rule ("keep call records 24 months") is carried out: an
  -- instant metadata change, not a delete of millions of rows. A month
  -- is skipped, and logged, while it has records still to rate or rated
  -- into an open cycle. Returns the partitions dropped.
  function purge_before(p_before date, p_from date default null) return pls_integer;

  -- The name of the partition holding p_month, or null if it has none.
  function partition_of(p_month date) return varchar2;

  -- The months that have a partition, with their size and compression,
  -- for a quick look:
  --   select * from table(billing_maint.partitions)
  function partitions return sys.odcivarchar2list pipelined;
end billing_maint;
/
