-- =====================================================================
-- BillAlert — 12_household_logins.sql
-- MTR-04: an Area President gives a household in their own service area
-- a sign-in, from the household record.
--
-- New Consumer creates only the `consumers` row. Without a sign-in the
-- household is billed and paid for, but cannot open the app to see its own
-- bill, receipts or notifications.
--
-- Creating a sign-in writes to `auth.users`, which takes the service-role
-- key. So, exactly like staff creation (09) and password resets (11), the
-- work enters through an Edge Function — create-household-login — which
-- holds the key on the server, and the RULES live here, in functions only
-- service_role may execute. The Flutter client can call neither.
--
-- Who may be given a sign-in:
--   * an active household in the caller's own service area
--   * that does not already have one
-- The username must be free and well formed. The household's name comes
-- from its own record, never from the request.
--
-- Run after 01-11. Safe to run more than once.
-- =====================================================================

-- Checks every rule and writes nothing. The Edge Function calls this BEFORE
-- it creates the auth user, so an ordinary refusal — a household that
-- already has a sign-in, a username that is taken — never leaves an auth
-- user behind to clean up.
create or replace function fn_check_household_login(
  p_admin_id     uuid,
  p_consumer_id  uuid,
  p_username     text
) returns table (
  household_first_name text,
  household_last_name  text,
  household_no         text
)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_area      uuid;
  v_username  text := lower(trim(coalesce(p_username, '')));
  v_household consumers%rowtype;
begin
  -- The Edge Function takes this id from the verified JWT. It is looked up
  -- again here so the database, not the function, is where the rule lives.
  select area_id
    into v_area
    from profiles
   where id = p_admin_id
     and role = 'admin'
     and account_status = 'active';

  if v_area is null then
    raise exception 'Only an active Area President can give a household a sign-in';
  end if;

  select * into v_household from consumers where id = p_consumer_id;

  if not found then
    raise exception 'That household was not found';
  end if;

  if v_household.area_id is distinct from v_area then
    raise exception 'That household is not in your service area';
  end if;

  if v_household.account_status <> 'active' then
    raise exception 'That household is not active, so it cannot be given a sign-in';
  end if;

  if v_household.profile_id is not null then
    raise exception
      'This household already has a sign-in. Use Reset a forgotten password '
      'if they cannot get in';
  end if;

  if v_username !~ '^[a-z][a-z0-9._-]{2,49}$' then
    raise exception
      'Use a username of 3 to 50 characters that starts with a letter and '
      'uses only letters, numbers, dot, underscore or hyphen';
  end if;

  if exists (select 1 from profiles where username = v_username) then
    raise exception 'Username % is already taken', v_username;
  end if;

  return query
    select v_household.first_name, v_household.last_name, v_household.consumer_no;
end $$;

comment on function fn_check_household_login is
  'MTR-04: checks that an Area President may give this household a sign-in '
  'with this username. Writes nothing. Server-only.';


-- Called after the Edge Function has created the auth user. Creates the
-- consumer profile and links it to the household, in one transaction.
create or replace function fn_create_household_login(
  p_admin_id     uuid,
  p_user_id      uuid,
  p_consumer_id  uuid,
  p_username     text
) returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_username  text := lower(trim(coalesce(p_username, '')));
  v_household consumers%rowtype;
  v_seq       integer;
  v_code      text;
begin
  -- Held until commit, so two taps on Create — or two Area Presidents'
  -- phones — cannot both link a sign-in to the same household.
  perform 1 from consumers where id = p_consumer_id for update;

  -- Checked again rather than trusted from the earlier call: the household
  -- may have been given a sign-in in between.
  perform 1 from fn_check_household_login(p_admin_id, p_consumer_id, v_username);

  select * into v_household from consumers where id = p_consumer_id;

  -- CON-0008. Serialised so two requests cannot receive the same number.
  perform pg_advisory_xact_lock(hashtext('billalert.staff.CON'));

  select coalesce(
           max((regexp_replace(user_code, '^[A-Z]+-', ''))::integer),
           0
         ) + 1
    into v_seq
    from profiles
   where user_code ~ '^CON-[0-9]+$';

  v_code := 'CON-' || lpad(v_seq::text, 4, '0');

  -- A consumer's profile carries no area and no mobile number: both live on
  -- the household, which is where RLS and the SMS number update read them.
  -- GEN-04: the temporary password must be replaced at first sign-in.
  insert into profiles (
    id, user_code, username, first_name, last_name, role,
    area_id, account_status, must_change_password
  ) values (
    p_user_id, v_code, v_username, v_household.first_name,
    v_household.last_name, 'consumer', null, 'active', true
  );

  update consumers
     set profile_id = p_user_id,
         updated_at = now()
   where id = p_consumer_id;

  return v_code;
exception
  when unique_violation then
    raise exception
      'That username or household sign-in is already in use. Refresh and try again.';
end $$;

comment on function fn_create_household_login is
  'MTR-04 server helper: after the Edge Function creates the auth user, '
  'creates the consumer profile and links it to the household. Server-only.';


revoke all on function fn_check_household_login(uuid, uuid, text)
  from public, anon, authenticated;
grant execute on function fn_check_household_login(uuid, uuid, text)
  to service_role;

revoke all on function fn_create_household_login(uuid, uuid, uuid, text)
  from public, anon, authenticated;
grant execute on function fn_create_household_login(uuid, uuid, uuid, text)
  to service_role;
