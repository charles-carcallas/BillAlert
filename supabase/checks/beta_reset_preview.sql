-- LEGACY: do not use for the current schema. It removes identities and omits
-- newer accounting tables. Use ../operations/20_reset_beta.sql and its README.
-- =====================================================================
-- BillAlert — beta_reset_preview.sql
--
-- Clears the test data before the Week 13 beta, leaving ONE Admin login.
-- The testers then create the Meter Reader, Cashier and Consumer
-- themselves during the demonstration, which is what starting from a
-- clean database means.
--
-- AS WRITTEN THIS CHANGES NOTHING. It ends in ROLLBACK, so it reports
-- what it would delete and then puts everything back. Read the counts,
-- and only when they look right change the last line to COMMIT.
--
-- BEFORE RUNNING, in order:
--   1. A verified backup exists (2026-09-23, restored and compared).
--   2. Every phone has finished syncing: Profile > Sync says
--      "Everything has been sent".
--   3. The SMS cron job is paused:
--        select cron.alter_job(2, active => false);
--      No text can then go out mid-reset. Re-enable it afterwards with
--        select cron.alter_job(2, active => true);
--   4. After the reset, every phone is UNINSTALLED and the beta build
--      installed fresh, or its saved copy of deleted households will
--      still be on screen.
--
-- DELETED: notifications, remit handovers, disconnection notices,
--   payments, receipts, bills, meter readings, billing cycles, every
--   household, and every login except the one Admin.
-- KEPT: the schema, functions, triggers, policies, the areas, the
--   settings row, the Philippine holidays, the SMS provider row, and
--   the Admin.
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 0. Guard: exactly one Admin must survive, or nothing happens.
-- ---------------------------------------------------------------------
do $$
declare
  v_admins int;
begin
  select count(*) into v_admins from profiles p join auth.users u on u.id = p.id where p.role = 'admin' and p.account_status = 'active';
  if v_admins <> 1 then
    raise exception
      'Expected exactly 1 admin profile, found %. Stopping so no login is lost.',
      v_admins;
  end if;
  if exists (select 1 from cron.job where active and command ilike '%send-sms%') then
    raise exception 'Pause the send-sms cron job before running this cleanup.';
  end if;
  if exists (select 1 from notifications where channel = 'sms' and status = 'pending') then
    raise exception 'Pending SMS exists. Resolve queued or in-flight texts before cleanup.';
  end if;
end $$;

-- What is here now.
select 'BEFORE' as stage, * from (
  select 'consumers' t, count(*) n from consumers
  union all select 'meter_readings', count(*) from meter_readings
  union all select 'bills', count(*) from bills
  union all select 'payment_transactions', count(*) from payment_transactions
  union all select 'payments', count(*) from payments
  union all select 'notifications', count(*) from notifications
  union all select 'disconnection_notices', count(*) from disconnection_notices
  union all select 'remit_handovers', count(*) from remit_handovers
  union all select 'billing_cycles', count(*) from billing_cycles
  union all select 'profiles', count(*) from profiles
  union all select 'auth users', count(*) from auth.users
) before_counts order by t;

-- ---------------------------------------------------------------------
-- 1. Transactional data, children before parents.
-- ---------------------------------------------------------------------
delete from notifications;
delete from remit_handovers;
delete from disconnection_notices;
delete from payments;
delete from payment_transactions;
delete from bills;
delete from meter_readings;
delete from billing_cycles;
delete from consumers;

-- ---------------------------------------------------------------------
-- 2. Every login except the Admin.
--
-- profiles.id references auth.users(id) on delete cascade, so deleting
-- the login removes its profile with it. Household logins go the same
-- way. consumers.profile_id is already gone with the households above.
-- ---------------------------------------------------------------------
delete from auth.users u
where not exists (
  select 1 from profiles p where p.id = u.id and p.role = 'admin'
);

-- ---------------------------------------------------------------------
-- ALTER SEQUENCE RESTART is transactional; unlike setval, ROLLBACK restores it.
-- 3. Numbering starts again, so the beta's first receipt and bill look
--    like a first one rather than continuing the old series.
-- ---------------------------------------------------------------------
alter sequence receipt_no_seq restart with 4471;
alter sequence bill_no_seq restart with 1;
alter sequence notice_no_seq restart with 33;

-- Who is left, so you can see the Admin survived before committing.
select p.role, p.first_name, p.last_name, p.account_status, u.email
from profiles p join auth.users u on u.id = p.id;

-- ---------------------------------------------------------------------
-- 4. What would be left. EXPECTED: every count 0 except
--    profiles 1, auth users 1, and the kept reference data.
-- ---------------------------------------------------------------------
select 'AFTER' as stage, * from (
  select 'consumers' t, count(*) n from consumers
  union all select 'meter_readings', count(*) from meter_readings
  union all select 'bills', count(*) from bills
  union all select 'payment_transactions', count(*) from payment_transactions
  union all select 'payments', count(*) from payments
  union all select 'notifications', count(*) from notifications
  union all select 'disconnection_notices', count(*) from disconnection_notices
  union all select 'remit_handovers', count(*) from remit_handovers
  union all select 'billing_cycles', count(*) from billing_cycles
  union all select 'profiles', count(*) from profiles
  union all select 'auth users', count(*) from auth.users
  union all select 'KEPT areas', count(*) from areas
  union all select 'KEPT settings', count(*) from settings
  union all select 'KEPT ph_holidays', count(*) from ph_holidays
  union all select 'KEPT sms_providers', count(*) from sms_providers
) after_counts order by t;

-- ---------------------------------------------------------------------
-- Change to COMMIT only when the numbers above are what you want.
-- ---------------------------------------------------------------------
rollback;


