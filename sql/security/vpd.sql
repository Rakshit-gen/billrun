-- Virtual Private Database policies for resellers. With a reseller set
-- (billing_security.set_reseller) every query on these tables gets a
-- predicate added by the database, so a portal can't show another
-- reseller's data by mistake or by a crafted query. Without one, the
-- policy functions return no predicate and nothing changes.
--
-- Needs CREATE ANY CONTEXT and EXECUTE on DBMS_RLS. VPD is an Enterprise
-- Edition feature on 19c; Oracle Free has it.

create or replace context billrun_ctx using billing_security;

declare
  procedure protect(p_table varchar2, p_function varchar2) is
    e_no_policy exception;
    pragma exception_init(e_no_policy, -28102);
  begin
    begin
      dbms_rls.drop_policy(user, p_table, 'reseller_scope');
    exception
      when e_no_policy then
        null;
    end;
    dbms_rls.add_policy(
      object_schema   => user,
      object_name     => p_table,
      policy_name     => 'reseller_scope',
      function_schema => user,
      policy_function => 'billing_security.' || p_function,
      statement_types => 'select, insert, update, delete',
      -- Rows a reseller inserts or updates have to be theirs too.
      update_check    => true,
      -- Asked again whenever the context changes, not once per parse.
      policy_type     => dbms_rls.context_sensitive);
  end protect;
begin
  protect('CUSTOMERS', 'customers_policy');
  protect('SUBSCRIBERS', 'by_customer_policy');
  protect('INVOICES', 'by_customer_policy');
  protect('PAYMENTS', 'by_customer_policy');
  protect('ADJUSTMENTS', 'by_customer_policy');
  protect('SUBSCRIBER_PLANS', 'by_subscriber_policy');
  protect('CDRS', 'by_subscriber_policy');
  protect('ALLOWANCE_USAGE', 'by_subscriber_policy');
  protect('USAGE_ALERTS', 'by_subscriber_policy');
  protect('INVOICE_LINES', 'by_invoice_policy');
  protect('PAYMENT_ALLOCATIONS', 'by_invoice_policy');
  protect('DUNNING_ACTIONS', 'by_invoice_policy');
end;
/
