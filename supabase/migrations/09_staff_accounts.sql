-- =====================================================================
-- BillAlert — 09_staff_accounts.sql
-- FR-31 / ADM (Figma 70:1436): the Area President creates a meter reader
-- or cashier account for their OWN service area.
--
-- WHY THIS IS A DATABASE FUNCTION AND NOT APP CODE
--
-- Creating a sign-in account means writing to `auth.users`, and the
-- Supabase client can only do that with the SERVICE-ROLE key — a
-- credential that bypasses every RLS policy in the project. Putting it in
-- the APK would hand full read/write over every household, bill and
-- payment to anyone willing to unzip the file. That is not a risk to
-- manage; it is a key that must never leave a server.
--
-- So the privilege stays here. This function is SECURITY DEFINER, which
-- means it runs as its owner (postgres) no matter who calls it. The app
-- calls it over PostgREST with the ordinary anon key and the Admin's own
-- JWT, exactly like the other five RPCs. Nothing privileged ships in the
-- app.
--
-- SECURITY DEFINER is only safe when the function decides for itself what
-- the caller may do, so it does:
--
--   * app.is_admin() — a meter reader calling this gets refused.
--   * The area is taken from app.current_area(), never from a parameter.
--     An Area President cannot create staff in somebody else's area even
--     by editing the request.
--   * The role is restricted to meter_reader or cashier. This cannot mint
--     another admin, and it cannot mint a consumer — MTR-04 provisions
--     those from the household record.
--   * search_path is pinned, so nothing can be hijacked by a shadowing
--     object in a caller-controlled schema.
--
-- NOTE: this is the SIXTH app-callable RPC. The other five were the whole
-- list on purpose. Adding one is a deliberate change, made because the
-- alternative was a screen that could not exist.
--
-- Run after 01-07. Safe to run more than once.
-- =====================================================================

create or replace function fn_create_staff_account(
  p_username       text,
  p_first_name     text,
  p_last_name      text,
  p_role           user_role,
  p_temp_password  text,
  p_position_title text default null,
  p_contact_number text default null
) returns uuid
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_uid      uuid := gen_random_uuid();
  v_username text := lower(trim(p_username));
  v_email    text;
  v_area     uuid;
  v_prefix   text;
  v_seq      integer;
  v_code     text;
begin
  -- ---- who may call this -------------------------------------------
  if not app.is_admin() then
    raise exception 'Only an Area President can create a staff account';
  end if;

  v_area := app.current_area();
  if v_area is null then
    raise exception 'No service area is attached to your account';
  end if;

  -- ---- what may be created -----------------------------------------
  if p_role not in ('meter_reader'::user_role, 'cashier'::user_role) then
    raise exception
      'A staff account is a meter reader or a cashier. Consumers are '
      'provisioned from the household record, and an Area President is '
      'appointed by the cooperative.';
  end if;

  if v_username !~ '^[a-z][a-z0-9._-]{2,49}$' then
    raise exception
      'A username is 3 to 50 characters, starts with a letter, and holds '
      'only letters, numbers, dot, underscore or hyphen';
  end if;

  if length(coalesce(p_temp_password, '')) < 8 then
    raise exception 'The temporary password must be at least 8 characters';
  end if;

  if exists (select 1 from profiles where username = v_username) then
    raise exception 'Username % is already taken', v_username;
  end if;

  -- Must match AppConfig.loginEmailDomain. The app never builds this
  -- address itself except in AuthRepositoryImpl.emailForUsername.
  v_email := v_username || '@billalert.local';

  if exists (select 1 from auth.users u where u.email = v_email) then
    raise exception 'Username % is already taken', v_username;
  end if;

  -- ---- MTR-0007 / CSH-0003 -----------------------------------------
  v_prefix := case p_role
                when 'meter_reader'::user_role then 'MTR'
                else 'CSH'
              end;

  select coalesce(max((regexp_replace(user_code, '^[A-Z]+-', ''))::integer), 0) + 1
    into v_seq
    from profiles
   where user_code ~ ('^' || v_prefix || '-[0-9]+$');

  v_code := v_prefix || '-' || lpad(v_seq::text, 4, '0');

  -- ---- the sign-in account -----------------------------------------
  -- email_confirmed_at is set now: this account is vouched for by the
  -- Area President in person, and there is no mailbox behind
  -- @billalert.local to confirm from.
  --
  -- The token columns are '' and not null. GoTrue reads them as text and
  -- a null makes sign-in fail with an error that names none of this.
  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, created_at, updated_at,
    raw_app_meta_data, raw_user_meta_data,
    confirmation_token, recovery_token, email_change, email_change_token_new
  ) values (
    '00000000-0000-0000-0000-000000000000', v_uid,
    'authenticated', 'authenticated', v_email,
    crypt(p_temp_password, gen_salt('bf')),
    now(), now(), now(),
    '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb,
    '', '', '', ''
  );

  -- The identity row is what the dashboard lists under the account, and
  -- what newer GoTrue versions expect to find. Password sign-in works
  -- without it, so a schema that has no auth.identities — or a different
  -- shape of one — must not lose the whole account.
  begin
    insert into auth.identities (
      id, user_id, provider_id, identity_data, provider,
      last_sign_in_at, created_at, updated_at
    ) values (
      gen_random_uuid(), v_uid, v_uid::text,
      jsonb_build_object('sub', v_uid::text, 'email', v_email),
      'email', now(), now(), now()
    );
  exception when others then
    raise notice
      'auth.identities row not written (%). The account can still sign in.',
      sqlerrm;
  end;

  -- ---- the profile the app actually reads ---------------------------
  -- GEN-04: must_change_password locks the new member of staff to the
  -- change-password screen until they pick their own.
  insert into profiles (
    id, user_code, username, first_name, last_name, role,
    position_title, contact_number, area_id, account_status,
    must_change_password
  ) values (
    v_uid, v_code, v_username, trim(p_first_name), trim(p_last_name), p_role,
    nullif(trim(coalesce(p_position_title, '')), ''),
    nullif(trim(coalesce(p_contact_number, '')), ''),
    v_area, 'active', true
  );

  return v_uid;
end $$;

comment on function fn_create_staff_account is
  'FR-31: an Area President creates a meter reader or cashier for their own '
  'area. SECURITY DEFINER so the service-role key never ships in the client; '
  'the function checks app.is_admin() and takes the area from the caller.';

-- Callable by a signed-in user only. An anon caller would fail is_admin()
-- anyway, but there is no reason to let it reach the body.
revoke all on function fn_create_staff_account(
  text, text, text, user_role, text, text, text
) from public, anon;

grant execute on function fn_create_staff_account(
  text, text, text, user_role, text, text, text
) to authenticated;
