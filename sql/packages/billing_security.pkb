create or replace package body billing_security as

  procedure set_reseller(p_code varchar2) is
    l_id resellers.reseller_id%type;
  begin
    select reseller_id into l_id from resellers where code = p_code;
    dbms_session.set_context(ctx, 'RESELLER_ID', to_char(l_id));
  exception
    when no_data_found then
      raise_application_error(billing_errors.no_such_reseller, 'no reseller ' || p_code);
  end set_reseller;

  procedure clear_reseller is
  begin
    dbms_session.clear_context(ctx, attribute => 'RESELLER_ID');
  end clear_reseller;

  -- No reseller set: no predicate, so no filtering at all.
  function scoped return boolean is
  begin
    return sys_context(ctx, 'RESELLER_ID') is not null;
  end scoped;

  function customers_policy(p_schema varchar2, p_object varchar2) return varchar2 is
  begin
    if not scoped then
      return null;
    end if;
    return q'[reseller_id = to_number(sys_context('BILLRUN_CTX', 'RESELLER_ID'))]';
  end customers_policy;

  -- The subqueries go through customers' own policy as well, so each
  -- table is only as visible as the customers it belongs to.
  function by_customer_policy(p_schema varchar2, p_object varchar2) return varchar2 is
  begin
    if not scoped then
      return null;
    end if;
    return 'customer_id in (select customer_id from customers)';
  end by_customer_policy;

  function by_subscriber_policy(p_schema varchar2, p_object varchar2) return varchar2 is
  begin
    if not scoped then
      return null;
    end if;
    return 'subscriber_id in (select subscriber_id from subscribers)';
  end by_subscriber_policy;

  function by_invoice_policy(p_schema varchar2, p_object varchar2) return varchar2 is
  begin
    if not scoped then
      return null;
    end if;
    return 'invoice_id in (select invoice_id from invoices)';
  end by_invoice_policy;

end billing_security;
/
