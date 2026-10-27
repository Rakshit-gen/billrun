create or replace package test_billing_load as
  --%suite(billing_load: getting call records in)

  --%beforeeach
  procedure setup;

  --%test(Staging skips the header and blank lines and copes with CRLF)
  procedure stages_lines;

  --%test(Good rows are loaded, with called numbers cleaned up)
  procedure loads_good_rows;

  --%test(Bad rows are rejected with a reason naming the problem)
  procedure rejects_with_reasons;

  --%test(A record sent twice is loaded once)
  procedure rejects_duplicates;

  --%test(Loading twice does nothing the second time)
  procedure loads_once;
end test_billing_load;
/
