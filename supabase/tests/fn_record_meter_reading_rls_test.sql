-- =====================================================================
-- Regression test — fn_record_meter_reading under Row-Level Security
--
-- WHY THIS EXISTS
--   fn_record_meter_reading once held `select ... for update` on the
--   consumer lookup. Under RLS, `for update` also checks the UPDATE
--   policy's USING clause, because locking a row requires permission to
--   update it — and `consumers_admin_update` is admin-only. So the
--   function failed for the Meter Reader, the one role allowed to call
--   it, with 'Consumer ... not found or not visible to you' for a
--   household the reader could select perfectly well a moment earlier.
--
-- WHY THERE ARE TWO HALVES
--   The negative half is the control, and it is the point of the test.
--   The bug could have been "fixed" by making the function SECURITY
--   DEFINER, which would have made the positive half pass while quietly
--   letting a reader record a reading in somebody else's service area.
--   A test with only the positive half would have approved that.
--
-- IDENTIFIERS
--   Households are looked up by consumer_no, never by a hardcoded UUID.
--   The fixture UUIDs in 05_seed.sql exist only on a local Postgres; on
--   Supabase the same households have random ids, because the fixture
--   profiles could not be inserted (profiles.id references auth.users)
--   and the rows were created by hand instead. consumer_no is the one
--   identifier that is the same in both places.
--
-- HOW TO RUN
--   Local Postgres, 01-05 applied in full including the fixture section
--   and the `test_app` role:
--
--     psql -d billalert -f supabase/tests/fn_record_meter_reading_rls_test.sql
--
--   To run it against Supabase instead, change the `set local role` line
--   below to `authenticated` — `test_app` is a local-only role. Do NOT
--   run it as the owner: the owner bypasses every policy, so all four
--   assertions would pass without proving anything.
--
--   The whole file runs in one transaction and rolls back, so it leaves
--   no readings or bills behind.
-- =====================================================================

begin;

-- Resolved BEFORE the role switch, while the current role can still see
-- every row, and carried across the switch in transaction-local GUCs.
select set_config('billalert.reader_id',
       (select id::text from profiles where username = 'ledesman.dormal'), true);
select set_config('billalert.own_area_consumer',
       (select id::text from consumers where consumer_no = '2020-0791-TUB'), true);
select set_config('billalert.own_area_consumer_2',
       (select id::text from consumers where consumer_no = '2018-0442-TUB'), true);
select set_config('billalert.other_area_consumer',
       (select id::text from consumers where consumer_no = '2022-0001-TUB'), true);

do $$
begin
  if current_setting('billalert.other_area_consumer', true) is null
     or current_setting('billalert.other_area_consumer', true) = '' then
    raise exception
      'SETUP: consumer 2022-0001-TUB (Area 4) is missing. The negative half of '
      'this test cannot run without a household outside the reader''s area, and '
      'without it the area boundary would pass vacuously.';
  end if;
end $$;

-- Ledesman Dormal, Meter Reader, Area 3. An ordinary role, so the policies
-- actually apply — the owner would bypass them.
set local role test_app;
select set_config('app.current_user_id', current_setting('billalert.reader_id'), true);


-- ---------------------------------------------------------------------
-- 1. POSITIVE — a reader records a reading in their OWN area.
--    The bill it creates must be born unpriced (FR-21a).
-- ---------------------------------------------------------------------
do $$
declare
  v_bill_id uuid;
  v_bill    bills%rowtype;
begin
  v_bill_id := fn_record_meter_reading(
    current_setting('billalert.own_area_consumer')::uuid, 4668);

  if v_bill_id is null then
    raise exception 'FAIL: the reader got no bill id back for their own area';
  end if;

  select * into v_bill from bills where id = v_bill_id;
  if not found then
    raise exception 'FAIL: bill % was returned but cannot be read back', v_bill_id;
  end if;

  -- BillAlert never computes an amount. The bill exists, priced by nobody.
  if v_bill.total_amount is not null then
    raise exception 'FAIL: a new bill arrived already priced at %', v_bill.total_amount;
  end if;
  if v_bill.due_date is not null then
    raise exception 'FAIL: a new bill arrived with a due date of %', v_bill.due_date;
  end if;
  if v_bill.status <> 'unpriced' then
    raise exception 'FAIL: a new bill has status % rather than unpriced', v_bill.status;
  end if;

  raise notice 'PASS: own area accepted, bill % is unpriced with % kWh',
    v_bill_id, v_bill.consumption;
end $$;


-- ---------------------------------------------------------------------
-- 2. NEGATIVE — the same reader must NOT be able to record a reading
--    for a consumer in another service area. This is the control.
-- ---------------------------------------------------------------------
do $$
declare
  v_bill_id uuid;
  v_allowed boolean := false;
begin
  begin
    v_bill_id := fn_record_meter_reading(
      current_setting('billalert.other_area_consumer')::uuid, 100);
    -- Reaching this line at all is the failure.
    v_allowed := true;
  exception
    when others then
      raise notice 'refused, as it should be (% - %)', sqlstate, sqlerrm;
  end;

  -- Raised outside the inner block so the assertion cannot be swallowed
  -- by the very handler that is meant to catch the refusal.
  if v_allowed then
    raise exception
      'FAIL: an Area 3 Meter Reader recorded a reading for an Area 4 consumer '
      '(bill %). The area boundary is not holding — check whether the function '
      'was made SECURITY DEFINER.', v_bill_id;
  end if;

  raise notice 'PASS: another area refused';
end $$;


-- ---------------------------------------------------------------------
-- 3. FR-23 — a second reading in the same cycle is refused.
-- ---------------------------------------------------------------------
do $$
declare
  v_allowed boolean := false;
begin
  begin
    perform fn_record_meter_reading(
      current_setting('billalert.own_area_consumer')::uuid, 4700);
    v_allowed := true;
  exception
    when unique_violation then
      raise notice 'refused a duplicate for the cycle: %', sqlerrm;
    when others then
      raise exception 'FAIL: expected a unique_violation, got % - %', sqlstate, sqlerrm;
  end;

  if v_allowed then
    raise exception 'FAIL: the same consumer was read twice in one cycle';
  end if;

  raise notice 'PASS: a second reading in the same cycle is refused';
end $$;


-- ---------------------------------------------------------------------
-- 4. MTR-12 — replaying a clientUuid returns the original bill and
--    creates no second one.
-- ---------------------------------------------------------------------
do $$
declare
  v_uuid   uuid := '99999999-0000-0000-0000-0000000000ff';
  v_first  uuid;
  v_second uuid;
  v_count  int;
begin
  v_first := fn_record_meter_reading(
    current_setting('billalert.own_area_consumer_2')::uuid, 3943, now(), v_uuid);
  v_second := fn_record_meter_reading(
    current_setting('billalert.own_area_consumer_2')::uuid, 3943, now(), v_uuid);

  if v_first is distinct from v_second then
    raise exception 'FAIL: a replayed clientUuid produced a different bill (% then %)',
      v_first, v_second;
  end if;

  select count(*) into v_count from meter_readings where client_uuid = v_uuid;
  if v_count <> 1 then
    raise exception 'FAIL: % readings share one clientUuid', v_count;
  end if;

  raise notice 'PASS: the replay returned bill % and created no duplicate', v_first;
end $$;

rollback;
