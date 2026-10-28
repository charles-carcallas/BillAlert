-- USER-RUN PREVIEW: creates fresh TEST households for these existing logins.
-- No Auth users/passwords, bills, readings or coverage assignments are created.
-- This does not infer ownership of any of the existing unlinked households.
-- Review the result, then change ONLY the final ROLLBACK to COMMIT to save.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';

create temp table staff_household_setup_result (
  username text, consumer_no text, result text
) on commit drop;

do $$
declare
  admin_row public.profiles%rowtype;
  person public.profiles%rowtype;
  existing public.consumers%rowtype;
  target record;
  household_id uuid;
begin
  select * into admin_row from public.profiles
  where username = 'mario.ombajin' and role = 'admin'
    and account_status = 'active' and staff_enabled;
  if not found or admin_row.area_id is null then
    raise exception 'Mario must be the active Area President with a service area';
  end if;
  -- Same area lock used by account setup and staff assignment.
  perform 1 from public.areas where id = admin_row.area_id for update;

  for target in select * from (values
    ('qa02.reader.replacement', 'QA02-REPLACEMENT-HOME', 'meter_reader'),
    ('test.tset1',              'QA02-TSET1-HOME',       'meter_reader'),
    ('test.tset2',              'QA02-TSET2-HOME',       'cashier')
  ) as targets(username, consumer_no, expected_role)
  loop
    select * into person from public.profiles
    where username = target.username for update;
    if not found or person.account_status <> 'active'
      or person.area_id is distinct from admin_row.area_id
      or person.role::text <> target.expected_role then
      raise exception 'Account % is missing, inactive, in another area or has changed role', target.username;
    end if;

    select * into existing from public.consumers
    where profile_id = person.id for update;
    if found then
      if existing.consumer_no = target.consumer_no
        and existing.area_id = admin_row.area_id
        and existing.account_status = 'active' then
        insert into staff_household_setup_result
          values(target.username, target.consumer_no, 'Already linked; unchanged');
        continue;
      end if;
      raise exception '% already has household %. Nothing will be replaced', target.username, existing.consumer_no;
    end if;
    if exists(select 1 from public.consumers where consumer_no = target.consumer_no) then
      raise exception 'Consumer number % already exists. Review it before linking', target.consumer_no;
    end if;

    insert into public.consumers (
      consumer_no, profile_id, first_name, last_name, area_id,
      account_status, created_by, opening_reading
    ) values (
      target.consumer_no, person.id, person.first_name, person.last_name,
      admin_row.area_id, 'active', admin_row.id, 0
    ) returning id into household_id;

    insert into public.account_events (
      area_id, actor_id, target_id, action, reason, details
    ) values (
      admin_row.area_id, admin_row.id, person.id, 'staff_link',
      'User-requested fresh test household for existing test login',
      jsonb_build_object('consumer_id', household_id, 'test_household', true)
    );
    insert into staff_household_setup_result
      values(target.username, target.consumer_no, 'Created and linked');
  end loop;
end $$;

select username, consumer_no, result
from staff_household_setup_result order by username;

-- PREVIEW ONLY. Change to COMMIT only after approving these exact mappings.
rollback;
