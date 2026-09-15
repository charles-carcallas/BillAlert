-- Regression test for 12_household_logins.sql: who may be given a household
-- sign-in, and with what username.
--
-- Unlike the other suites, this one is meaningful in the Supabase SQL
-- editor. fn_check_household_login is SECURITY DEFINER and takes the caller
-- as a parameter, so row-level security plays no part in what it decides.
--
-- It needs two live accounts — mario.ombajin (Area President) and
-- ledesman.dormal (Meter Reader) — and virgilio.busalanan's household, which
-- has a sign-in. The households without one are created here and removed by
-- the rollback, so the result does not depend on who has been given a
-- sign-in since.
--
-- Success is the single row at the end. The first failure raises and stops.

begin;

create function pg_temp.expect_refused(
  p_case     text,
  p_admin    uuid,
  p_consumer uuid,
  p_username text,
  p_expected text
) returns void
language plpgsql as $$
declare v_message text;
begin
  begin
    perform fn_check_household_login(p_admin, p_consumer, p_username);
  exception when raise_exception then
    get stacked diagnostics v_message = message_text;
    if v_message not like (p_expected || '%') then
      raise exception 'FAIL: % - refused for the wrong reason: %', p_case, v_message;
    end if;
    return;
  end;
  raise exception 'FAIL: % - it was allowed', p_case;
end $$;

do $$
declare
  v_admin      uuid := (select id from profiles where username = 'mario.ombajin');
  v_reader     uuid := (select id from profiles where username = 'ledesman.dormal');
  v_area       uuid;
  v_other_area uuid;
  v_with_login uuid;
  v_candidate  uuid;
  v_elsewhere  uuid;
  v_names      record;
begin
  v_area := (select area_id from profiles where id = v_admin);
  v_other_area := (select id from areas where id <> v_area order by code limit 1);
  v_with_login := (
    select c.id from consumers c
      join profiles p on p.id = c.profile_id
     where p.username = 'virgilio.busalanan'
  );

  if v_admin is null or v_reader is null or v_with_login is null
     or v_other_area is null then
    raise exception 'SETUP: an account, household or second area this test needs is missing';
  end if;

  insert into consumers (consumer_no, first_name, last_name, area_id)
  values ('TEST-LOGIN-0001', 'Testa', 'Household', v_area)
  returning id into v_candidate;

  insert into consumers (consumer_no, first_name, last_name, area_id)
  values ('TEST-LOGIN-0002', 'Other', 'Area', v_other_area)
  returning id into v_elsewhere;

  perform pg_temp.expect_refused(
    'a Meter Reader cannot give a sign-in',
    v_reader, v_candidate, 'testa.household',
    'Only an active Area President');

  perform pg_temp.expect_refused(
    'a household that does not exist',
    v_admin, gen_random_uuid(), 'testa.household',
    'That household was not found');

  perform pg_temp.expect_refused(
    'a household in another service area',
    v_admin, v_elsewhere, 'other.area',
    'That household is not in your service area');

  perform pg_temp.expect_refused(
    'a household that already has a sign-in',
    v_admin, v_with_login, 'second.login',
    'This household already has a sign-in');

  perform pg_temp.expect_refused(
    'a username that does not start with a letter',
    v_admin, v_candidate, '2026household',
    'Use a username');

  perform pg_temp.expect_refused(
    'a username someone already has',
    v_admin, v_candidate, 'ledesman.dormal',
    'Username ledesman.dormal is already taken');

  update consumers set account_status = 'inactive' where id = v_candidate;
  perform pg_temp.expect_refused(
    'an inactive household',
    v_admin, v_candidate, 'testa.household',
    'That household is not active');
  update consumers set account_status = 'active' where id = v_candidate;

  -- And the one that should pass, returning the name from the record.
  select * into v_names
    from fn_check_household_login(v_admin, v_candidate, ' Testa.Household ');
  if v_names.household_first_name <> 'Testa'
     or v_names.household_no <> 'TEST-LOGIN-0001' then
    raise exception 'FAIL: an allowed check returned %', row_to_json(v_names);
  end if;
end $$;

rollback;

select 'PASS: all household sign-in rules held' as result;
