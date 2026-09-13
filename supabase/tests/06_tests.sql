-- =====================================================================
-- BillAlert — 06_tests.sql
-- Data-model test suite: 56 cases, one per business rule.
--
-- Run with:
--   psql "$DATABASE_URL" -f sql/06_tests.sql
--
-- The whole file runs inside ONE transaction that ROLLS BACK at the end,
-- so it leaves the database exactly as it found it. The final SELECT
-- prints the report before the rollback — save that output as evidence
-- for the Phase 2 Testing Report (rubric: "Testing Report", 5%).
--
-- Cases TC-01..TC-47 and TC-52..TC-54 run as the owner, where RLS is
-- bypassed, and test BUSINESS RULES. TC-48..TC-51 and TC-55..TC-56
-- switch to an ordinary role to test
-- the RLS POLICIES themselves — a superuser can never prove those.
--
-- Groups: 1 identity · 2 FR-21a capture · 3 FR-21b posting ·
--         4 FR-30 payment · 5 DOM-05 disconnection · 6 notifications · 7 RLS
-- =====================================================================

\set ON_ERROR_STOP on
begin;

create table test_results (
  seq         serial primary key,
  tc          text,
  requirement text,
  description text,
  passed      boolean,
  detail      text
);
grant all on test_results to test_app;
grant all on sequence test_results_seq_seq to test_app;

create or replace function t_result(p_tc text, p_req text, p_desc text,
                                    p_passed boolean, p_detail text default null)
returns void language plpgsql as $$
begin
  insert into test_results (tc, requirement, description, passed, detail)
  values (p_tc, p_req, p_desc, coalesce(p_passed, false), p_detail);
end $$;

create sequence t_seq;

-- Ids captured while running as the owner, for use after `set role test_app`.
-- An RLS test cannot look up the row it is meant to be denied — that is the
-- point of the test — so the id has to be stashed beforehand.
create table t_fixture (k text primary key, v uuid);
grant all on t_fixture to test_app;

create or replace function t_mkconsumer(p_area uuid, p_contact text default '09170000000')
returns uuid language plpgsql as $$
declare v_id uuid; n int;
begin
  n := nextval('t_seq');
  insert into consumers (consumer_no, first_name, last_name, contact_number,
                         meter_serial_no, area_id, purok)
  values ('T-' || lpad(n::text, 6, '0'), 'Test', 'Consumer' || n, p_contact,
          'T-SN-' || lpad(n::text, 6, '0'), p_area, 'Purok 1')
  returning id into v_id;
  return v_id;
end $$;

create or replace function t_area_a() returns uuid language sql immutable as
  $$ select '11111111-0000-0000-0000-00000000000a'::uuid $$;
create or replace function t_area_b() returns uuid language sql immutable as
  $$ select '11111111-0000-0000-0000-00000000000b'::uuid $$;

-- Capture a reading AND post an amount, for tests that need a payable bill.
create or replace function t_payable(p_consumer uuid, p_reading numeric,
                                     p_amount numeric, p_at timestamptz,
                                     p_due date)
returns uuid language plpgsql as $$
declare b uuid;
begin
  b := fn_record_meter_reading(p_consumer, p_reading, p_at);
  perform fn_post_bill_amount(b, p_amount, p_due, p_at + interval '7 days');
  return b;
end $$;


-- =====================================================================
-- GROUP 1 — Staffing, accounts and identity
-- =====================================================================

-- TC-01 ---------------------------------------------------------------
do $$
declare ok boolean := false;
begin
  begin
    insert into profiles (user_code, username, first_name, last_name, role, area_id, account_status)
    values ('MTR-DUP','dup.reader','Second','Reader','meter_reader', t_area_a(), 'active');
  exception when others then ok := true;
  end;
  perform t_result('TC-01','ADM-07',
    'A second ACTIVE meter reader cannot be assigned to an area that already has one',
    ok, case when ok then null else 'the duplicate assignment was accepted' end);
end $$;

-- TC-02 ---------------------------------------------------------------
do $$
declare n int;
begin
  select count(*) into n from profiles
   where area_id = t_area_a() and account_status = 'active'
     and role in ('meter_reader','cashier');
  perform t_result('TC-02','ADM-07',
    'One meter reader AND one cashier may share the same area',
    n = 2, format('found %s active staff in Area 3 (expected 2)', n));
end $$;

-- TC-03 ---------------------------------------------------------------
do $$
begin
  update profiles set account_status = 'inactive' where user_code = 'MTR-0001';
  insert into profiles (user_code, username, first_name, last_name, role, area_id, account_status)
  values ('MTR-REPL','repl.reader','Replacement','Reader','meter_reader', t_area_a(), 'active');
  perform t_result('TC-03','ADM-04, ADM-07',
    'Deactivating a meter reader frees the area slot for a replacement', true, null);
exception when others then
  perform t_result('TC-03','ADM-04, ADM-07',
    'Deactivating a meter reader frees the area slot for a replacement',
    false, 'unexpected error: ' || sqlerrm);
end $$;

-- TC-04 ---------------------------------------------------------------
do $$
declare ok boolean := false;
begin
  begin
    insert into consumers (consumer_no, first_name, last_name, meter_serial_no, area_id)
    values ('C-DUPE','Dupe','Meter','BIEC-08317', t_area_a());
  exception when others then ok := true;
  end;
  perform t_result('TC-04','MTR-03',
    'A meter serial number already on file is rejected as a duplicate',
    ok, case when ok then null else 'the duplicate meter serial was accepted' end);
end $$;

-- TC-05 ---------------------------------------------------------------
do $$
declare c uuid; n int;
begin
  -- The New Consumer screen collects name, mobile, purok and barangay only.
  -- No meter serial, so registration must succeed without one.
  insert into consumers (consumer_no, first_name, last_name, contact_number, area_id, purok)
  values ('C-NOMETER','No','Meter','+63 917 555 0999', t_area_a(), 'Purok 3')
  returning id into c;
  select count(*) into n from consumers where id = c and meter_serial_no is null;
  perform t_result('TC-05','MTR-03 / Figma "New Consumer"',
    'A consumer can be registered before a meter serial is assigned',
    n = 1, format('rows with null serial=%s', n));
exception when others then
  perform t_result('TC-05','MTR-03 / Figma "New Consumer"',
    'A consumer can be registered before a meter serial is assigned',
    false, 'unexpected error: ' || sqlerrm);
end $$;

-- TC-06 ---------------------------------------------------------------
do $$
declare c uuid; v text;
begin
  insert into consumers (consumer_no, first_name, last_name, contact_number, area_id, purok)
  values ('C-PHONE','Spaced','Number','+63 917 555 0142', t_area_a(), 'Purok 1')
  returning id into c;
  select contact_number into v from consumers where id = c;
  perform t_result('TC-06','CON-08 / Figma',
    'A spaced mobile number as shown in the mockup is normalised to E.164 and accepted',
    v = '+639175550142', format('stored as %s (expected +639175550142)', v));
exception when others then
  perform t_result('TC-06','CON-08 / Figma',
    'A spaced mobile number as shown in the mockup is normalised and accepted',
    false, 'unexpected error: ' || sqlerrm);
end $$;

-- TC-07 ---------------------------------------------------------------
do $$
declare ok boolean := false;
begin
  begin
    insert into consumers (consumer_no, first_name, last_name, contact_number, area_id)
    values ('C-BADNUM','Bad','Number','12345', t_area_a());
  exception when others then ok := true;
  end;
  perform t_result('TC-07','CON-08',
    'A number that is not a Philippine mobile is still rejected after normalisation',
    ok, case when ok then null else '"12345" was accepted as a mobile number' end);
end $$;

-- TC-08 ---------------------------------------------------------------
do $$
declare ok boolean := false;
begin
  begin
    insert into profiles (user_code, username, first_name, last_name, role, account_status)
    values ('ADM-DUP','ledesman.dormal','Impostor','User','admin','active');
  exception when others then ok := true;
  end;
  perform t_result('TC-08','GEN-01 / Figma "Login"',
    'Usernames are unique, so the login screen can resolve one to exactly one account',
    ok, case when ok then null else 'a duplicate username was accepted' end);
end $$;


-- =====================================================================
-- GROUP 2 — FR-21a: the reader captures, and prices nothing
-- =====================================================================

-- TC-09 ---------------------------------------------------------------
do $$
declare c uuid; b uuid; r record;
begin
  c := t_mkconsumer(t_area_a());
  b := fn_record_meter_reading(c, 150, timestamptz '2026-08-20 09:00+08');
  select bl.status, bl.total_amount, bl.due_date, bl.priced_at, mr.consumption
    into r from bills bl join meter_readings mr on mr.id = bl.meter_reading_id
   where bl.id = b;
  perform t_result('TC-09','FR-21a',
    'Recording a reading creates an UNPRICED bill — no amount, no due date',
    r.status = 'unpriced' and r.total_amount is null
      and r.due_date is null and r.priced_at is null,
    format('status=%s amount=%s due=%s', r.status, r.total_amount, r.due_date));
exception when others then
  perform t_result('TC-09','FR-21a','Reading creates an unpriced bill',
    false, 'unexpected error: ' || sqlerrm);
end $$;

-- TC-10 ---------------------------------------------------------------
do $$
declare c uuid; b uuid; n int;
begin
  c := t_mkconsumer(t_area_a());
  b := fn_record_meter_reading(c, 150, timestamptz '2026-08-20 09:00+08');
  select count(*) into n from notifications where bill_id = b;
  perform t_result('TC-10','FR-13',
    'Capturing a reading sends the consumer NOTHING — there is no amount to announce yet',
    n = 0, format('notifications created at capture=%s (expected 0)', n));
exception when others then
  perform t_result('TC-10','FR-13','No alert at capture', false, 'unexpected error: ' || sqlerrm);
end $$;

-- TC-11 ---------------------------------------------------------------
do $$
declare c uuid; b uuid; r record;
begin
  c := t_mkconsumer(t_area_a());
  b := fn_record_meter_reading(c, 150, timestamptz '2026-08-20 09:00+08');
  select mr.previous_reading, mr.current_reading, mr.consumption
    into r from bills bl join meter_readings mr on mr.id = bl.meter_reading_id where bl.id = b;
  perform t_result('TC-11','MTR-08, DOM-02',
    'A first-ever reading uses a previous value of zero',
    r.previous_reading = 0 and r.consumption = 150,
    format('previous=%s current=%s consumption=%s', r.previous_reading, r.current_reading, r.consumption));
exception when others then
  perform t_result('TC-11','MTR-08, DOM-02','First reading uses zero', false, 'unexpected error: ' || sqlerrm);
end $$;

-- TC-12 ---------------------------------------------------------------
do $$
declare c uuid; b uuid; r record;
begin
  c := t_mkconsumer(t_area_a());
  perform fn_record_meter_reading(c, 3884, timestamptz '2026-07-20 09:00+08');
  b := fn_record_meter_reading(c, 3943, timestamptz '2026-08-20 09:00+08');
  select mr.previous_reading, mr.consumption
    into r from bills bl join meter_readings mr on mr.id = bl.meter_reading_id where bl.id = b;
  -- The mockup: "03,943 kWh − 03,884 kWh = 59 kWh"
  perform t_result('TC-12','MTR-08, DOM-02',
    'The next cycle carries the prior reading forward: 3943 − 3884 = 59 kWh',
    r.previous_reading = 3884 and r.consumption = 59,
    format('previous=%s consumption=%s (expected 3884 / 59)', r.previous_reading, r.consumption));
exception when others then
  perform t_result('TC-12','MTR-08, DOM-02','Consumption across cycles', false, 'unexpected error: ' || sqlerrm);
end $$;

-- TC-13 ---------------------------------------------------------------
do $$
declare c uuid; ok boolean := false; msg text;
begin
  c := t_mkconsumer(t_area_a());
  perform fn_record_meter_reading(c, 100, timestamptz '2026-08-20 09:00+08');
  begin
    perform fn_record_meter_reading(c, 180, timestamptz '2026-08-25 09:00+08');
  exception when others then ok := true; msg := sqlerrm;
  end;
  perform t_result('TC-13','FR-23',
    'A consumer cannot be READ twice inside the same billing cycle', ok, msg);
end $$;

-- TC-14 ---------------------------------------------------------------
do $$
declare c uuid; b1 uuid; b2 uuid; k uuid := gen_random_uuid(); n int;
begin
  c := t_mkconsumer(t_area_a());
  b1 := fn_record_meter_reading(c, 120, timestamptz '2026-08-20 09:00+08', k);
  b2 := fn_record_meter_reading(c, 120, timestamptz '2026-08-20 09:00+08', k);  -- retried sync
  select count(*) into n from meter_readings where consumer_id = c;
  perform t_result('TC-14','MTR-12',
    'A retried offline sync with the same client key creates one reading, not two',
    b1 = b2 and n = 1, format('bill ids equal=%s readings=%s', b1 = b2, n));
exception when others then
  perform t_result('TC-14','MTR-12','Idempotent reading sync', false, 'unexpected error: ' || sqlerrm);
end $$;

-- TC-15 ---------------------------------------------------------------
do $$
declare c uuid; ok boolean := false;
begin
  c := t_mkconsumer(t_area_a());
  begin
    perform fn_record_meter_reading(c, 100, timestamptz '2026-08-20 09:00+08');
    perform fn_record_meter_reading(c, 50,  timestamptz '2026-09-20 09:00+08');
  exception when others then ok := true;
  end;
  perform t_result('TC-15','MTR-09',
    'A present reading lower than the previous one is rejected as a typing error',
    ok, case when ok then null else 'a backwards meter reading was accepted' end);
end $$;

-- TC-16 ---------------------------------------------------------------
-- TC-13 proves the FUNCTION refuses a second reading with a readable
-- message. This proves the DATABASE refuses a duplicate cycle bill even
-- when the function is bypassed — which is what protects against two
-- devices syncing the same cycle concurrently, where both application
-- checks can pass before either writes.
do $$
declare
  c uuid; b_aug uuid; ok boolean := false;
  aug_cycle uuid; jun_cycle uuid; spare_reading uuid;
begin
  c := t_mkconsumer(t_area_a());
  b_aug := fn_record_meter_reading(c, 200, timestamptz '2026-08-20 09:00+08');
  select billing_cycle_id into aug_cycle from bills where id = b_aug;

  jun_cycle := (fn_ensure_billing_cycle(date '2026-06-20')).id;
  insert into meter_readings (consumer_id, billing_cycle_id, previous_reading,
                              current_reading, reading_date, client_uuid)
  values (c, jun_cycle, 0, 50, date '2026-06-20', gen_random_uuid())
  returning id into spare_reading;

  begin
    insert into bills (bill_no, consumer_id, billing_cycle_id, meter_reading_id, consumption)
    values ('BA-RACE-0001', c, aug_cycle, spare_reading, 50);
  exception when others then ok := true;
  end;

  perform t_result('TC-16','FR-23, NFR-05',
    'The database itself refuses a duplicate cycle bill, even when the function is bypassed',
    ok, case when ok then null else 'a duplicate bill for the same cycle was inserted directly' end);
end $$;


-- =====================================================================
-- GROUP 3 — FR-21b: the Admin posts the cooperative's amount
-- =====================================================================

-- TC-17 ---------------------------------------------------------------
do $$
declare c uuid; b uuid; r bills%rowtype;
begin
  c := t_mkconsumer(t_area_a());
  b := fn_record_meter_reading(c, 4668, timestamptz '2026-08-20 09:00+08');
  perform fn_post_bill_amount(b, 658.30, date '2026-09-08', timestamptz '2026-08-27 10:00+08');
  select * into r from bills where id = b;
  -- Whole-peso ceiling: the Admin enters ₱658.30 and the bill stores ₱659.00.
  perform t_result('TC-17','FR-21b',
    'Posting the cooperative''s amount makes the bill payable, with their due date',
    r.status = 'unpaid' and r.total_amount = 659.00
      and r.due_date = date '2026-09-08' and r.balance = 659.00 and r.priced_at is not null,
    format('status=%s amount=%s due=%s balance=%s', r.status, r.total_amount, r.due_date, r.balance));
exception when others then
  perform t_result('TC-17','FR-21b','Posting an amount', false, 'unexpected error: ' || sqlerrm);
end $$;

-- TC-18 ---------------------------------------------------------------
do $$
declare c uuid; b uuid; n record;
begin
  c := t_mkconsumer(t_area_a(), '+63 917 555 0333');
  b := fn_record_meter_reading(c, 300, timestamptz '2026-08-20 09:00+08');
  perform fn_post_bill_amount(b, 500.00, date '2026-09-08', timestamptz '2026-08-27 10:00+08');
  select * into n from notifications where bill_id = b and notif_type = 'bill_ready';
  -- The mockup: "Posting sends the consumer's bill-ready alert automatically."
  perform t_result('TC-18','FR-13, SYS-01',
    'Posting the amount is what fires the bill-ready alert, automatically',
    n.id is not null and n.status = 'pending',
    format('status=%s message=%s', n.status, left(coalesce(n.message_content,''), 50)));
exception when others then
  perform t_result('TC-18','FR-13, SYS-01','Alert fires at posting', false, 'unexpected error: ' || sqlerrm);
end $$;

-- TC-19 ---------------------------------------------------------------
do $$
declare c uuid; b uuid; ch notification_channel;
begin
  c := t_mkconsumer(t_area_a(), '+63 917 555 0334');
  b := fn_record_meter_reading(c, 300, timestamptz '2026-08-20 09:00+08');
  perform fn_post_bill_amount(b, 500.00, date '2026-09-08', timestamptz '2026-08-27 10:00+08');
  select channel into ch from notifications where bill_id = b and notif_type = 'bill_ready';
  -- Objective 3 reserves SMS for overdue and disconnection; a bill-ready
  -- alert is the highest-volume message the system sends, so it goes by push.
  perform t_result('TC-19','Objective 3, FR-16',
    'The bill-ready alert goes by PUSH, not SMS — SMS is reserved for overdue and disconnection',
    ch = 'push', format('channel=%s (expected push)', ch));
exception when others then
  perform t_result('TC-19','Objective 3, FR-16','Bill-ready uses push', false, 'unexpected error: ' || sqlerrm);
end $$;

-- TC-20 ---------------------------------------------------------------
do $$
declare c uuid; b uuid; ok boolean := false;
begin
  c := t_mkconsumer(t_area_a());
  b := fn_record_meter_reading(c, 300, timestamptz '2026-08-20 09:00+08');
  perform fn_post_bill_amount(b, 500.00, date '2026-09-08', timestamptz '2026-08-27 10:00+08');
  begin
    perform fn_post_bill_amount(b, 999.00, date '2026-09-30', timestamptz '2026-08-28 10:00+08');
  exception when others then ok := true;
  end;
  perform t_result('TC-20','FR-21b',
    'An amount cannot be posted twice against the same bill',
    ok, case when ok then null else 'the bill was re-priced' end);
end $$;

-- TC-21 ---------------------------------------------------------------
do $$
declare c uuid; b uuid; ok boolean := false;
begin
  c := t_mkconsumer(t_area_a());
  b := fn_record_meter_reading(c, 300, timestamptz '2026-08-20 09:00+08');
  begin
    perform fn_post_bill_amount(b, 500.00, date '2026-08-01', timestamptz '2026-08-27 10:00+08');
  exception when others then ok := true;
  end;
  perform t_result('TC-21','FR-21b',
    'A due date already in the past is rejected when posting',
    ok, case when ok then null else 'a due date before the posting date was accepted' end);
end $$;

-- TC-22 ---------------------------------------------------------------
do $$
declare c uuid; b uuid; ok boolean := true;
begin
  c := t_mkconsumer(t_area_a());
  b := fn_record_meter_reading(c, 300, timestamptz '2026-08-20 09:00+08');
  begin
    -- half-priced: an amount with no due date must be impossible
    update bills set total_amount = 500 where id = b;
    ok := false;
  exception when others then ok := true;
  end;
  perform t_result('TC-22','FR-21b',
    'A bill cannot be half-priced — an amount without a due date is refused',
    ok, case when ok then null else 'an amount was set with no due date' end);
end $$;

-- TC-23 ---------------------------------------------------------------
do $$
declare c uuid; b uuid; n int;
begin
  c := t_mkconsumer(t_area_a());
  b := fn_record_meter_reading(c, 300, timestamptz '2026-08-20 09:00+08');
  select count(*) into n from v_readings_awaiting_amount where bill_id = b;
  perform t_result('TC-23','FR-21b / Figma "Amounts"',
    'An unpriced bill appears in the Admin''s "readings awaiting an amount" queue',
    n = 1, format('rows in queue for this bill=%s (expected 1)', n));
exception when others then
  perform t_result('TC-23','FR-21b','Awaiting-amount queue', false, 'unexpected error: ' || sqlerrm);
end $$;

-- TC-24 ---------------------------------------------------------------
do $$
declare c uuid; b uuid; n int;
begin
  c := t_mkconsumer(t_area_a());
  b := fn_record_meter_reading(c, 300, timestamptz '2026-08-20 09:00+08');
  perform fn_post_bill_amount(b, 500.00, date '2026-09-08', timestamptz '2026-08-27 10:00+08');
  select count(*) into n from v_readings_awaiting_amount where bill_id = b;
  perform t_result('TC-24','FR-21b / Figma "Amounts1"',
    'Once posted, the bill leaves the Admin queue',
    n = 0, format('rows still in queue=%s (expected 0)', n));
exception when others then
  perform t_result('TC-24','FR-21b','Posted bill leaves the queue', false, 'unexpected error: ' || sqlerrm);
end $$;

-- TC-25 ---------------------------------------------------------------
do $$
declare c uuid; b uuid; r record;
begin
  c := t_mkconsumer(t_area_a());
  b := fn_record_meter_reading(c, 3943, timestamptz '2026-08-20 09:00+08');
  select * into r from v_consumer_current_bill where consumer_id = c;
  -- FR-25: the seven-day window must be visible to the consumer — the
  -- reading and consumption are shown, and the amount is explicitly absent.
  perform t_result('TC-25','FR-25',
    'During the seven-day wait the consumer still sees the reading and consumption, flagged unpriced',
    r.bill_id = b and r.is_unpriced and r.total_amount is null
      and r.current_reading = 3943 and r.consumption = 3943,
    format('unpriced=%s amount=%s reading=%s', r.is_unpriced, r.total_amount, r.current_reading));
exception when others then
  perform t_result('TC-25','FR-25','Unpriced bill visible to consumer', false, 'unexpected error: ' || sqlerrm);
end $$;


-- =====================================================================
-- GROUP 4 — FR-30: payments, and one receipt per handover
-- =====================================================================

-- TC-26 ---------------------------------------------------------------
do $$
declare c uuid; b uuid; ok boolean := false; msg text;
begin
  c := t_mkconsumer(t_area_a());
  b := fn_record_meter_reading(c, 300, timestamptz '2026-08-20 09:00+08');   -- left unpriced
  begin
    perform fn_record_payment(array[b], array[100.00]::numeric[]);
  exception when others then ok := true; msg := sqlerrm;
  end;
  perform t_result('TC-26','FR-30',
    'An unpriced bill cannot be settled — there is no amount to collect against',
    ok, msg);
end $$;

-- TC-27 ---------------------------------------------------------------
do $$
declare c uuid; b uuid; r bills%rowtype;
begin
  c := t_mkconsumer(t_area_a());
  b := t_payable(c, 300, 704.20, timestamptz '2026-08-20 09:00+08', date '2026-09-08');
  perform fn_record_payment(array[b], array[704.20]::numeric[]);
  select * into r from bills where id = b;
  perform t_result('TC-27','FR-30, CSH-04',
    'Paying a bill in full sets it to PAID with a zero balance',
    r.status = 'paid' and r.balance = 0,
    format('status=%s balance=%s', r.status, r.balance));
exception when others then
  perform t_result('TC-27','FR-30','Full payment', false, 'unexpected error: ' || sqlerrm);
end $$;

-- TC-28 ---------------------------------------------------------------
do $$
declare c uuid; b uuid; r bills%rowtype;
begin
  c := t_mkconsumer(t_area_a());
  b := t_payable(c, 300, 704.20, timestamptz '2026-08-20 09:00+08', date '2026-09-08');
  perform fn_record_payment(array[b], array[200.00]::numeric[]);
  select * into r from bills where id = b;
  perform t_result('TC-28','CSH-04',
    'A part payment sets the bill to PARTIAL and leaves the correct balance',
    r.status = 'partial' and r.balance = 504.20,
    format('status=%s balance=%s (expected partial / 504.20)', r.status, r.balance));
exception when others then
  perform t_result('TC-28','CSH-04','Partial payment', false, 'unexpected error: ' || sqlerrm);
end $$;

-- TC-29 ---------------------------------------------------------------
do $$
declare
  c uuid; b1 uuid; b2 uuid; b3 uuid; txn uuid;
  n_lines int; n_receipts int; n_paid int; r payment_transactions%rowtype;
begin
  c := t_mkconsumer(t_area_a());
  b1 := t_payable(c, 100, 612.40, timestamptz '2026-06-20 09:00+08', date '2026-09-08');
  b2 := t_payable(c, 200, 658.75, timestamptz '2026-07-20 09:00+08', date '2026-09-08');
  b3 := t_payable(c, 300, 704.20, timestamptz '2026-08-20 09:00+08', date '2026-09-08');
  txn := fn_record_payment(array[b1,b2,b3],
                           array[612.40, 658.75, 704.20]::numeric[],
                           2000.00, timestamptz '2026-08-21 14:18+08');
  select count(*) into n_lines from payments where transaction_id = txn;
  select count(distinct pt.receipt_no) into n_receipts
    from payments pay join payment_transactions pt on pt.id = pay.transaction_id
   where pay.transaction_id = txn;
  select count(*) into n_paid from bills where id in (b1,b2,b3) and status = 'paid';
  select * into r from payment_transactions where id = txn;
  -- The mockup: "Total (3 bills) ₱1,975.35 · Cash tendered ₱2,000.00 · Change ₱24.65"
  perform t_result('TC-29','FR-30, CSH-06 / Figma "Receipt"',
    'Three bills settled in one handover produce ONE receipt number, three allocation lines, and correct change',
    n_lines = 3 and n_receipts = 1 and n_paid = 3
      and r.total_collected = 1975.35 and r.change_due = 24.65,
    format('lines=%s distinct receipts=%s paid=%s total=%s change=%s',
           n_lines, n_receipts, n_paid, r.total_collected, r.change_due));
exception when others then
  perform t_result('TC-29','FR-30, CSH-06','One receipt per handover', false, 'unexpected error: ' || sqlerrm);
end $$;

-- TC-30 ---------------------------------------------------------------
do $$
declare c uuid; b1 uuid; b2 uuid; txn uuid; n int;
begin
  c := t_mkconsumer(t_area_a());
  b1 := t_payable(c, 100, 612.40, timestamptz '2026-06-20 09:00+08', date '2026-09-08');
  b2 := t_payable(c, 200, 658.75, timestamptz '2026-07-20 09:00+08', date '2026-09-08');
  txn := fn_record_payment(array[b1,b2], array[612.40, 658.75]::numeric[]);
  -- The mockup's Consumer History shows the SAME OR number against June and July.
  select count(distinct receipt_no) into n from v_payment_history
   where consumer_id = c and bill_id in (b1,b2);
  perform t_result('TC-30','CON-03 / Figma "History"',
    'Both settled months show the same OR number in the consumer''s payment history',
    n = 1, format('distinct receipt numbers across the two months=%s (expected 1)', n));
exception when others then
  perform t_result('TC-30','CON-03','Shared OR number in history', false, 'unexpected error: ' || sqlerrm);
end $$;

-- TC-31 ---------------------------------------------------------------
do $$
declare c uuid; b uuid; ok boolean := false;
begin
  c := t_mkconsumer(t_area_a());
  b := t_payable(c, 300, 704.20, timestamptz '2026-08-20 09:00+08', date '2026-09-08');
  begin
    perform fn_record_payment(array[b], array[999999.00]::numeric[]);
  exception when others then ok := true;
  end;
  perform t_result('TC-31','CSH-04',
    'A payment larger than the outstanding balance is refused',
    ok, case when ok then null else 'an overpayment was accepted' end);
end $$;

-- TC-32 ---------------------------------------------------------------
do $$
declare c uuid; b1 uuid; b2 uuid; ok boolean := false; paid numeric; n int;
begin
  c := t_mkconsumer(t_area_a());
  b1 := t_payable(c, 100, 612.40, timestamptz '2026-06-20 09:00+08', date '2026-09-08');
  b2 := t_payable(c, 200, 658.75, timestamptz '2026-07-20 09:00+08', date '2026-09-08');
  begin
    perform fn_record_payment(array[b1,b2], array[500.00, 999999.00]::numeric[]);
  exception when others then ok := true;
  end;
  select amount_paid into paid from bills where id = b1;
  select count(*) into n from payment_transactions where consumer_id = c;
  perform t_result('TC-32','CSH-04, NFR-07',
    'A multi-bill payment is atomic: one bad amount leaves no receipt and no credit',
    ok and paid = 0 and n = 0,
    format('rejected=%s first bill paid=%s receipts created=%s', ok, paid, n));
exception when others then
  perform t_result('TC-32','CSH-04, NFR-07','Payment atomicity', false, 'unexpected error: ' || sqlerrm);
end $$;

-- TC-33 ---------------------------------------------------------------
do $$
declare c uuid; b uuid; t1 uuid; t2 uuid; k uuid := gen_random_uuid(); n int;
begin
  c := t_mkconsumer(t_area_a());
  b := t_payable(c, 300, 704.20, timestamptz '2026-08-20 09:00+08', date '2026-09-08');
  t1 := fn_record_payment(array[b], array[704.20]::numeric[], null, now(), k);
  t2 := fn_record_payment(array[b], array[704.20]::numeric[], null, now(), k);  -- retried sync
  select count(*) into n from payment_transactions where consumer_id = c;
  -- Cashiers work offline too ("3 payments waiting to sync"), so a replayed
  -- payment must not double-credit the bill.
  perform t_result('TC-33','MTR-12 / Figma "Cashier Profile"',
    'A retried offline PAYMENT with the same client key credits the bill once, not twice',
    t1 = t2 and n = 1, format('same transaction=%s transactions=%s', t1 = t2, n));
exception when others then
  perform t_result('TC-33','MTR-12','Idempotent payment sync', false, 'unexpected error: ' || sqlerrm);
end $$;

-- TC-34 ---------------------------------------------------------------
do $$
declare c uuid; b uuid; txn uuid; ok boolean := false;
begin
  c := t_mkconsumer(t_area_a());
  b := t_payable(c, 300, 704.20, timestamptz '2026-08-20 09:00+08', date '2026-09-08');
  txn := fn_record_payment(array[b], array[100.00]::numeric[]);
  begin
    insert into payments (transaction_id, bill_id, consumer_id, amount_paid, payment_method)
    values (txn, b, c, 100.00, 'gcash');
  exception when others then ok := true;
  end;
  perform t_result('TC-34','CSH-05, DOM-06',
    'Cash is the only permitted payment method; the database rejects any other',
    ok, case when ok then null else 'a non-cash payment method was accepted' end);
end $$;


-- =====================================================================
-- GROUP 5 — Disconnection (DOM-05)
-- =====================================================================

-- TC-35 ---------------------------------------------------------------
do $$
declare got timestamptz; expected timestamptz := timestamptz '2026-08-13 10:00+08';
begin
  got := fn_earliest_lawful_disconnection(timestamptz '2026-08-11 10:00+08');
  perform t_result('TC-35','DOM-05',
    'Notice served on a Tuesday morning becomes lawful exactly 48 hours later',
    got = expected, format('got %s, expected %s', got, expected));
end $$;

-- TC-36 ---------------------------------------------------------------
do $$
declare got timestamptz; expected timestamptz := timestamptz '2026-08-17 08:00+08';
begin
  got := fn_earliest_lawful_disconnection(timestamptz '2026-08-13 14:00+08');
  perform t_result('TC-36','DOM-05',
    'A 48-hour window landing on a Saturday advances to Monday morning',
    got = expected, format('got %s, expected %s', got, expected));
end $$;

-- TC-37 ---------------------------------------------------------------
do $$
declare got timestamptz; expected timestamptz := timestamptz '2026-08-13 08:00+08';
begin
  got := fn_earliest_lawful_disconnection(timestamptz '2026-08-10 16:00+08');
  perform t_result('TC-37','DOM-05',
    'A window falling after 3:00 p.m. advances to the next morning, never the same afternoon',
    got = expected, format('got %s, expected %s', got, expected));
end $$;

-- TC-38 ---------------------------------------------------------------
do $$
declare got timestamptz; expected timestamptz := timestamptz '2026-09-01 08:00+08';
begin
  got := fn_earliest_lawful_disconnection(timestamptz '2026-08-29 09:00+08');
  perform t_result('TC-38','DOM-05',
    'An official Philippine holiday is skipped when computing the lawful window',
    got = expected, format('got %s, expected %s', got, expected));
end $$;

-- TC-39 ---------------------------------------------------------------
do $$
declare ok boolean := false;
begin
  begin
    update settings set courtesy_notice_hours = 24 where id = 1;
  exception when others then ok := true;
  end;
  perform t_result('TC-39','DOM-05',
    'The notice period cannot be configured below the 48-hour statutory minimum',
    ok, case when ok then null else 'a 24-hour notice period was accepted' end);
end $$;

-- TC-40 ---------------------------------------------------------------
do $$
declare c uuid; ok boolean := false;
begin
  c := t_mkconsumer(t_area_a());
  perform fn_record_meter_reading(c, 100, timestamptz '2026-06-20 09:00+08');  -- unpriced
  begin
    perform fn_issue_disconnection_notice(c, null, timestamptz '2026-08-20 10:00+08');
  exception when others then ok := true;
  end;
  -- An unpriced bill has no due date and can never be overdue, so the
  -- overdue threshold is computable only over payable bills.
  perform t_result('TC-40','MTR-15, FR-24',
    'An unpriced bill can never make an account overdue, so no notice can be issued against it',
    ok, case when ok then null else 'a notice was issued against an unpriced bill' end);
end $$;

-- TC-41 ---------------------------------------------------------------
do $$
declare c uuid; n uuid; r disconnection_notices%rowtype;
begin
  c := t_mkconsumer(t_area_a());
  perform t_payable(c, 100, 612.40, timestamptz '2026-06-20 09:00+08', date '2026-07-05');
  n := fn_issue_disconnection_notice(c, 'Unpaid electricity bill', timestamptz '2026-08-19 10:42+08');
  select * into r from disconnection_notices where id = n;
  -- The mockup: "DN-2026-0819-0033"
  perform t_result('TC-41','MTR-15 / Figma "Disconnection Notice"',
    'A served notice carries a human-readable reference in the mockup''s DN-YYYY-MMDD-NNNN form',
    r.notice_no like 'DN-2026-0819-%',
    format('notice_no=%s', r.notice_no));
exception when others then
  perform t_result('TC-41','MTR-15','Notice reference number', false, 'unexpected error: ' || sqlerrm);
end $$;

-- TC-42 ---------------------------------------------------------------
do $$
declare c uuid; n1 uuid; ok boolean := false;
begin
  c := t_mkconsumer(t_area_a());
  perform t_payable(c, 100, 612.40, timestamptz '2026-06-20 09:00+08', date '2026-07-05');
  n1 := fn_issue_disconnection_notice(c, 'Unpaid bill', timestamptz '2026-08-19 10:42+08');
  begin
    perform fn_issue_disconnection_notice(c, 'Unpaid bill', timestamptz '2026-08-20 10:00+08');
  exception when others then ok := true;
  end;
  perform t_result('TC-42','CON-04',
    'A consumer may have only one active disconnection notice at a time',
    ok and n1 is not null,
    case when ok then null else 'a second active notice was created' end);
end $$;

-- TC-43 ---------------------------------------------------------------
do $$
declare c uuid; n uuid; st notice_status; still_active int;
begin
  c := t_mkconsumer(t_area_a());
  perform t_payable(c, 100, 612.40, timestamptz '2026-06-20 09:00+08', date '2026-07-05');
  n := fn_issue_disconnection_notice(c, 'Unpaid bill', timestamptz '2026-08-19 10:42+08');
  perform fn_close_disconnection_notice(n, 'referred', 'Handover to cooperative personnel recorded');
  select status into st from disconnection_notices where id = n;
  select count(*) into still_active from v_active_disconnection_warnings where consumer_id = c;
  perform t_result('TC-43','ADM-17, CON-04',
    'Recording an outcome closes the notice and clears the consumer''s warning banner',
    st = 'referred' and still_active = 0,
    format('status=%s active warnings=%s', st, still_active));
exception when others then
  perform t_result('TC-43','ADM-17, CON-04','Closing a notice clears the warning',
    false, 'unexpected error: ' || sqlerrm);
end $$;


-- =====================================================================
-- GROUP 6 — Notifications and progress counters
-- =====================================================================

-- TC-44 ---------------------------------------------------------------
do $$
declare c uuid; b uuid; n record;
begin
  c := t_mkconsumer(t_area_a(), null);          -- no contact number on file
  b := fn_record_meter_reading(c, 100, timestamptz '2026-08-20 09:00+08');
  perform fn_post_bill_amount(b, 500.00, date '2026-09-08', timestamptz '2026-08-27 10:00+08');
  select * into n from notifications where bill_id = b;
  -- Push is delivered to the device, not the number, so a missing mobile
  -- must NOT fail a push alert the way it fails an SMS (TC-45).
  perform t_result('TC-44','SYS-04',
    'A push alert still queues for a consumer with no mobile number on file',
    n.id is not null and n.channel = 'push' and n.status = 'pending',
    format('channel=%s status=%s', n.channel, n.status));
exception when others then
  perform t_result('TC-44','SYS-04','Push does not need a phone number',
    false, 'unexpected error: ' || sqlerrm);
end $$;

-- TC-45 ---------------------------------------------------------------
do $$
declare c uuid; n uuid; rec record;
begin
  c := t_mkconsumer(t_area_a(), null);          -- no contact number
  perform t_payable(c, 100, 612.40, timestamptz '2026-06-20 09:00+08', date '2026-07-05');
  n := fn_issue_disconnection_notice(c, 'Unpaid bill', timestamptz '2026-08-19 10:42+08');
  select * into rec from notifications where disconnection_id = n;
  perform t_result('TC-45','SYS-04',
    'An SMS to a consumer with no number is recorded as FAILED with a reason, never omitted',
    rec.id is not null and rec.status = 'failed' and rec.failed_reason is not null,
    format('status=%s reason=%s', rec.status, rec.failed_reason));
exception when others then
  perform t_result('TC-45','SYS-04','Missing number stays visible', false, 'unexpected error: ' || sqlerrm);
end $$;

-- TC-46 ---------------------------------------------------------------
do $$
declare c1 uuid; c2 uuid; cyc uuid; r record;
begin
  c1 := t_mkconsumer(t_area_b());
  c2 := t_mkconsumer(t_area_b());
  perform fn_record_meter_reading(c1, 100, timestamptz '2026-10-20 09:00+08');  -- read, left unpriced
  cyc := (fn_ensure_billing_cycle(date '2026-10-20')).id;
  select * into r from v_meter_reader_progress
   where area_id = t_area_b() and billing_cycle_id = cyc;
  -- FR-19: the reader's progress counts READINGS. It must not wait on the
  -- cooperative returning an amount.
  perform t_result('TC-46','FR-19 / Figma "Readings"',
    'Reader progress counts readings, not bills — an unpriced reading still counts as read',
    r.read_count = 1 and r.not_yet_read_count >= 1,
    format('read=%s not yet read=%s total=%s', r.read_count, r.not_yet_read_count, r.total_consumers));
exception when others then
  perform t_result('TC-46','FR-19','Reader progress counts readings', false, 'unexpected error: ' || sqlerrm);
end $$;

-- TC-47 ---------------------------------------------------------------
do $$
declare c uuid; r record; cyc uuid;
begin
  c := t_mkconsumer(t_area_b());
  perform fn_record_meter_reading(c, 100, timestamptz '2026-11-20 09:00+08');   -- unpriced
  cyc := (fn_ensure_billing_cycle(date '2026-11-20')).id;
  select * into r from v_cashier_collection_progress
   where area_id = t_area_b() and billing_cycle_id = cyc;
  perform t_result('TC-47','CSH-02 / Figma "Consumers"',
    'An unpriced bill is not counted as collectable in the cashier''s outstanding figure',
    r.payable_count = 0 and r.awaiting_amount_count = 1 and r.total_outstanding = 0,
    format('payable=%s awaiting=%s outstanding=%s',
           r.payable_count, r.awaiting_amount_count, r.total_outstanding));
exception when others then
  perform t_result('TC-47','CSH-02','Unpriced excluded from collections', false, 'unexpected error: ' || sqlerrm);
end $$;


-- =====================================================================
-- GROUP 7 — Row-Level Security
--
-- These run as `test_app`, an ordinary role. RLS is bypassed by
-- superusers and table owners, so this is the only way to prove the
-- policies actually hold.
-- =====================================================================

-- TC-52 ---------------------------------------------------------------
do $$
declare ok boolean := false;
begin
  begin
    insert into profiles (user_code, username, first_name, last_name, role,
                          position_title, area_id, account_status)
    values ('ADM-DUP2','second.president','Second','President','admin',
            'Area President', t_area_a(), 'active');
  exception when others then ok := true;
  end;
  perform t_result('TC-52','FR-31',
    'An area cannot have two active Area Presidents — one Admin per service area',
    ok, case when ok then null else 'a second active admin was accepted for the area' end);
end $$;

-- TC-53 ---------------------------------------------------------------
do $$
declare ok boolean := false;
begin
  begin
    insert into profiles (user_code, username, first_name, last_name, role, account_status)
    values ('ADM-NOAREA','floating.admin','Floating','Admin','admin','active');
  exception when others then ok := true;
  end;
  perform t_result('TC-53','FR-31 / Phase 1 §5',
    'An Admin must belong to a service area — the Admin is an Area President, not a superuser',
    ok, case when ok then null else 'an admin was created with no service area' end);
end $$;

-- TC-54 ---------------------------------------------------------------
do $$
declare n int;
begin
  select count(*) into n from areas where is_active;
  perform t_result('TC-54','Phase 1 §4',
    'Barangay Tubod is deployed across four service areas',
    n = 4, format('active areas=%s (expected 4)', n));
end $$;


-- Stash an Area 4 unpriced bill for TC-56, while RLS is still bypassed.
do $$
declare c uuid; b uuid;
begin
  c := t_mkconsumer(t_area_b());
  b := fn_record_meter_reading(c, 500, timestamptz '2026-12-20 09:00+08');
  insert into t_fixture (k, v) values ('area4_unpriced_bill', b)
  on conflict (k) do update set v = excluded.v;
end $$;


-- TC-48 ---------------------------------------------------------------
set local role test_app;
set local app.current_user_id = '33333333-0000-0000-0000-000000000004';  -- Test Area 2 meter reader

insert into test_results (tc, requirement, description, passed, detail)
select 'TC-48', 'MTR-02, DOM-08',
       'A meter reader sees only consumers inside their assigned area',
       count(*) > 0 and bool_and(area_id = '11111111-0000-0000-0000-00000000000b'),
       format('visible consumers=%s, all in their own area=%s',
              count(*), bool_and(area_id = '11111111-0000-0000-0000-00000000000b'))
from consumers;

-- TC-49 ---------------------------------------------------------------
set local app.current_user_id = '44444444-0000-0000-0000-000000000001';  -- consumer Virgilio

insert into test_results (tc, requirement, description, passed, detail)
select 'TC-49', 'GEN-08, CON-02',
       'A consumer can see only their own consumer record, never anyone else''s',
       count(*) = 1 and bool_and(consumer_no = '2019-0917-TUB'),
       format('visible consumer records=%s (expected exactly 1: 2019-0917-TUB)', count(*))
from consumers;

-- TC-50 ---------------------------------------------------------------
set local app.current_user_id = '33333333-0000-0000-0000-000000000004';

do $$
declare ok boolean := false;
begin
  begin
    insert into consumers (consumer_no, first_name, last_name, meter_serial_no, area_id)
    values ('C-CROSS','Cross','Area','T-SN-CROSS', '11111111-0000-0000-0000-00000000000a');
  exception when others then ok := true;
  end;
  insert into test_results (tc, requirement, description, passed, detail)
  values ('TC-50', 'MTR-02, DOM-08',
          'A meter reader cannot register a consumer into someone else''s area',
          ok, case when ok then null else 'the cross-area insert was allowed' end);
end $$;

-- TC-51 ---------------------------------------------------------------
set local app.current_user_id = '33333333-0000-0000-0000-000000000003';  -- a Cashier

do $$
declare ok boolean := false; b uuid;
begin
  select id into b from bills where total_amount is null limit 1;
  if b is null then
    insert into test_results (tc, requirement, description, passed, detail)
    values ('TC-51','FR-21b','Only an Admin may post a bill amount', false, 'no unpriced bill in fixture');
    return;
  end if;
  begin
    perform fn_post_bill_amount(b, 500.00, date '2026-12-31');
  exception when others then ok := true;
  end;
  insert into test_results (tc, requirement, description, passed, detail)
  values ('TC-51','FR-21b',
          'A Cashier cannot post a bill amount — pricing is the Admin''s alone',
          ok, case when ok then null else 'a cashier priced a bill' end);
end $$;

-- TC-55 ---------------------------------------------------------------
-- The most important RLS case in the suite: an Area President is NOT a
-- superuser. Area 3's admin must not see Area 4's consumers.
set local app.current_user_id = '33333333-0000-0000-0000-000000000001';  -- Area 3 Admin

insert into test_results (tc, requirement, description, passed, detail)
select 'TC-55', 'FR-31, NFR-02',
       'An Area President sees only their own area''s consumers, never another area''s',
       count(*) > 0 and bool_and(area_id = '11111111-0000-0000-0000-00000000000a'),
       format('visible consumers=%s, all in Area 3=%s',
              count(*), bool_and(area_id = '11111111-0000-0000-0000-00000000000a'))
from consumers;

-- TC-56 ---------------------------------------------------------------
do $$
declare ok boolean := false; b uuid;
begin
  -- an unpriced bill belonging to AREA 4, which the Area 3 admin must not price
  select v into b from t_fixture where k = 'area4_unpriced_bill';
  if b is null then
    insert into test_results (tc, requirement, description, passed, detail)
    values ('TC-56','FR-31','An Admin cannot post an amount outside their own area',
            false, 'no Area 4 unpriced bill in fixture');
    return;
  end if;
  begin
    perform fn_post_bill_amount(b, 500.00, date '2026-12-31');
  exception when others then ok := true;
  end;
  insert into test_results (tc, requirement, description, passed, detail)
  values ('TC-56','FR-31, NFR-02',
          'An Admin cannot post an amount against a bill in another service area',
          ok, case when ok then null else 'a cross-area bill was priced' end);
end $$;

reset role;


-- =====================================================================
-- REPORT
-- =====================================================================
\echo ''
\echo '=============================================================='
\echo ' BillAlert — Week 10 data model test report'
\echo '=============================================================='

select
  tc                                           as "Case",
  requirement                                  as "Requirement",
  case when passed then 'PASS' else 'FAIL' end as "Result",
  description                                  as "What it proves"
from test_results
order by seq;

\echo ''
select
  count(*)                                    as "Total",
  count(*) filter (where passed)              as "Passed",
  count(*) filter (where not passed)          as "Failed",
  round(100.0 * count(*) filter (where passed) / nullif(count(*),0), 1) as "Pass %"
from test_results;

\echo ''
\echo 'Failures (empty means everything passed):'
select tc as "Case", requirement as "Requirement", detail as "Detail"
from test_results where not passed order by seq;

rollback;
