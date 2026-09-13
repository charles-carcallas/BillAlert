-- Regression test for 10_consumer_contact_number.sql.
-- Run after migrations 01-10. It rolls back every change.

begin;

select set_config(
  'billalert.consumer_id',
  (select id::text from profiles where username = 'virgilio.busalanan'),
  true
);
select set_config(
  'billalert.admin_id',
  (select id::text from profiles where username = 'mario.ombajin'),
  true
);

set local role test_app;
select set_config(
  'app.current_user_id',
  current_setting('billalert.consumer_id'),
  true
);

do $$
declare
  v_saved text;
  v_other_count integer;
begin
  v_saved := fn_update_own_contact_number('0917 555 0999');
  if v_saved <> '+639175550999' then
    raise exception 'FAIL: normalized result was %', v_saved;
  end if;

  select count(*) into v_other_count
    from consumers
   where profile_id <> app.current_user_id()
     and contact_number = '+639175550999';
  if v_other_count <> 0 then
    raise exception 'FAIL: another household was changed';
  end if;

  raise notice 'PASS: consumer changed only their own SMS number';
end $$;

do $$
declare allowed boolean := false;
begin
  begin
    perform fn_update_own_contact_number('not a phone');
    allowed := true;
  exception when others then
    raise notice 'invalid number refused (% - %)', sqlstate, sqlerrm;
  end;
  if allowed then
    raise exception 'FAIL: an invalid mobile number was stored';
  end if;
  raise notice 'PASS: invalid mobile number refused';
end $$;

select set_config(
  'app.current_user_id',
  current_setting('billalert.admin_id'),
  true
);

do $$
declare allowed boolean := false;
begin
  begin
    perform fn_update_own_contact_number('0917 555 0888');
    allowed := true;
  exception when insufficient_privilege then
    raise notice 'staff caller refused';
  end;
  if allowed then
    raise exception 'FAIL: a staff account changed a consumer SMS number';
  end if;
  raise notice 'PASS: staff caller refused';
end $$;

rollback;
