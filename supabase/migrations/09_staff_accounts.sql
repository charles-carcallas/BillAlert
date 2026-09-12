-- =====================================================================
-- BillAlert — 09_staff_accounts.sql
-- FR-31: server-only profile creation for a newly provisioned staff user.
--
-- `auth.users` is owned by Supabase Auth and is never written directly.
-- The create-staff-account Edge Function uses the Auth Admin API, then calls
-- this helper with its server-side service role. The Flutter client cannot
-- execute this function.
--
-- Run after 01-08. Safe to run more than once.
-- =====================================================================

-- Remove the earlier client-callable prototype if it was ever deployed. It
-- inserted directly into auth.users, which Supabase does not support.
drop function if exists fn_create_staff_account(
  text, text, text, user_role, text, text, text
);

create or replace function fn_create_staff_profile(
  p_admin_id      uuid,
  p_user_id       uuid,
  p_username      text,
  p_first_name    text,
  p_last_name     text,
  p_role          user_role,
  p_contact_number text default null
) returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_area          uuid;
  v_username      text := lower(trim(p_username));
  v_prefix        text;
  v_seq           integer;
  v_code          text;
  v_role_label    text;
  v_existing_name text;
begin
  -- The Edge Function gets this id from the verified user JWT. Looking the
  -- profile up again here makes the database enforce the same boundary.
  select area_id
    into v_area
    from profiles
   where id = p_admin_id
     and role = 'admin'
     and account_status = 'active';

  if v_area is null then
    raise exception 'Only an active Area President can create a staff account';
  end if;

  if p_role is null
     or p_role not in ('meter_reader'::user_role, 'cashier'::user_role) then
    raise exception 'A staff account must be a Meter Reader or Cashier';
  end if;

  if v_username !~ '^[a-z][a-z0-9._-]{2,49}$' then
    raise exception
      'A username is 3 to 50 characters, starts with a letter, and holds '
      'only letters, numbers, dot, underscore or hyphen';
  end if;

  if nullif(trim(coalesce(p_first_name, '')), '') is null then
    raise exception 'Enter the staff member''s first name';
  end if;

  if nullif(trim(coalesce(p_last_name, '')), '') is null then
    raise exception 'Enter the staff member''s last name';
  end if;

  if exists (select 1 from profiles where username = v_username) then
    raise exception 'Username % is already taken', v_username;
  end if;

  v_role_label := case p_role
                    when 'meter_reader'::user_role then 'Meter Reader'
                    else 'Cashier'
                  end;

  select first_name || ' ' || last_name
    into v_existing_name
    from profiles
   where area_id = v_area
     and role = p_role
     and account_status = 'active'
   limit 1;

  if v_existing_name is not null then
    raise exception
      'Assignment blocked — % is already the active % for this service area',
      v_existing_name, v_role_label;
  end if;

  v_prefix := case p_role
                when 'meter_reader'::user_role then 'MTR'
                else 'CSH'
              end;

  -- Serialises code allocation so two Area Presidents cannot receive the
  -- same MTR/CSH number when requests arrive together.
  perform pg_advisory_xact_lock(hashtext('billalert.staff.' || v_prefix));

  select coalesce(
           max((regexp_replace(user_code, '^[A-Z]+-', ''))::integer),
           0
         ) + 1
    into v_seq
    from profiles
   where user_code ~ ('^' || v_prefix || '-[0-9]+$');

  v_code := v_prefix || '-' || lpad(v_seq::text, 4, '0');

  insert into profiles (
    id, user_code, username, first_name, last_name, role,
    contact_number, area_id, account_status, must_change_password
  ) values (
    p_user_id, v_code, v_username, trim(p_first_name), trim(p_last_name),
    p_role, nullif(trim(coalesce(p_contact_number, '')), ''), v_area,
    'active', true
  );

  return v_code;
exception
  when unique_violation then
    raise exception
      'That username or staff assignment is already in use. Refresh and try again.';
end $$;

comment on function fn_create_staff_profile is
  'FR-31 server helper: creates an area-scoped Meter Reader or Cashier '
  'profile after the Edge Function provisions the auth user.';

revoke all on function fn_create_staff_profile(
  uuid, uuid, text, text, text, user_role, text
) from public, anon, authenticated;

grant execute on function fn_create_staff_profile(
  uuid, uuid, text, text, text, user_role, text
) to service_role;
