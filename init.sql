do $do$
declare
  name text;
  gender text;
begin

for name in values ('firstname'), ('middlename'), ('lastname') loop
  execute format(
  $macro$
  
  drop table if exists %1$s_gender;

  create table %1$s_gender as
    select json_array_elements_text(content #> array['gender', '%1$s', priority, gender]) as suffix, male
    from gender_content
      , ( values ('exceptions'), ('suffixes') ) p (priority)
      , ( values ('androgynous', null), ('female', false), ('male', true) ) g (gender, male)
  union all
    select '', null
  ;

  analyze %1$s_gender;

  create or replace function %1$s_gender(%1$s text) returns boolean as $fn$
    select male
    from %1$s_gender
    where lower($1) like '%%'||suffix
    order by char_length(suffix) desc
    limit 1
  $fn$ language sql stable strict;
  
  create or replace function %1$s(%1$s text, cas int, gender boolean) returns text as $fn$
    select case gender
        when true  then %1$s_male(%1$s, cas)
        when false then %1$s_female(%1$s, cas)
                   else %1$s_androgynous(%1$s, cas)
      end;
  $fn$ language sql stable;

  create or replace function %1$s(%1$s text, cas int) returns text as $fn$
    select %1$s(%1$s, cas, %1$s_gender(%1$s));
  $fn$ language sql stable;

  $macro$, name);

  for gender in values ('androgynous'), ('female'), ('male') loop
    execute format(
    $macro$

    drop table if exists %1$s_%2$s;

    create table %1$s_%2$s as
      select json_array_elements_text(rule->'test') as suffix
           , (select array_agg(ltrim(m, '.')) from json_array_elements_text(rule->'mods') x (m)) as mods
      from rule_content
        , ( values ('exceptions'), ('suffixes') ) p (priority)
        , json_array_elements(content #> array['%1$s', priority]) t (rule)
      where rule->>'gender' = '%2$s'
    union all
      select '', array['', '', '', '', '']
    ;

    analyze %1$s_%2$s;
    
    create or replace function %1$s_%2$s(%1$s text, cas int) returns text as $fn$
      select mods($1, case cas when 0 then '' else mods[cas] end)
      from %1$s_%2$s
      where lower($1) like '%%'||suffix
      order by char_length(suffix) desc
      limit 1
    $fn$ language sql stable strict;
    
    $macro$, name, gender);
  end loop;

end loop;

for gender in values ('androgynous'), ('female'), ('male') loop
  execute format(
  $macro$
  
  create or replace function fullname_%1$s(firstname text, middlename text, lastname text, cas int) returns record as $fn$
    select firstname_%1$s(firstname, cas), middlename_%1$s(middlename, cas), lastname_%1$s(lastname, cas)
  $fn$ language sql stable;
  
  $macro$, gender);
end loop;

end;
$do$;

create or replace function fullname_gender(firstname text, middlename text, lastname text) returns boolean as $fn$
  select coalesce(middlename_gender(middlename), lastname_gender(lastname), firstname_gender(firstname))
$fn$ language sql stable;

create or replace function fullname(firstname text, middlename text, lastname text, cas int, gender boolean) returns record as $fn$
  select case gender
      when true  then fullname_male(firstname, middlename, lastname, cas)
      when false then fullname_female(firstname, middlename, lastname, cas)
                 else fullname_androgynous(firstname, middlename, lastname, cas)
    end;
$fn$ language sql stable;

create or replace function fullname(firstname text, middlename text, lastname text, cas int) returns record as $fn$
  select fullname(firstname, middlename, lastname, cas, fullname_gender(firstname, middlename, lastname));
$fn$ language sql stable;

create or replace function mods(name text, mods text) returns text as $fn$
  select substring( name from 1 for char_length(name) - position(ltrim(mods, '-') in mods) + 1 ) || ltrim(mods, '-');
$fn$ language sql immutable strict
