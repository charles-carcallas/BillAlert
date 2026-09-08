-- =====================================================================
-- BillAlert — 05_seed.sql
-- Reference data + a deterministic demo fixture.
--
-- The fixture UUIDs are fixed on purpose so 06_tests.sql can assert
-- against known rows and so every team member's local database looks
-- identical when comparing results.
--
-- Names and figures are drawn from the Figma mockup so a running database
-- matches the screens. They are FICTIONAL — do not present any of this as
-- real cooperative data.
--
-- SAFE TO RUN on a development project. Do NOT run the FIXTURE section
-- against a database holding real cooperative data.
-- =====================================================================

-- ---------------------------------------------------------------------
-- SETTINGS (ADM-11, ADM-14, ADM-15, ADM-16)
-- Service location: Barangay Tubod, Clarin, Bohol — one barangay, held
-- here rather than in a table, because it is the same for every consumer.
-- ---------------------------------------------------------------------
insert into settings (id) values (1) on conflict (id) do nothing;

-- ---------------------------------------------------------------------
-- NOTE: there is no rate table.
-- BillAlert does not compute bills; the cooperative returns the amount
-- and the Admin posts it (FR-21b). See BillAlert_FR_Revision_Billing_Lag.md.
-- ---------------------------------------------------------------------


-- ---------------------------------------------------------------------
-- PHILIPPINE HOLIDAYS (DOM-05)
--
-- Regular holidays with FIXED dates only. Movable holidays — Maundy
-- Thursday, Good Friday, Eid'l Fitr, Eid'l Adha, National Heroes Day —
-- are set by annual Presidential Proclamation and MUST be loaded from
-- the proclamation for each year. An incomplete table silently produces
-- an unlawful disconnection window, so treat this as a maintained table,
-- not a one-time seed.
-- ---------------------------------------------------------------------
insert into ph_holidays (holiday_date, name, holiday_type) values
  (date '2026-01-01','New Year''s Day','regular'),
  (date '2026-04-02','Maundy Thursday','regular'),
  (date '2026-04-03','Good Friday','regular'),
  (date '2026-04-09','Araw ng Kagitingan','regular'),
  (date '2026-05-01','Labor Day','regular'),
  (date '2026-06-12','Independence Day','regular'),
  (date '2026-08-31','National Heroes Day','regular'),
  (date '2026-11-30','Bonifacio Day','regular'),
  (date '2026-12-25','Christmas Day','regular'),
  (date '2026-12-30','Rizal Day','regular'),
  (date '2027-01-01','New Year''s Day','regular')
on conflict (holiday_date) do nothing;


-- ---------------------------------------------------------------------
-- SMS PROVIDERS (ADM-12) — configuration only, never credentials.
-- ---------------------------------------------------------------------
insert into sms_providers (provider_name, is_active, auth_scheme, auth_header_name, base_url, credential_ref) values
  ('Semaphore',           false, 'query_param', null,            'https://api.semaphore.co/api/v4/messages', 'SEMAPHORE_API_KEY'),
  ('httpSMS',             false, 'bearer',      'Authorization', 'https://api.httpsms.com/v1/messages/send',  'HTTPSMS_API_KEY'),
  ('TextBee',             false, 'header',      'x-api-key',     'https://api.textbee.dev/api/v1',            'TEXTBEE_API_KEY'),
  ('Android SMS Gateway', false, 'basic',       'Authorization', null,                                        'ANDROID_SMSGW_CREDS')
on conflict (provider_name) do nothing;


-- =====================================================================
-- FIXTURE — development and test data only
-- =====================================================================

-- The FOUR service areas of Barangay Tubod (Phase 1 §4, §5).
-- Each has one Area President (Admin), one Meter Reader and one Cashier.
-- Area 3 is the one the Figma mockup depicts.
insert into areas (id, code, name) values
  ('11111111-0000-0000-0000-000000000001','AREA-1','Area 1 — Tubod'),
  ('11111111-0000-0000-0000-000000000002','AREA-2','Area 2 — Tubod'),
  ('11111111-0000-0000-0000-00000000000a','AREA-3','Area 3 — Tubod'),
  ('11111111-0000-0000-0000-00000000000b','AREA-4','Area 4 — Tubod')
on conflict (id) do nothing;

-- Staff and admin profiles.
-- NOTE: on Supabase these ids must match the corresponding auth.users ids.
-- Passwords live in Supabase Auth (bcrypt) and never in this table — that
-- is deliberate, and is what the "no hardcoded credentials" criterion wants.
insert into profiles (id, user_code, username, first_name, last_name, role, position_title,
                      contact_number, area_id, account_status, must_change_password) values
  ('33333333-0000-0000-0000-000000000001','ADM-0003','mario.ombajin','Mario','Ombajin','admin','Area President',
   '+63 917 555 0101','11111111-0000-0000-0000-00000000000a','active', false),
  ('33333333-0000-0000-0000-000000000002','MTR-0001','ledesman.dormal','Ledesman','Dormal','meter_reader',null,
   '+63 917 555 0102','11111111-0000-0000-0000-00000000000a','active', false),
  ('33333333-0000-0000-0000-000000000003','CSH-0001','mercedita.gales','Mercedita','Gales','cashier',null,
   '+63 917 555 0103','11111111-0000-0000-0000-00000000000a','active', false),
  -- Area 4, used to prove the area boundary in the RLS tests — including
  -- that one Area President cannot read another area's consumers.
  ('33333333-0000-0000-0000-000000000004','MTR-0004','juan.delacruz','Juan','Dela Cruz','meter_reader',null,
   '+63 917 555 0104','11111111-0000-0000-0000-00000000000b','active', false),
  ('33333333-0000-0000-0000-000000000005','CSH-0004','maria.santos','Maria','Santos','cashier',null,
   '+63 917 555 0105','11111111-0000-0000-0000-00000000000b','active', false),
  ('33333333-0000-0000-0000-000000000006','ADM-0004','rosalinda.paña','Rosalinda','Pana','admin','Area President',
   '+63 917 555 0106','11111111-0000-0000-0000-00000000000b','active', false)
on conflict (id) do nothing;

-- Consumer login profiles (MTR-04 auto-provisioned).
insert into profiles (id, user_code, username, first_name, last_name, role, contact_number,
                      account_status, must_change_password) values
  ('44444444-0000-0000-0000-000000000001','CON-0001','virgilio.busalanan','Virgilio','Busalanan','consumer','+63 917 555 0142','active', true),
  ('44444444-0000-0000-0000-000000000002','CON-0002','elena.bongcaras','Elena','Bongcaras','consumer',      '+63 917 555 0201','active', true),
  ('44444444-0000-0000-0000-000000000003','CON-0003','rodel.amistad','Rodel','Amistad','consumer',          '+63 917 555 0202','active', true),
  ('44444444-0000-0000-0000-000000000004','CON-0004','teresita.lumayag','Teresita','Lumayag','consumer',     null,             'active', true),
  ('44444444-0000-0000-0000-000000000005','CON-0005','bienvenido.sarigumba','Bienvenido','Sarigumba','consumer','+63 917 555 0204','active', true),
  ('44444444-0000-0000-0000-000000000006','CON-0006','marilou.cagampang','Marilou','Cagampang','consumer',  '+63 917 555 0205','active', true),
  ('44444444-0000-0000-0000-000000000007','CON-0007','ben.aquino','Ben','Aquino','consumer',                '+63 917 555 0206','active', true)
on conflict (id) do nothing;

-- Consumers. Every one is in Barangay Tubod; only the purok varies.
-- CON-0004 (Teresita) deliberately has NO contact number, so SYS-04's
-- "record it as failed, do not omit it" rule has a subject to test.
insert into consumers (id, consumer_no, profile_id, first_name, last_name, contact_number,
                       meter_serial_no, area_id, purok, created_by) values
  ('55555555-0000-0000-0000-000000000001','2019-0917-TUB','44444444-0000-0000-0000-000000000001','Virgilio','Busalanan','+63 917 555 0142','BIEC-08317','11111111-0000-0000-0000-00000000000a','Purok 3','33333333-0000-0000-0000-000000000002'),
  ('55555555-0000-0000-0000-000000000002','2018-0442-TUB','44444444-0000-0000-0000-000000000002','Elena','Bongcaras','+63 917 555 0201','BIEC-08319','11111111-0000-0000-0000-00000000000a','Purok 1','33333333-0000-0000-0000-000000000002'),
  ('55555555-0000-0000-0000-000000000003','2021-1130-TUB','44444444-0000-0000-0000-000000000003','Rodel','Amistad','+63 917 555 0202','BIEC-08321','11111111-0000-0000-0000-00000000000a','Purok 2','33333333-0000-0000-0000-000000000002'),
  ('55555555-0000-0000-0000-000000000004','2017-0338-TUB','44444444-0000-0000-0000-000000000004','Teresita','Lumayag',null,'BIEC-08323','11111111-0000-0000-0000-00000000000a','Purok 2','33333333-0000-0000-0000-000000000002'),
  ('55555555-0000-0000-0000-000000000005','2020-0791-TUB','44444444-0000-0000-0000-000000000005','Bienvenido','Sarigumba','+63 917 555 0204','BIEC-08325','11111111-0000-0000-0000-00000000000a','Purok 4','33333333-0000-0000-0000-000000000002'),
  ('55555555-0000-0000-0000-000000000006','2019-0625-TUB','44444444-0000-0000-0000-000000000006','Marilou','Cagampang','+63 917 555 0205','BIEC-08327','11111111-0000-0000-0000-00000000000a','Purok 4','33333333-0000-0000-0000-000000000002'),
  -- Area 4, used to prove the area boundary in the RLS tests.
  ('55555555-0000-0000-0000-000000000007','2022-0001-TUB','44444444-0000-0000-0000-000000000007','Ben','Aquino','+63 917 555 0206','BIEC-09001','11111111-0000-0000-0000-00000000000b','Purok 1','33333333-0000-0000-0000-000000000004')
on conflict (id) do nothing;


-- ---------------------------------------------------------------------
-- Test role.
--
-- RLS is bypassed by superusers and by a table's owner, so the policies
-- in 04_rls.sql can only be PROVEN from an ordinary role. This role
-- stands in for Supabase's `authenticated` role during local testing.
-- ---------------------------------------------------------------------
do $$ begin
  create role test_app nologin;
exception when duplicate_object then null;
end $$;

grant usage on schema public, app to test_app;
grant select, insert, update, delete on all tables in schema public to test_app;
grant usage, select on all sequences in schema public to test_app;
grant execute on all functions in schema public, app to test_app;
