create or replace package billing_run as
  -- Bills a cycle: one invoice per customer that had service in it, with
  --   RECURRING   each plan's monthly fee for the days the line was on
  --               it, so a plan change mid month is charged pro rata;
  --   USAGE       the rated calls, by line, service and destination;
  --   ADJUSTMENT  credits and charges booked against the cycle;
  -- then tax at the customer's rate. Lines are rounded to cents and the
  -- invoice adds up the rounded lines, so it always matches what's on it.
  --
  -- Refuses a cycle that's billed already, or that has calls still to
  -- rate (FAILED ones don't hold it up; they're left for a later cycle
  -- once fixed). Doesn't commit: the invoices and the cycle's change to
  -- BILLED go together or not at all.

  -- Returns the number of invoices written.
  function bill_cycle(p_cycle_id bill_cycles.cycle_id%type) return pls_integer;
end billing_run;
/
