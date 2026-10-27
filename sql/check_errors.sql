-- Stops the install if anything in the schema failed to compile. SQL*Plus
-- only warns about a package with errors, so this asks the dictionary.
set feedback off
column type format a12
column name format a30
column text format a90 word_wrapped
select type, name, line, position, text
  from user_errors
 where attribute = 'ERROR'
 order by name, type, sequence;

declare
  l_errors pls_integer;
begin
  select count(*) into l_errors from user_errors where attribute = 'ERROR';
  if l_errors > 0 then
    raise_application_error(-20999, l_errors || ' compile errors, listed above');
  end if;
end;
/
