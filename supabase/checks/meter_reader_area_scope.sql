-- =====================================================================
-- BillAlert — checks/meter_reader_area_scope.sql
--
-- Proves, against the live database, that a Meter Reader can see and
-- record readings only in their own service area (MTR-02, MTR-11, FR-31).
--
-- It signs in AS a real meter reader for the length of one transaction,
-- tries to look at and write to households outside that area, and ROLLS
-- EVERYTHING BACK. Nothing is saved. Run the whole file at once in the
-- Supabase SQL editor and read the single result table at the end.
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 0. Pick the reader, and (while still unrestricted) one active household
--    in their area and one outside it to aim at.
-- ---------------------------------------------------------------------
select set_config('check.reader', p.id::text, true),
       set_config('check.reader_area', p.area_id::text, true)
  from profiles p
 where p.role = 'meter_reader'
 order by p.created_at
 limit 1;

select set_config(
  'check.other_consumer',
  coalesce((select c.id::text from consumers c
             where c.area_id <> current_setting('check.reader_area')::uuid
               and c.account_status = 'active'
             limit 1), ''),
  true);

select set_config(
  'check.total_consumers', (select count(*)::text from consumers), true);

-- ---------------------------------------------------------------------
-- 1. Become that meter reader, exactly as the app's API calls do.
-- ---------------------------------------------------------------------
select set_config('request.jwt.claims',
       json_build_object('sub', current_setting('check.reader'),
                         'role', 'authenticated')::text, true),
       set_config('request.jwt.claim.sub', current_setting('check.reader'), true);
set local role authenticated;

-- ---------------------------------------------------------------------
-- 2. Try to step outside the area. Each attempt records what happened.
-- ---------------------------------------------------------------------
do $$
declare
  other uuid := nullif(current_setting('check.other_consumer'), '')::uuid;
begin
  if other is null then
    perform set_config('check.rpc', 'SKIPPED - no active household outside '
      || 'this reader''s area exists to test with', true);
    perform set_config('check.insert', 'SKIPPED - same reason', true);
    return;
  end if;

  begin
    perform fn_record_meter_reading(other, 999999, now(), gen_random_uuid());
    perform set_config('check.rpc', 'FAIL - reading ACCEPTED for another area', true);
  exception when others then
    perform set_config('check.rpc', 'PASS - refused: ' || sqlerrm, true);
  end;

  begin
    insert into meter_readings (consumer_id, billing_cycle_id, previous_reading,
                                current_reading, reading_date, client_uuid)
    select other, bc.id, 0, 999999, current_date, gen_random_uuid()
      from billing_cycles bc order by bc.period_start desc limit 1;
    perform set_config('check.insert', 'FAIL - direct insert ACCEPTED for another area', true);
  exception when others then
    perform set_config('check.insert', 'PASS - refused: ' || sqlerrm, true);
  end;
end $$;

-- ---------------------------------------------------------------------
-- 3. The result. Every row should say PASS (or 0 outside the area).
-- ---------------------------------------------------------------------
select 'signed in as' as check_item,
       app.current_role()::text || ' in area ' || app.current_area()::text as result
union all
select 'households visible outside own area',
       (select count(*) from consumers where area_id <> app.current_area())::text
       || '   (in own area: '
       || (select count(*) from consumers where area_id = app.current_area())::text
       || ' of ' || current_setting('check.total_consumers') || ' total)'
union all
select 'readings visible outside own area',
       (select count(*) from meter_readings mr
          join consumers c on c.id = mr.consumer_id
         where c.area_id <> app.current_area())::text
union all
select 'bills visible outside own area',
       (select count(*) from bills b join consumers c on c.id = b.consumer_id
         where c.area_id <> app.current_area())::text
union all
select 'payments visible outside own area',
       (select count(*) from payments p join consumers c on c.id = p.consumer_id
         where c.area_id <> app.current_area())::text
union all
select 'record reading for another area (app route)', current_setting('check.rpc')
union all
select 'insert reading for another area (direct API)', current_setting('check.insert');

rollback;
