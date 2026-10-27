create or replace package billing_rate as
  -- Rates NEW call records. For each it finds the plan the subscriber
  -- was on, the destination class (longest prefix of the called number),
  -- peak or off peak, the tariff, and the bill cycle, then takes what it
  -- can from the plan's allowance and charges the rest. A record that
  -- can't be rated is marked FAILED with the reason, and can be set back
  -- to NEW once the reference data is fixed.
  --
  -- Records are rated per subscriber in time order, so the earliest
  -- calls use the allowance first however the records arrived. A call in
  -- a cycle that's already billed goes into the next open cycle, marked
  -- late. Neither function commits; both return the records processed.

  -- Rates in batches, with the reference tables cached in memory and
  -- one update statement per batch.
  function rate_pending(p_max_rows pls_integer default 100000, p_batch_size pls_integer default 1000)
    return pls_integer;

  -- The same rules one record and one query at a time: the way this is
  -- often first written. Kept as the reference that rate_pending is
  -- tested and timed against.
  function rate_pending_slow(p_max_rows pls_integer default 100000) return pls_integer;

  -- Puts an open cycle's records back to NEW, along with the month's
  -- FAILED ones, and clears its allowance counters, so the next
  -- rate_pending rates them all again: after a tariff was entered wrong,
  -- say. Raises cycle_not_open for a billed cycle. Returns the records
  -- reset.
  function rerate_cycle(p_cycle_id bill_cycles.cycle_id%type) return pls_integer;
end billing_rate;
/
