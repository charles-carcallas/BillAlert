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
-- HOW TO RUN
--   Against a LOCAL Postgres with 01-05 applied in full, including the
--   fixture section and the `test_app` role. Not against Supabase: the
--   SQL editor runs as the table owner and bypasses every policy, so
--   every assertion here would pass without proving anything.
--
--     psql -d billalert -f supabase/tests/06_fn_record_meter_reading_rls_test.sql
--
--   The whole file runs in one transaction and rolls back, so it leaves
--   no readings or bills behind.
-- =====================================================================

begin;

-- Ledesman Dormal, Meter Reader, Area 3. Ordinary role, so the policies
-- actually apply — a superuser or the table owner would bypass them.
set local role test_app;
set local app.current_user_id = '33333333-0000-0000-0000-000000000002';


-- ---------------------------------------------------------------------
-- 1. POSITIVE — a reader records a reading in their OWN area.
--    The bill it creates must be born unpriced (FR-21a).
-- ---------------------------------------------------------------------
do $$
declare
  v_bill_id uuid;
  v_bill    bills%rowtype;
begin
  -- Bienvenido Sarigumba, 2020-0791-TUB, Area 3.
  v_bill_id := fn_record_meter_reading(
    '55555555-0000-0000-0000-000000000005'::uuid,
    4668
  );

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
  if v_bill.consumption <> 58 then
    raise exception 'FAIL: consumption is % rather than 58 kWh', v_bill.consumption;
  end if;

  raise notice 'PASS: own area accepted, bill % is unpriced with % kWh',
    v_bill_id, v_bill.consumption;
end $$;


-- ---------------------------------------------------------------------
-- 2. NEGATIVE — the same reader must NOT be able to record a reading
--    for a consumer in another service area.
--
--    Ben Aquino, 2022-0001-TUB, is in Area 4. The seed puts him there
--    for exactly this assertion.
-- ---------------------------------------------------------------------
do $$
declare
  v_bill_id uuid;
  v_allowed boolean := false;
begin
  begin
    v_bill_id := fn_record_meter_reading(
      '55555555-0000-0000-0000-000000000007'::uuid,
      100
    );
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
-- 3. FR-23 — a second reading in the same cycle is refused, and says so
--    in words the reader can act on.
-- ---------------------------------------------------------------------
do $$
declare
  v_allowed boolean := false;
begin
  begin
    perform fn_record_meter_reading(
      '55555555-0000-0000-0000-000000000005'::uuid,
      4700
    );
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
  -- Elena Bongcaras, Area 3, not yet read in this transaction.
  v_first := fn_record_meter_reading(
    '55555555-0000-0000-0000-000000000002'::uuid, 3943, now(), v_uuid);
  v_second := fn_record_meter_reading(
    '55555555-0000-0000-0000-000000000002'::uuid, 3943, now(), v_uuid);

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
