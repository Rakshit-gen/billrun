create or replace package test_billing_rate as
  --%suite(billing_rate: pricing call records)

  --%beforeeach
  procedure setup;

  --%test(Calls abroad are charged in whole minutes, outside the bundle)
  procedure international;

  --%test(Off peak national calls are billed by the second after the first minute)
  procedure off_peak;

  --%test(The allowance goes to the earliest calls and splits the call that uses it up)
  procedure allowance_split;

  --%test(Each cycle starts with a full allowance)
  procedure allowance_per_cycle;

  --%test(A call after a plan change is rated on the new plan)
  procedure plan_change;

  --%test(A price change applies from its valid_from)
  procedure tariff_change;

  --%test(A call for a billed cycle goes into the next open one, marked late)
  procedure late_call;

  --%test(Records that can't be rated are failed with the reason)
  procedure failures;

  --%test(Rerating a cycle applies a corrected price and recounts allowances)
  procedure rerate;

  --%test(A billed cycle can't be rerated)
  --%throws(-20001)
  procedure rerate_billed;

  --%test(The batch rater gives the same results as the row by row one)
  procedure fast_matches_slow;
end test_billing_rate;
/
