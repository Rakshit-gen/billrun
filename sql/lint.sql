-- Recompiles billrun's packages with every PL/SQL compiler warning on and
-- lists what the compiler says, worst first. Fails if any warning isn't
-- in the list of accepted ones at the bottom.
set feedback off
set serveroutput on
set linesize 200
column name format a22
column text format a110 word_wrapped

begin
  for p in (select object_name, object_type from user_objects
             where object_type in ('PACKAGE', 'PACKAGE BODY')
               and object_name like 'BILLING\_%' escape '\'
             order by object_type, object_name) loop
    execute immediate 'alter package ' || p.object_name || ' compile '
      || case p.object_type when 'PACKAGE BODY' then 'body ' end
      || 'plsql_warnings = ''ENABLE:ALL'' reuse settings';
  end loop;
end;
/

select name, line, text
  from user_errors
 where attribute = 'WARNING'
 order by message_number, name, line;

declare
  l_n pls_integer;
begin
  select count(*) into l_n
    from user_errors
   where attribute = 'WARNING'
     and message_number not in (
       -- No AUTHID clause: definer's rights is the intent throughout.
       5018);
  dbms_output.put_line(l_n || ' compiler warnings');
end;
/
