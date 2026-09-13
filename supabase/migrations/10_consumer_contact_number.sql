-- =====================================================================
-- BillAlert — consumer self-service SMS number.
--
-- A consumer may change exactly one household field: contact_number. The
-- function derives the household from the signed-in profile and accepts no
-- consumer id, area id, status, name, or account number from the client.
--
-- The existing trg_consumers_normalize_contact trigger remains the only
-- owner of Philippine mobile normalization. The function writes the raw text
-- and returns the E.164 value stored after that trigger runs.
--
-- Run after 01-09. Safe to run more than once.
-- =====================================================================

-- One SMS destination belongs to one household. This also closes the race
-- between two consumers trying to claim the same number at the same time.
create unique index if not exists uq_consumers_contact_number
  on consumers (contact_number)
  where contact_number is not null;

create or replace function fn_update_own_contact_number(
  p_contact_number text
) returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_saved text;
begin
  if app.current_user_id() is null or app.current_role() <> 'consumer' then
    raise exception using
      errcode = '42501',
      message = 'Only a signed-in consumer may change a household SMS number';
  end if;

  if nullif(trim(coalesce(p_contact_number, '')), '') is null then
    raise exception 'Enter the mobile number that should receive SMS alerts';
  end if;

  -- Raw text on purpose. trg_consumers_normalize_contact normalizes it before
  -- the CHECK and unique index validate the stored value.
  update consumers
     set contact_number = p_contact_number
   where profile_id = app.current_user_id()
   returning contact_number into v_saved;

  if not found then
    raise no_data_found;
  end if;

  return v_saved;
exception
  when check_violation then
    raise exception
      'Enter a Philippine mobile number such as 0917 555 0142';
  when unique_violation then
    raise exception using
      errcode = '23505',
      message = 'That mobile number is already used by another household';
end $$;

comment on function fn_update_own_contact_number(text) is
  'Consumer self-service: updates only the caller household contact_number '
  'and returns the normalized E.164 value stored by the existing trigger.';

revoke all on function fn_update_own_contact_number(text)
  from public, anon;
grant execute on function fn_update_own_contact_number(text)
  to authenticated;
