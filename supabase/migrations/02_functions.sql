-- =====================================================================
-- BillAlert — 02_functions.sql
-- Session helpers, the DOM-05 lawful-window calculator, and the four
-- transactional operations that must never half-complete.
--
--   fn_record_meter_reading      FR-21a  Meter Reader captures, unpriced
--   fn_post_bill_amount          FR-21b  Admin posts a whole-peso amount
--   fn_record_payment            FR-30   Cashier collects
--   fn_issue_disconnection_notice MTR-15 Meter Reader serves notice
--
-- No function in this file computes a peso amount from a reading.
-- BillAlert does not price bills.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Session context helpers
--
-- On Supabase these read auth.uid(). On a plain Postgres (local testing,
-- CI) they fall back to a session GUC:  set local app.current_user_id = '...'
-- ---------------------------------------------------------------------
create or replace function app.current_user_id() returns uuid
language plpgsql stable as $$
declare v uuid;
begin
  begin
    execute 'select auth.uid()' into v;
  exception when others then
    v := null;
  end;
  if v is null then
    v := nullif(current_setting('app.current_user_id', true), '')::uuid;
  end if;
  return v;
end $$;

-- SECURITY DEFINER: called from inside RLS policies on profiles, so they
-- must not re-enter those policies and recurse.
create or replace function app.current_role() returns user_role
language sql stable security definer set search_path = public, pg_temp as $$
  select role from profiles where id = app.current_user_id();
$$;

create or replace function app.current_area() returns uuid
language sql stable security definer set search_path = public, pg_temp as $$
  select area_id from profiles where id = app.current_user_id();
$$;

create or replace function app.current_consumer_id() returns uuid
language sql stable security definer set search_path = public, pg_temp as $$
  select id from consumers where profile_id = app.current_user_id();
$$;

create or replace function app.is_admin() returns boolean
language sql stable as $$ select app.current_role() = 'admin'::user_role $$;

-- FR-31: an Admin is an AREA PRESIDENT, not a superuser. Every staff role —
-- Admin included — is confined to its own service area. This helper is what
-- the RLS policies use; `app.is_admin()` alone must never grant cross-area
-- access, or one area's president can read another area's consumers.
create or replace function app.staff_in_area(p_area uuid) returns boolean
language sql stable as $$
  select app.current_role() in ('admin','meter_reader','cashier')
     and p_area = app.current_area();
$$;


-- ---------------------------------------------------------------------
-- SYS-07: Philippine Standard Time. Never trust the device clock.
-- ---------------------------------------------------------------------
create or replace function fn_ph_today(p_at timestamptz default now()) returns date
language sql stable as $$
  select (p_at at time zone 'Asia/Manila')::date;
$$;


-- ---------------------------------------------------------------------
-- DOM-01: resolve (or create) the billing cycle containing a date.
-- ---------------------------------------------------------------------
create or replace function fn_ensure_billing_cycle(p_date date)
returns billing_cycles
language plpgsql as $$
declare
  s       settings%rowtype;
  v_start date;
  v_end   date;
  v_cycle billing_cycles%rowtype;
begin
  select * into s from settings where id = 1;
  if not found then
    raise exception 'settings row is missing; run 05_seed.sql';
  end if;

  if extract(day from p_date) >= s.cycle_start_day then
    v_start := make_date(extract(year from p_date)::int, extract(month from p_date)::int, s.cycle_start_day);
  else
    v_start := (make_date(extract(year from p_date)::int, extract(month from p_date)::int, s.cycle_start_day)
                - interval '1 month')::date;
  end if;
  v_end := (v_start + interval '1 month - 1 day')::date;

  select * into v_cycle from billing_cycles
   where cycle_year = extract(year from v_start)::smallint
     and cycle_month = extract(month from v_start)::smallint;

  if not found then
    insert into billing_cycles (cycle_year, cycle_month, period_start, period_end)
    values (extract(year from v_start)::smallint, extract(month from v_start)::smallint, v_start, v_end)
    on conflict (cycle_year, cycle_month) do nothing;

    select * into v_cycle from billing_cycles
     where cycle_year = extract(year from v_start)::smallint
       and cycle_month = extract(month from v_start)::smallint;
  end if;

  return v_cycle;
end $$;


-- ---------------------------------------------------------------------
-- DOM-05: earliest lawful disconnection date and time.
--
--   1. Add the notice period (>= 48h statutory minimum, ERC Magna Carta).
--   2. Advance until the result falls inside a lawful window:
--        - a weekday that is not an official Philippine holiday,
--        - between the configured window start and 3:00 p.m.
--
-- ASSUMPTION (verify with the cooperative): the window OPENS at 08:00.
-- The Magna Carta states only that disconnection may not occur AFTER 3 p.m.
--
-- The system computes and records this. It never disconnects anyone.
-- ---------------------------------------------------------------------
-- SECURITY DEFINER: whether a date is a public holiday is a matter of law, not
-- of the caller's permissions. Pinning it here means the lawful window cannot
-- change because of who asked, and cannot silently lose the holiday calendar if
-- RLS on ph_holidays is ever tightened.
create or replace function fn_earliest_lawful_disconnection(p_served_at timestamptz)
returns timestamptz
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare
  tz      constant text := 'Asia/Manila';
  s       settings%rowtype;
  v_local timestamp;
  v_guard int := 0;
begin
  select * into s from settings where id = 1;
  if not found then
    raise exception 'settings row is missing; run 05_seed.sql';
  end if;

  v_local := (p_served_at + make_interval(hours => s.courtesy_notice_hours)) at time zone tz;

  loop
    v_guard := v_guard + 1;
    if v_guard > 60 then
      raise exception 'could not resolve a lawful disconnection window within 60 days of %', p_served_at;
    end if;

    if v_local::time < make_time(s.disconnection_window_start_hour, 0, 0) then
      v_local := date_trunc('day', v_local) + make_interval(hours => s.disconnection_window_start_hour);
    end if;

    if v_local::time > make_time(s.disconnection_window_end_hour, 0, 0) then
      v_local := date_trunc('day', v_local) + interval '1 day'
                 + make_interval(hours => s.disconnection_window_start_hour);
      continue;
    end if;

    if extract(isodow from v_local) >= 6
       or exists (select 1 from ph_holidays where holiday_date = v_local::date) then
      v_local := date_trunc('day', v_local) + interval '1 day'
                 + make_interval(hours => s.disconnection_window_start_hour);
      continue;
    end if;

    exit;
  end loop;

  return v_local at time zone tz;
end $$;


-- ---------------------------------------------------------------------
-- ADM-14: render the bill-ready message. Only ever called AFTER pricing.
-- ---------------------------------------------------------------------
create or replace function fn_render_bill_message(p_bill_id uuid)
returns text
language plpgsql stable as $$
declare
  s   settings%rowtype;
  r   record;
  msg text;
begin
  select * into s from settings where id = 1;
  select b.*, c.first_name, c.last_name, c.consumer_no,
         mr.previous_reading, mr.current_reading,
         to_char(bc.period_start, 'FMMonth YYYY') as cycle_label
    into r
    from bills b
    join consumers c       on c.id  = b.consumer_id
    join meter_readings mr on mr.id = b.meter_reading_id
    join billing_cycles bc on bc.id = b.billing_cycle_id
   where b.id = p_bill_id;

  if not found then
    raise exception 'bill % not found', p_bill_id;
  end if;
  if r.total_amount is null then
    raise exception 'bill % has no amount yet; it cannot be announced', r.bill_no;
  end if;

  msg := s.sms_template;
  msg := replace(msg, '{name}',             r.first_name || ' ' || r.last_name);
  msg := replace(msg, '{amount}',           to_char(r.total_amount, 'FM999,999,990.00'));
  msg := replace(msg, '{month}',            r.cycle_label);
  msg := replace(msg, '{due_date}',         to_char(r.due_date, 'FMMon DD, YYYY'));
  msg := replace(msg, '{account_no}',       r.consumer_no);
  msg := replace(msg, '{previous_reading}', to_char(r.previous_reading, 'FM999,999,990.00'));
  msg := replace(msg, '{current_reading}',  to_char(r.current_reading,  'FM999,999,990.00'));
  msg := replace(msg, '{usage}',            to_char(r.consumption,      'FM999,999,990.00'));
  return msg;
end $$;


-- ---------------------------------------------------------------------
-- SYS-04: queue a notification.
--
-- A consumer with no contact number on an SMS channel produces a FAILED
-- row, never a missing one. Push has no such dependency.
-- ---------------------------------------------------------------------
create or replace function fn_queue_notification(
  p_consumer_id      uuid,
  p_notif_type       notification_type,
  p_channel          notification_channel,
  p_message          text,
  p_bill_id          uuid default null,
  p_disconnection_id uuid default null,
  p_cycle_id         uuid default null
) returns uuid
language plpgsql as $$
declare
  v_contact text;
  v_id      uuid;
begin
  select contact_number into v_contact from consumers where id = p_consumer_id;

  insert into notifications (
    consumer_id, billing_cycle_id, bill_id, disconnection_id,
    notif_type, channel, message_content, status, failed_reason
  ) values (
    p_consumer_id, p_cycle_id, p_bill_id, p_disconnection_id,
    p_notif_type, p_channel, p_message,
    (case when p_channel = 'sms' and v_contact is null then 'failed' else 'pending' end)::notification_status,
    case when p_channel = 'sms' and v_contact is null
         then 'No contact number on file for this consumer' end
  )
  on conflict do nothing
  returning id into v_id;

  return v_id;
end $$;


-- =====================================================================
-- FR-21a — Meter Reader records a reading. An UNPRICED bill is created.
--
-- No rate lookup, no arithmetic on money, and NO notification: the
-- consumer cannot act on a reading, so telling them about it would only
-- announce a number that does not exist yet (FR-13).
--
-- SECURITY INVOKER on purpose: RLS still applies, so a Meter Reader
-- cannot read a consumer outside their area by calling this directly.
-- =====================================================================
create or replace function fn_record_meter_reading(
  p_consumer_id     uuid,
  p_current_reading numeric,
  p_captured_at     timestamptz default now(),
  p_client_uuid     uuid default gen_random_uuid()
) returns uuid
language plpgsql as $$
declare
  v_consumer     consumers%rowtype;
  v_cycle        billing_cycles%rowtype;
  v_prev         numeric(12,2);
  v_reading      meter_readings%rowtype;
  v_existing     uuid;
  v_reading_date date;
  v_bill_id      uuid;
begin
  -- MTR-12: idempotent sync. A retried upload returns the original bill.
  select b.id into v_existing
    from meter_readings mr join bills b on b.meter_reading_id = mr.id
   where mr.client_uuid = p_client_uuid;
  if v_existing is not null then
    return v_existing;
  end if;

  -- Deliberately NOT `for update`, and it must stay that way.
  --
  -- Under RLS, `select ... for update` also checks the UPDATE policy's USING
  -- clause, because locking a row requires permission to update it.
  -- `consumers_admin_update` is admin-only, so a lock here makes this whole
  -- function fail for the Meter Reader - the one role allowed to call it.
  -- The symptom is baffling: the reader can select the household one moment
  -- and be told 'not found or not visible to you' the next.
  --
  -- Nothing below updates the consumer, so there is nothing to lock.
  -- The locks in fn_post_bill_amount and fn_record_payment are different and
  -- must stay: they are on `bills`, whose update policy covers admin and
  -- cashier, and the one in fn_record_payment guards against two cashiers
  -- settling the same bill at once.
  select * into v_consumer from consumers where id = p_consumer_id;
  if not found then
    raise exception 'Consumer % not found or not visible to you', p_consumer_id
      using errcode = 'no_data_found';
  end if;
  if v_consumer.account_status <> 'active' then
    raise exception 'Consumer % is not active', v_consumer.consumer_no;
  end if;

  v_reading_date := fn_ph_today(p_captured_at);          -- SYS-07
  v_cycle := fn_ensure_billing_cycle(v_reading_date);    -- DOM-01

  -- FR-23: reject a second READING in the same cycle, with a message the
  -- Meter Reader can act on. The unique constraint is the real guarantee;
  -- this is the friendly error.
  if exists (select 1 from meter_readings
              where consumer_id = p_consumer_id and billing_cycle_id = v_cycle.id) then
    raise exception 'Consumer % has already been read for % %',
      v_consumer.consumer_no,
      to_char(v_cycle.period_start, 'FMMonth'), v_cycle.cycle_year
      using errcode = 'unique_violation';
  end if;

  -- MTR-08 / DOM-02: previous reading, or zero when there is no history.
  select mr.current_reading into v_prev
    from meter_readings mr
    join billing_cycles bc on bc.id = mr.billing_cycle_id
   where mr.consumer_id = p_consumer_id
   order by bc.period_start desc
   limit 1;
  v_prev := coalesce(v_prev, 0);

  if p_current_reading < v_prev then
    raise exception 'Present reading (%) is lower than the previous reading (%) for consumer %',
      p_current_reading, v_prev, v_consumer.consumer_no;
  end if;

  insert into meter_readings (
    consumer_id, billing_cycle_id, previous_reading, current_reading,
    reading_date, captured_at, recorded_by, client_uuid
  ) values (
    p_consumer_id, v_cycle.id, v_prev, p_current_reading,
    v_reading_date, p_captured_at, app.current_user_id(), p_client_uuid
  ) returning * into v_reading;

  -- The bill is born UNPRICED: total_amount, due_date and priced_at all NULL.
  insert into bills (
    bill_no, consumer_id, billing_cycle_id, meter_reading_id, consumption,
    generated_at, generated_by
  ) values (
    'BA-' || to_char(v_cycle.period_start, 'YYYYMM') || '-'
          || lpad(nextval('bill_no_seq')::text, 6, '0'),
    p_consumer_id, v_cycle.id, v_reading.id, v_reading.consumption,
    p_captured_at, app.current_user_id()
  ) returning id into v_bill_id;

  return v_bill_id;
end $$;


-- =====================================================================
-- FR-21b — Admin posts the amount the cooperative returned, rounded up to
-- the next whole peso whenever it contains centavos.
--
-- This is the moment a bill becomes payable, and the moment the consumer
-- is told about it (FR-13). The mockup: "Posting sends the consumer's
-- bill-ready alert automatically."
--
-- The alert goes by PUSH, not SMS. Objective 3 reserves SMS for overdue
-- and disconnection notices, because SMS costs money per message and a
-- bill-ready alert is the highest-volume message the system sends.
--
-- Superseded by 14_bill_sms.sql, which redefines this function: every
-- household now gets the bill by text as well, so a keypad phone is not
-- left out.
-- =====================================================================
create or replace function fn_post_bill_amount(
  p_bill_id    uuid,
  p_amount     numeric,
  p_due_date   date,
  p_posted_at  timestamptz default now()
) returns uuid
language plpgsql as $$
declare
  s        settings%rowtype;
  v_bill   bills%rowtype;
  v_notif  uuid;
begin
  if app.current_user_id() is not null and not app.is_admin() then
    raise exception 'Only an Admin may post a bill amount';
  end if;

  select * into s from settings where id = 1;

  select * into v_bill from bills where id = p_bill_id for update;
  if not found then
    raise exception 'Bill % not found or not visible to you', p_bill_id;
  end if;
  if v_bill.total_amount is not null then
    raise exception 'Bill % already has an amount of %; it cannot be re-posted',
      v_bill.bill_no, v_bill.total_amount;
  end if;
  if p_amount is null or p_amount <= 0 then
    raise exception 'The amount due must be greater than zero';
  end if;
  if p_due_date is null then
    raise exception 'A due date must be supplied with the amount';
  end if;
  if p_due_date < fn_ph_today(p_posted_at) then
    raise exception 'The due date (%) is already in the past', p_due_date;
  end if;

  update bills
     set total_amount = ceil(p_amount),
         due_date     = p_due_date,
         priced_at    = p_posted_at,
         priced_by    = app.current_user_id()
   where id = p_bill_id;

  -- FR-13: the bill-ready alert fires HERE, not at capture.
  v_notif := fn_queue_notification(
    v_bill.consumer_id, 'bill_ready', s.billready_channel,
    fn_render_bill_message(p_bill_id), p_bill_id, null, v_bill.billing_cycle_id
  );

  return v_notif;
end $$;


-- =====================================================================
-- FR-30 / CSH-04 — Cashier settles one or more PAYABLE bills.
--
-- One cash handover produces ONE transaction carrying ONE official
-- receipt number, plus one allocation line per bill settled. Unpriced
-- bills are refused: there is no amount to collect against.
-- =====================================================================
create or replace function fn_record_payment(
  p_bill_ids      uuid[],
  p_amounts       numeric[],
  p_cash_tendered numeric default null,
  p_paid_at       timestamptz default now(),
  p_client_uuid   uuid default null
) returns uuid
language plpgsql as $$
declare
  v_txn_id      uuid;
  v_consumer_id uuid;
  v_area_id     uuid;
  v_consumer_no text;
  v_last        text;
  v_total       numeric(12,2) := 0;
  v_bill        bills%rowtype;
  v_amount      numeric(12,2);
  v_seq         bigint;
  v_receipt     text;
  i             int;
begin
  -- Cashiers record payments offline; a retried sync must not double-credit.
  if p_client_uuid is not null then
    select id into v_txn_id from payment_transactions where client_uuid = p_client_uuid;
    if v_txn_id is not null then
      return v_txn_id;
    end if;
  end if;

  if p_bill_ids is null or array_length(p_bill_ids, 1) is null then
    raise exception 'No bills were selected for payment';
  end if;
  if array_length(p_bill_ids, 1) <> array_length(p_amounts, 1) then
    raise exception 'Each selected bill needs exactly one amount';
  end if;

  -- Validate and lock every bill BEFORE writing anything.
  for i in 1 .. array_length(p_bill_ids, 1) loop
    select * into v_bill from bills where id = p_bill_ids[i] for update;
    if not found then
      raise exception 'Bill % not found or not visible to you', p_bill_ids[i];
    end if;

    -- FR-30: "Unpriced bills cannot be settled."
    if v_bill.total_amount is null then
      raise exception
        'Bill % has no amount yet — the cooperative has not returned it. It cannot be paid.',
        v_bill.bill_no;
    end if;

    v_amount := round(p_amounts[i], 2);
    if v_amount <= 0 then
      raise exception 'Payment amount for bill % must be greater than zero', v_bill.bill_no;
    end if;
    if v_amount > v_bill.balance then
      raise exception 'Payment of % exceeds the outstanding balance of % on bill %',
        v_amount, v_bill.balance, v_bill.bill_no;
    end if;

    if v_consumer_id is null then
      v_consumer_id := v_bill.consumer_id;
      select area_id, consumer_no, last_name into v_area_id, v_consumer_no, v_last
        from consumers where id = v_consumer_id;
    elsif v_consumer_id <> v_bill.consumer_id then
      raise exception 'All bills in one transaction must belong to the same consumer';
    end if;

    v_total := v_total + v_amount;
  end loop;

  if p_cash_tendered is not null and p_cash_tendered < v_total then
    raise exception 'Cash tendered (%) is less than the total due (%)', p_cash_tendered, v_total;
  end if;

  -- ONE receipt number for the whole handover.
  v_seq     := nextval('receipt_no_seq');
  v_receipt := 'BIEC-' || to_char(p_paid_at at time zone 'Asia/Manila', 'YYYY-MM')
               || '-' || lpad(v_seq::text, 6, '0');

  insert into payment_transactions (
    receipt_no, verification_code, consumer_id, area_id, cashier_id,
    total_collected, cash_tendered, change_due, paid_at, client_uuid
  ) values (
    v_receipt,
    -- "BIEC-4471-VB-1975" — short code the consumer scans at the counter.
    'BIEC-' || v_seq::text || '-'
      || upper(left(regexp_replace(coalesce(v_last, 'XX'), '[^A-Za-z]', '', 'g') || 'XX', 2))
      || '-' || to_char(v_total, 'FM99999999'),
    v_consumer_id, v_area_id, app.current_user_id(),
    v_total, p_cash_tendered,
    case when p_cash_tendered is null then null else p_cash_tendered - v_total end,
    p_paid_at, p_client_uuid
  ) returning id into v_txn_id;

  for i in 1 .. array_length(p_bill_ids, 1) loop
    v_amount := round(p_amounts[i], 2);
    insert into payments (
      transaction_id, bill_id, consumer_id, amount_paid, payment_method, paid_at, received_by
    ) values (
      v_txn_id, p_bill_ids[i], v_consumer_id, v_amount, 'cash', p_paid_at, app.current_user_id()
    );
    -- The trigger recomputes balance and status (paid / partial).
    update bills set amount_paid = amount_paid + v_amount where id = p_bill_ids[i];
  end loop;

  return v_txn_id;
end $$;


-- =====================================================================
-- MTR-15 / DOM-05 / SYS-04 — issue a disconnection notice.
-- =====================================================================
create or replace function fn_issue_disconnection_notice(
  p_consumer_id uuid,
  p_reason      text default null,
  p_served_at   timestamptz default now(),
  p_client_uuid uuid default gen_random_uuid()
) returns uuid
language plpgsql as $$
declare
  v_existing  uuid;
  v_notice_id uuid;
  v_lawful    timestamptz;
  v_consumer  consumers%rowtype;
  v_reason    text;
  v_msg       text;
  v_notice_no text;
begin
  select id into v_existing from disconnection_notices where client_uuid = p_client_uuid;
  if v_existing is not null then
    return v_existing;                                     -- MTR-12 idempotent
  end if;

  select * into v_consumer from consumers where id = p_consumer_id;
  if not found then
    raise exception 'Consumer % not found or not visible to you', p_consumer_id;
  end if;

  -- A notice is only lawful against an account that is actually overdue.
  -- An unpriced bill has no due date and can never be overdue, so the
  -- threshold is computable only over payable bills.
  if not exists (
    select 1 from bills
     where consumer_id = p_consumer_id
       and total_amount is not null
       and status <> 'paid'
       and due_date < fn_ph_today(p_served_at)
  ) then
    raise exception 'Consumer % has no overdue bill; a disconnection notice cannot be issued',
      v_consumer.consumer_no;
  end if;

  v_lawful := fn_earliest_lawful_disconnection(p_served_at);
  v_reason := coalesce(nullif(trim(p_reason), ''), 'Unpaid electricity bill');

  -- "DN-2026-0819-0033"
  v_notice_no := 'DN-' || to_char(p_served_at at time zone 'Asia/Manila', 'YYYY-MMDD')
                 || '-' || lpad(nextval('notice_no_seq')::text, 4, '0');

  insert into disconnection_notices (
    notice_no, consumer_id, reason, served_at, earliest_lawful_at, issued_by, client_uuid
  ) values (
    v_notice_no, p_consumer_id, v_reason, p_served_at, v_lawful,
    app.current_user_id(), p_client_uuid
  ) returning id into v_notice_id;

  v_msg := format(
    'NOTICE %s: %s %s, your BillAlert account %s has an unpaid balance. Reason: %s. '
    || 'Please settle before %s to avoid disconnection.',
    v_notice_no, v_consumer.first_name, v_consumer.last_name, v_consumer.consumer_no, v_reason,
    to_char(v_lawful at time zone 'Asia/Manila', 'FMMon DD, YYYY HH12:MI AM')
  );

  -- Objective 3: disconnection notices go by SMS, so they reach a consumer
  -- who does not open the app.
  perform fn_queue_notification(
    p_consumer_id, 'disconnection', 'sms', v_msg, null, v_notice_id, null
  );

  return v_notice_id;
end $$;


-- ---------------------------------------------------------------------
-- ADM-17: record the outcome of a notice and close it (clears CON-04).
-- ---------------------------------------------------------------------
create or replace function fn_close_disconnection_notice(
  p_notice_id uuid,
  p_outcome   notice_status,
  p_notes     text default null
) returns void
language plpgsql as $$
begin
  if p_outcome not in ('settled','cancelled','referred') then
    raise exception 'Outcome must be settled, cancelled, or referred';
  end if;

  update disconnection_notices
     set status        = p_outcome,
         closed_at     = now(),
         closed_by     = app.current_user_id(),
         outcome_notes = p_notes
   where id = p_notice_id and status = 'active';

  if not found then
    raise exception 'Notice % not found or already closed', p_notice_id;
  end if;
end $$;

comment on function fn_close_disconnection_notice is
  'ADM-17 scope note: "referred" records a handover to cooperative personnel. '
  'BillAlert never authorises, schedules, or executes a disconnection.';
