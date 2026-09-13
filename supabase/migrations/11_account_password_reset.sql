-- =====================================================================
-- BillAlert — 11_account_password_reset.sql
-- An Area President resets a forgotten password for an account in their
-- own service area.
--
-- Changing another person's password takes Supabase's Auth Admin API, and
-- that takes the service-role key. So, exactly like staff creation (09),
-- the work enters through an Edge Function — reset-account-password — which
-- holds the key on the server, and the RULES live here, in functions only
-- service_role may execute. The Flutter client can call neither.
--
-- Who may be reset:
--   * a Meter Reader or Cashier whose profile is in the caller's area
--   * a consumer login whose household is in the caller's area
-- Never: another Area President, the caller themselves (Change password
-- exists for that), an inactive account, or anyone in another area.
--
-- Run after 01-10. Safe to run more than once.
-- =====================================================================

create or replace function fn_authorize_password_reset(
  p_admin_id  uuid,
  p_target_id uuid
) returns table (
  target_first_name text,
  target_last_name  text,
  target_kind       text
)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_area   uuid;
  v_target profiles%rowtype;
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
    raise exception 'Only an active Area President can reset a password';
  end if;

  if p_target_id = p_admin_id then
    raise exception
      'Use Change password on your Profile to change your own password';
  end if;

  select * into v_target from profiles where id = p_target_id;

  if not found then
    raise exception 'That account was not found';
  end if;

  if v_target.account_status <> 'active' then
    raise exception
      'That account is not active, so its password cannot be reset';
  end if;

  if v_target.role in ('meter_reader'::user_role, 'cashier'::user_role) then
    if v_target.area_id is distinct from v_area then
      raise exception 'That account is not in your service area';
    end if;
  elsif v_target.role = 'consumer'::user_role then
    -- A consumer's login profile carries no area. Their household does.
    if not exists (
      select 1
        from consumers c
       where c.profile_id = p_target_id
         and c.area_id = v_area
    ) then
      raise exception 'That account is not in your service area';
    end if;
  else
    -- An Area President's password is reset by the cooperative, never by a
    -- peer: otherwise one Area President could take over another's account.
    raise exception
      'An Area President''s password cannot be reset from this screen';
  end if;

  return query
    select v_target.first_name, v_target.last_name, v_target.role::text;
end $$;

comment on function fn_authorize_password_reset is
  'Checks that an Area President may reset this account''s password: own '
  'area, staff or household login, never an Area President or themselves. '
  'Writes nothing. Server-only.';


create or replace function fn_require_password_change(
  p_admin_id  uuid,
  p_target_id uuid
) returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  -- Checked again rather than trusted from an earlier call. The Edge Function
  -- is the only caller today; the rule still belongs to the database.
  perform 1 from fn_authorize_password_reset(p_admin_id, p_target_id);

  -- GEN-04: the temporary password must be replaced at the next sign-in, so
  -- the Area President never knows the password that is kept.
  update profiles
     set must_change_password = true,
         updated_at = now()
   where id = p_target_id;
end $$;

comment on function fn_require_password_change is
  'After authorising a reset, requires the account to choose a new password '
  'at its next sign-in. Called before the password itself is changed. '
  'Server-only.';


revoke all on function fn_authorize_password_reset(uuid, uuid)
  from public, anon, authenticated;
grant execute on function fn_authorize_password_reset(uuid, uuid)
  to service_role;

revoke all on function fn_require_password_change(uuid, uuid)
  from public, anon, authenticated;
grant execute on function fn_require_password_change(uuid, uuid)
  to service_role;
