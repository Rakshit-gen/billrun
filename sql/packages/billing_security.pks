create or replace package billing_security as
  -- Row level security (Virtual Private Database) for resellers. A
  -- session that calls set_reseller sees only that reseller's customers
  -- and everything hanging off them, in every query, whatever the SQL;
  -- billing's own sessions never set it and see everything. The
  -- policies are in sql/security/vpd.sql.

  ctx constant varchar2(30) := 'BILLRUN_CTX';

  procedure set_reseller(p_code varchar2);
  procedure clear_reseller;

  -- Policy functions, called by the database, not by code.
  function customers_policy(p_schema varchar2, p_object varchar2) return varchar2;
  function by_customer_policy(p_schema varchar2, p_object varchar2) return varchar2;
  function by_subscriber_policy(p_schema varchar2, p_object varchar2) return varchar2;
  function by_invoice_policy(p_schema varchar2, p_object varchar2) return varchar2;
end billing_security;
/
