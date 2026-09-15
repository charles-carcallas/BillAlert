-- =====================================================================
-- BillAlert — 01_schema.sql
-- Core data model: schemas, enums, tables, constraints, indexes.
--
-- Target: PostgreSQL 15+ (Supabase). Also runs on a plain local Postgres
-- so the team can test without touching the hosted project.
--
-- Run order: 01_schema → 02_functions → 03_views → 04_rls → 05_seed → 06_tests
--
-- ---------------------------------------------------------------------
-- THE ONE THING TO UNDERSTAND BEFORE READING THE BILLING TABLES
--
-- BillAlert does NOT compute bills. The Meter Reader captures a reading;
-- BOHECO I's central billing office returns the peso amount roughly a
-- week later; the Admin transcribes it. So a bill is born UNPRICED and
-- becomes payable only when an amount and a due date are posted against
-- it. There is no tariff, no rate table, and no arithmetic on money
-- anywhere in this schema.
--
-- That seven-day window — where a reading exists but no amount does — is
-- the exact problem BillAlert was built to solve. It is modelled here as
-- the `unpriced` bill status.
--
-- See BillAlert_FR_Revision_Billing_Lag.md (FR-21a / FR-21b).
-- =====================================================================

create extension if not exists pgcrypto;   -- gen_random_uuid()

create schema if not exists app;           -- helper functions (auth/session context)

-- ---------------------------------------------------------------------
-- Enumerated types
-- ---------------------------------------------------------------------
do $$ begin
  create type user_role            as enum ('admin','meter_reader','cashier','consumer');
  create type account_status       as enum ('pending','active','inactive');
  -- 'unpriced' = a reading exists, the cooperative has not returned an amount yet.
  create type bill_status          as enum ('unpriced','unpaid','partial','paid');
  create type notice_status        as enum ('active','settled','cancelled','referred');
  create type notification_type    as enum ('bill_ready','pre_due_reminder','overdue','disconnection');
  create type notification_channel as enum ('sms','push');
  create type notification_status  as enum ('pending','sent','failed');
exception when duplicate_object then null;
end $$;


-- =====================================================================
-- REFERENCE DATA
-- =====================================================================

-- ADM-10 / DOM-08: service areas.
--
-- SCOPE (Phase 1 final, §4): BillAlert serves ONE barangay — Tubod, Clarin,
-- Bohol — deployed across FOUR service areas. Each area has its own Area
-- President (Admin), Meter Reader and Cashier, and serves its own consumers.
--
-- An area is NOT a purok. Puroks subdivide the barangay independently of the
-- service areas — the mockup's Area 3 roster contains consumers from Puroks
-- 1, 2, 3 and 4 — so a purok is recorded per consumer (consumers.purok) and
-- is display/sorting information, not an access boundary. The ACCESS boundary
-- is the service area (FR-19, FR-28, FR-34).
create table if not exists areas (
  id           uuid primary key default gen_random_uuid(),
  code         text not null unique,
  name         text not null,
  is_active    boolean not null default true,
  created_at   timestamptz not null default now()
);

-- DOM-05: official Philippine holidays, used to compute the lawful disconnection window.
create table if not exists ph_holidays (
  holiday_date date primary key,
  name         text not null,
  holiday_type text not null default 'regular' check (holiday_type in ('regular','special'))
);

-- ADM-11, ADM-15, ADM-16: system-wide configuration. Single row, enforced.
-- No screen edits these (the "fixed configuration" limitation) — they are
-- seeded and read.
create table if not exists settings (
  id                       smallint primary key default 1 check (id = 1),
  -- Printed on the login screen and every receipt.
  cooperative_name         text not null default 'Bohol I Electric Cooperative',
  -- DOM-07: the single barangay this deployment covers. Not selectable anywhere.
  service_province         text not null default 'Bohol',
  service_city_mun         text not null default 'Clarin',
  service_barangay         text not null default 'Tubod',
  -- PSGC 10-digit codes. Province and municipality are confirmed against the
  -- PSA PSGC listing for Bohol; the barangay code is derived from the
  -- municipality code plus Tubod's barangay number and should be confirmed
  -- against the PSA barangay listing before it is printed on a real bill.
  service_province_psgc    text not null default '0701200000',
  service_city_mun_psgc    text not null default '0701214000',
  service_barangay_psgc    text not null default '0701214023',
  -- ADM-11 billing cycle. The mockup shows "15 July 2026 – 14 August 2026".
  -- NOTE: there is no days_to_due. The due date arrives from the cooperative
  -- with the amount (FR-21b); BillAlert never derives one.
  -- A cycle is a calendar month: an August cycle covers August. This was
  -- 15 because the mockup shows "15 July 2026 - 14 August 2026", which
  -- makes the "August" cycle cover half of September while every screen
  -- prints "August 2026" over it. Changed deliberately — see
  -- 08_calendar_cycles.sql.
  cycle_start_day          smallint not null default 1  check (cycle_start_day between 1 and 28),
  -- ADM-16 automated reminder schedule.
  -- Objective 3: push carries no per-message cost, so reminders go by push
  -- and SMS is reserved for overdue and disconnection. Revised in
  -- 14_bill_sms.sql: bill-ready alerts also go by text.
  predue_reminder_days     smallint not null default 3  check (predue_reminder_days between 0 and 30),
  predue_channel           notification_channel not null default 'push',
  billready_channel        notification_channel not null default 'push',
  overdue_enabled          boolean not null default true,
  overdue_days_after       smallint not null default 3  check (overdue_days_after between 0 and 60),
  overdue_channel          notification_channel not null default 'sms',
  -- ADM-14 message template
  sms_template             text not null default
    'Hi {name}, your BillAlert bill for {month} is PHP {amount}. Due on {due_date}. Account {account_no}.',
  -- ADM-15 batch policy
  batch_enabled            boolean  not null default true,
  batch_size               smallint not null default 20 check (batch_size between 1 and 200),
  batch_delay_ms           integer  not null default 1000 check (batch_delay_ms between 0 and 60000),
  require_batch_confirm    boolean  not null default true,
  -- DOM-05 internal courtesy period, separate from the 48h statutory minimum
  courtesy_notice_hours    smallint not null default 48 check (courtesy_notice_hours >= 48),
  disconnection_window_start_hour smallint not null default 8  check (disconnection_window_start_hour between 0 and 23),
  disconnection_window_end_hour   smallint not null default 15 check (disconnection_window_end_hour between 1 and 23),
  updated_at               timestamptz not null default now()
);
comment on column settings.courtesy_notice_hours is
  'DOM-05. 48h is the ERC Magna Carta statutory MINIMUM and the floor enforced by the CHECK. '
  'A longer cooperative courtesy period is set here; it never lowers the statutory figure.';

-- ADM-12/13: SMS gateway providers. Credentials are NOT stored here.
create table if not exists sms_providers (
  id                uuid primary key default gen_random_uuid(),
  provider_name     text not null unique,
  is_active         boolean not null default false,
  auth_scheme       text,
  auth_header_name  text,
  payload_template  text,
  base_url          text,
  credential_ref    text,
  last_test_at      timestamptz,
  last_test_success boolean,
  last_test_detail  text
);
comment on column sms_providers.credential_ref is
  'SECURITY: the NAME of a secret held in Supabase Vault / Edge Function env, never the secret itself. '
  'Phase 2 rubric: "no hardcoded credentials or API keys in source code" — this column is why.';

create unique index if not exists uq_sms_provider_active
  on sms_providers ((true)) where is_active;


-- ---------------------------------------------------------------------
-- Philippine mobile number normalisation.
--
-- Every number in the mockup is spaced — "+63 917 555 0142". Rather than
-- loosen the format check and store whatever was typed, numbers are
-- normalised to E.164 on write and the strict CHECK validates the stored
-- value. The SMS gateway then always receives a clean number.
-- ---------------------------------------------------------------------
create or replace function fn_normalize_ph_mobile(p_raw text) returns text
language plpgsql immutable as $$
declare d text;
begin
  if p_raw is null or btrim(p_raw) = '' then return null; end if;
  d := regexp_replace(p_raw, '[^0-9+]', '', 'g');   -- drop spaces, dashes, parens
  if d ~ '^\+639[0-9]{9}$'  then return d;                      end if;
  if d ~ '^639[0-9]{9}$'    then return '+' || d;               end if;
  if d ~ '^09[0-9]{9}$'     then return '+63' || substring(d from 2); end if;
  if d ~ '^9[0-9]{9}$'      then return '+63' || d;             end if;
  return p_raw;   -- unrecognised: returned unchanged so the CHECK rejects it
end $$;


-- =====================================================================
-- IDENTITY
-- =====================================================================

-- GEN-01..GEN-12. One row per person who can log in, of any role.
create table if not exists profiles (
  id                   uuid primary key default gen_random_uuid(),
  user_code            text not null unique,
  -- The login screen shows "Username: ledesman.dormal", and MTR-04 derives a
  -- username from the consumer's first name. Supabase Auth signs in with an
  -- email or a phone, so the app resolves this username to the account's
  -- credential before calling signInWithPassword.
  username             text not null unique,
  first_name           text not null,
  last_name            text not null,
  role                 user_role not null,
  -- "Area President · Admin" in the mockup: a job title, distinct from the
  -- four system roles.
  position_title       text,
  contact_number       text,
  area_id              uuid references areas(id),
  account_status       account_status not null default 'pending',
  must_change_password boolean not null default true,   -- GEN-04
  theme_preference     text not null default 'system' check (theme_preference in ('system','light','dark')), -- GEN-12
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  -- FR-31 / Target Users: each of Tubod's four service areas has its own
  -- Area President (the Admin), Meter Reader and Cashier. Admin is therefore
  -- area-scoped like the other staff roles; only consumers are not.
  constraint profiles_area_by_role check (
    (role in ('admin','meter_reader','cashier') and area_id is not null)
    or (role = 'consumer')
  ),
  constraint profiles_contact_format check (
    contact_number is null or contact_number ~ '^\+639[0-9]{9}$'
  )
);

-- FR-31: "one active Meter Reader, one active Cashier and one active Admin
-- per service area." The mockup renders exactly this rule: "Assignment blocked
-- — area already has a Meter Reader. Ledesman Dormal is the active Meter
-- Reader for Area 3 — Tubod."
create unique index if not exists uq_area_one_active_staff_per_role
  on profiles (area_id, role)
  where account_status = 'active' and role in ('admin','meter_reader','cashier');

do $$ begin
  if exists (select 1 from information_schema.tables
             where table_schema = 'auth' and table_name = 'users') then
    alter table profiles
      add constraint profiles_id_fkey
      foreign key (id) references auth.users(id) on delete cascade;
  end if;
exception when duplicate_object then null;
end $$;


-- MTR-03/04/06, ADM-03: the consumer record.
create table if not exists consumers (
  id                uuid primary key default gen_random_uuid(),
  consumer_no       text not null unique,                -- "2019-0917-TUB"
  profile_id        uuid unique references profiles(id) on delete set null,
  first_name        text not null,
  last_name         text not null,
  contact_number    text,
  -- Nullable: the New Consumer screen collects only name, mobile, purok and
  -- barangay. The meter serial ("BIEC-08319") is attached when the meter is
  -- commissioned. A partial unique index keeps real serials unique without
  -- forcing one at registration.
  meter_serial_no   text,
  area_id           uuid not null references areas(id),
  -- MTR-05, revised: the barangay is fixed for the deployment and held in
  -- `settings`. What varies per consumer is the purok — "Purok 3" in the mockup.
  purok             text,
  account_status    account_status not null default 'active',
  created_by        uuid references profiles(id),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  constraint consumers_contact_format check (
    contact_number is null or contact_number ~ '^\+639[0-9]{9}$'
  )
);
create unique index if not exists uq_consumers_meter_serial
  on consumers (meter_serial_no) where meter_serial_no is not null;
create index if not exists idx_consumers_area   on consumers(area_id);
create index if not exists idx_consumers_status on consumers(account_status);
create index if not exists idx_consumers_name   on consumers(last_name, first_name);

-- Normalise phone numbers on the way in, for both tables.
create or replace function fn_normalize_contact() returns trigger
language plpgsql as $$
begin
  new.contact_number := fn_normalize_ph_mobile(new.contact_number);
  return new;
end $$;

drop trigger if exists trg_profiles_normalize_contact on profiles;
create trigger trg_profiles_normalize_contact
  before insert or update of contact_number on profiles
  for each row execute function fn_normalize_contact();

drop trigger if exists trg_consumers_normalize_contact on consumers;
create trigger trg_consumers_normalize_contact
  before insert or update of contact_number on consumers
  for each row execute function fn_normalize_contact();


-- =====================================================================
-- READINGS AND BILLS
-- =====================================================================

-- DOM-01. Cycles are stored as ROWS, not recomputed from dates on every
-- query. This turns MTR-10 ("never read a consumer twice in a cycle")
-- from a race-prone date-range check into a one-column unique constraint —
-- which matters because offline sync makes duplicate submissions normal
-- traffic rather than an edge case.
create table if not exists billing_cycles (
  id            uuid primary key default gen_random_uuid(),
  cycle_year    smallint not null,
  cycle_month   smallint not null check (cycle_month between 1 and 12),
  period_start  date not null,
  period_end    date not null,
  is_closed     boolean not null default false,
  created_at    timestamptz not null default now(),
  constraint billing_cycles_period_valid check (period_end >= period_start),
  constraint billing_cycles_ym_uniq unique (cycle_year, cycle_month),
  constraint billing_cycles_no_overlap
    exclude using gist (daterange(period_start, period_end, '[]') with &&)
);

-- FR-21a / MTR-09, MTR-11, MTR-12, DOM-02.
-- The reader's job ends here. No money is involved.
create table if not exists meter_readings (
  id                uuid primary key default gen_random_uuid(),
  consumer_id       uuid not null references consumers(id) on delete cascade,
  billing_cycle_id  uuid not null references billing_cycles(id),
  previous_reading  numeric(12,2) not null default 0 check (previous_reading >= 0),  -- MTR-08
  current_reading   numeric(12,2) not null check (current_reading >= 0),
  consumption       numeric(12,2) generated always as (current_reading - previous_reading) stored, -- DOM-02
  reading_date      date not null,
  -- MTR-12: the server attributes the record to CAPTURE time, not sync time.
  captured_at       timestamptz not null default now(),
  synced_at         timestamptz not null default now(),
  recorded_by       uuid references profiles(id),
  -- MTR-12: idempotency key minted on the device. A retried sync cannot
  -- duplicate a reading.
  client_uuid       uuid not null unique,
  created_at        timestamptz not null default now(),
  constraint meter_readings_not_backwards check (current_reading >= previous_reading),
  constraint meter_readings_one_per_cycle unique (consumer_id, billing_cycle_id)   -- FR-23
);
create index if not exists idx_readings_consumer_cycle on meter_readings(consumer_id, billing_cycle_id);
create index if not exists idx_readings_cycle          on meter_readings(billing_cycle_id);

-- FR-21a creates the bill UNPRICED; FR-21b prices it.
--
-- Why the bill is born with the reading rather than created later at
-- pricing: it gives the Consumer's bill screen something to show during
-- the seven-day window (FR-25), and NFR-05 already assumes offline sync
-- can create bills — which only holds if the bill arrives with the reading.
create table if not exists bills (
  id                uuid primary key default gen_random_uuid(),
  bill_no           text not null unique,
  consumer_id       uuid not null references consumers(id) on delete cascade,
  billing_cycle_id  uuid not null references billing_cycles(id),
  meter_reading_id  uuid not null unique references meter_readings(id) on delete cascade,
  consumption       numeric(12,2) not null check (consumption >= 0),

  -- ---- posted by the Admin from the cooperative's figure (FR-21b) ----
  -- NULL until then. BillAlert never derives either value.
  total_amount      numeric(12,2) check (total_amount is null or total_amount >= 0),
  due_date          date,
  priced_at         timestamptz,
  priced_by         uuid references profiles(id),

  amount_paid       numeric(12,2) not null default 0 check (amount_paid >= 0),
  balance           numeric(12,2),                             -- maintained by trigger
  status            bill_status not null default 'unpriced',   -- maintained by trigger
  generated_at      timestamptz not null default now(),
  generated_by      uuid references profiles(id),

  constraint bills_one_per_cycle unique (consumer_id, billing_cycle_id),
  -- A bill is either fully unpriced or fully priced. No half state.
  constraint bills_pricing_consistent check (
    (total_amount is null and due_date is null and priced_at is null)
    or (total_amount is not null and due_date is not null and priced_at is not null)
  ),
  -- FR-30: an unpriced bill cannot have been paid against.
  constraint bills_unpriced_unpaid check (total_amount is not null or amount_paid = 0)
);
create index if not exists idx_bills_consumer    on bills(consumer_id);
create index if not exists idx_bills_cycle       on bills(billing_cycle_id);
create index if not exists idx_bills_status_due  on bills(status, due_date);
create index if not exists idx_bills_outstanding on bills(due_date) where status not in ('paid','unpriced');
-- The Admin's "readings awaiting an amount" queue.
create index if not exists idx_bills_unpriced    on bills(billing_cycle_id) where status = 'unpriced';

create or replace function fn_bills_sync_derived() returns trigger
language plpgsql as $$
begin
  if new.total_amount is null then
    new.balance := null;
    new.status  := 'unpriced';
  else
    new.balance := new.total_amount - new.amount_paid;
    new.status  := case
                     when new.amount_paid >= new.total_amount then 'paid'::bill_status
                     when new.amount_paid > 0                 then 'partial'::bill_status
                     else 'unpaid'::bill_status
                   end;
  end if;
  return new;
end $$;

drop trigger if exists trg_bills_sync_derived on bills;
create trigger trg_bills_sync_derived
  before insert or update of amount_paid, total_amount on bills
  for each row execute function fn_bills_sync_derived();


-- =====================================================================
-- PAYMENTS
-- =====================================================================

-- CSH-04 / FR-30. One cash handover = one transaction = ONE official
-- receipt, covering however many bills it settles.
--
-- DECISION (Sep 2026): the receipt number lives HERE, not on `payments`.
-- The mockup's Consumer History shows the same OR number against June,
-- July and August, and the receipt prints "Total paid / Cash tendered /
-- Change" — all facts about the handover, not about any one bill. SRS
-- CSH-04's "a distinct receipt number for each bill" is superseded.
create table if not exists payment_transactions (
  id                 uuid primary key default gen_random_uuid(),
  receipt_no         text not null unique,          -- "BIEC-2026-08-004471"
  verification_code  text not null unique,          -- "BIEC-4471-VB-1975", scanned at the counter
  consumer_id        uuid not null references consumers(id),
  area_id            uuid not null references areas(id),
  cashier_id         uuid references profiles(id),
  total_collected    numeric(12,2) not null check (total_collected > 0),
  cash_tendered      numeric(12,2) check (cash_tendered is null or cash_tendered >= total_collected),
  change_due         numeric(12,2) check (change_due is null or change_due >= 0),
  paid_at            timestamptz not null default now(),
  -- Cashiers record payments offline too ("3 payments waiting to sync").
  client_uuid        uuid unique,
  created_at         timestamptz not null default now()
);
create index if not exists idx_paytxn_paid_at  on payment_transactions(paid_at desc);
create index if not exists idx_paytxn_area     on payment_transactions(area_id);
create index if not exists idx_paytxn_consumer on payment_transactions(consumer_id, paid_at desc);

-- One row per bill settled by a transaction: how much of the handover
-- went where. These are allocation lines, not receipts.
create table if not exists payments (
  id              uuid primary key default gen_random_uuid(),
  transaction_id  uuid not null references payment_transactions(id) on delete cascade,
  bill_id         uuid not null references bills(id),
  consumer_id     uuid not null references consumers(id),
  amount_paid     numeric(12,2) not null check (amount_paid > 0),
  -- CSH-05 / DOM-06: cash is the ONLY method, constrained at the database.
  payment_method  text not null default 'cash' check (payment_method = 'cash'),
  paid_at         timestamptz not null default now(),
  received_by     uuid references profiles(id),
  created_at      timestamptz not null default now(),
  constraint payments_one_line_per_bill unique (transaction_id, bill_id)
);
create index if not exists idx_payments_bill     on payments(bill_id);
create index if not exists idx_payments_consumer on payments(consumer_id, paid_at desc);
create index if not exists idx_payments_txn      on payments(transaction_id);

create sequence if not exists receipt_no_seq start 4471;   -- matches the mockup's series
create sequence if not exists bill_no_seq    start 1;
create sequence if not exists notice_no_seq  start 33;


-- =====================================================================
-- DISCONNECTION
-- =====================================================================

-- MTR-15, ADM-17, DOM-05, CON-04.
create table if not exists disconnection_notices (
  id                  uuid primary key default gen_random_uuid(),
  notice_no           text not null unique,                  -- "DN-2026-0819-0033"
  consumer_id         uuid not null references consumers(id) on delete cascade,
  reason              text not null default 'Unpaid electricity bill',
  served_at           timestamptz not null default now(),    -- capture time, not sync time
  earliest_lawful_at  timestamptz not null,                  -- DOM-05, computed on insert
  status              notice_status not null default 'active',
  closed_at           timestamptz,
  closed_by           uuid references profiles(id),
  outcome_notes       text,
  issued_by           uuid references profiles(id),
  client_uuid         uuid not null unique,
  created_at          timestamptz not null default now(),
  constraint notice_closed_consistency check (
    (status = 'active' and closed_at is null)
    or (status <> 'active' and closed_at is not null)
  ),
  constraint notice_lawful_after_served check (earliest_lawful_at > served_at)
);
create unique index if not exists uq_one_active_notice_per_consumer
  on disconnection_notices (consumer_id) where status = 'active';
create index if not exists idx_notices_status on disconnection_notices(status, served_at desc);


-- =====================================================================
-- NOTIFICATIONS
-- =====================================================================

-- SYS-01..SYS-04, CON-05, MTR-16/17.
create table if not exists notifications (
  id                 uuid primary key default gen_random_uuid(),
  consumer_id        uuid not null references consumers(id) on delete cascade,
  billing_cycle_id   uuid references billing_cycles(id),
  bill_id            uuid references bills(id) on delete cascade,
  disconnection_id   uuid references disconnection_notices(id) on delete cascade,
  notif_type         notification_type not null,
  channel            notification_channel not null,
  message_content    text not null,
  status             notification_status not null default 'pending',
  failed_reason      text,
  retry_count        smallint not null default 0 check (retry_count between 0 and 3),
  sent_at            timestamptz,
  is_read            boolean not null default false,   -- CON-05
  read_at            timestamptz,
  created_at         timestamptz not null default now(),
  constraint notif_failure_has_reason check (status <> 'failed' or failed_reason is not null),
  constraint notif_sent_has_timestamp check (status <> 'sent' or sent_at is not null)
);
create index if not exists idx_notif_consumer  on notifications(consumer_id, created_at desc);
create index if not exists idx_notif_unread    on notifications(consumer_id) where not is_read;
create index if not exists idx_notif_retryable on notifications(status) where status in ('pending','failed');
create index if not exists idx_notif_cycle     on notifications(billing_cycle_id);

comment on constraint notif_failure_has_reason on notifications is
  'SYS-04: a consumer with no contact number produces a FAILED notification with a stated reason, '
  'never a missing row. The gap has to stay visible for follow-up.';

create unique index if not exists uq_notif_one_per_bill_type
  on notifications (bill_id, notif_type)
  where bill_id is not null and notif_type in ('bill_ready','pre_due_reminder','overdue');
