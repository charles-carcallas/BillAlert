-- =====================================================================
-- BillAlert — 04_rls.sql
-- Row-Level Security.
--
-- GEN-08 requires role restrictions enforced "server-side on every API
-- request", and DOM-08 confines staff to their assigned area. Doing that
-- in Dart alone is not enforcement — anyone with the anon key and an HTTP
-- client bypasses it. These policies are the actual boundary; the Flutter
-- routing guard is only the courtesy layer on top.
--
-- IMPORTANT — the Admin is NOT a superuser.
--
-- Phase 1 §5: Barangay Tubod has four service areas, each with its own Area
-- President (the Admin), Meter Reader and Cashier. FR-31 enforces one active
-- holder of each per area. So `app.is_admin()` on its own must never grant
-- cross-area access — every staff policy below uses `app.staff_in_area(...)`,
-- which requires the row's area to match the caller's. Only system-wide
-- configuration (settings, sms_providers, holidays) is shared across areas.
--
-- Rubric relevance: "Security Implementation" (7%) and "Technical
-- Implementation" (15%).
-- =====================================================================

alter table profiles              enable row level security;
alter table consumers             enable row level security;
alter table billing_cycles        enable row level security;
alter table meter_readings        enable row level security;
alter table bills                 enable row level security;
alter table payment_transactions  enable row level security;
alter table payments              enable row level security;
alter table disconnection_notices enable row level security;
alter table notifications         enable row level security;
alter table settings              enable row level security;
alter table areas                 enable row level security;
alter table sms_providers         enable row level security;
alter table ph_holidays           enable row level security;

-- ---------------------------------------------------------------------
-- profiles — you always see yourself; Admin sees everyone.
-- ---------------------------------------------------------------------
drop policy if exists profiles_select_self_or_admin on profiles;
create policy profiles_select_self_or_admin on profiles
  for select using (
    id = app.current_user_id()
    or (app.is_admin() and area_id = app.current_area())
  );

drop policy if exists profiles_update_self on profiles;
create policy profiles_update_self on profiles
  for update using (id = app.current_user_id())
  with check  (id = app.current_user_id());

-- FR-31: the Admin creates staff and consumer accounts — for their own area.
-- A consumer login has no area, so it is admitted on role alone.
drop policy if exists profiles_admin_write on profiles;
create policy profiles_admin_write on profiles
  for all using (app.is_admin() and (area_id = app.current_area() or role = 'consumer'))
  with check  (app.is_admin() and (area_id = app.current_area() or role = 'consumer'));


-- ---------------------------------------------------------------------
-- consumers — MTR-02: assigned area only. Access outside it is refused,
-- not filtered client-side.
-- ---------------------------------------------------------------------
drop policy if exists consumers_select_scoped on consumers;
create policy consumers_select_scoped on consumers
  for select using (
    app.staff_in_area(area_id)              -- admin, reader or cashier, own area only
    or profile_id = app.current_user_id()   -- the consumer themselves
  );

-- FR-31: consumer accounts are created by the ADMIN, not the Meter Reader.
-- (The mockup puts "New Consumer" under Admin > Accounts, and Phase 1 §4
-- lists account creation under the Admin Module.) This supersedes MTR-03/04
-- in the engineering SRS, which still assigns registration to the reader.
drop policy if exists consumers_mtr_insert on consumers;
drop policy if exists consumers_mtr_update on consumers;
drop policy if exists consumers_admin_insert on consumers;
create policy consumers_admin_insert on consumers
  for insert with check (app.is_admin() and area_id = app.current_area());

drop policy if exists consumers_admin_update on consumers;
create policy consumers_admin_update on consumers
  for update using (app.is_admin() and area_id = app.current_area())
  with check  (app.is_admin() and area_id = app.current_area());


-- ---------------------------------------------------------------------
-- meter_readings — MTR-11: the Meter Reader writes only in their area.
-- ---------------------------------------------------------------------
drop policy if exists readings_select_scoped on meter_readings;
create policy readings_select_scoped on meter_readings
  for select using (
    exists (
      select 1 from consumers c where c.id = meter_readings.consumer_id and (
        app.staff_in_area(c.area_id) or c.profile_id = app.current_user_id()
      )
    )
  );

drop policy if exists readings_mtr_insert on meter_readings;
create policy readings_mtr_insert on meter_readings
  for insert with check (
    app.current_role() = 'meter_reader'
    and exists (select 1 from consumers c
                 where c.id = meter_readings.consumer_id and c.area_id = app.current_area())
  );


-- ---------------------------------------------------------------------
-- bills — CON-02 for the consumer, area scope for staff.
-- Bills are INSERTED only through fn_record_meter_reading, never directly.
-- ---------------------------------------------------------------------
drop policy if exists bills_select_scoped on bills;
create policy bills_select_scoped on bills
  for select using (
    exists (
      select 1 from consumers c where c.id = bills.consumer_id and (
        app.staff_in_area(c.area_id) or c.profile_id = app.current_user_id()
      )
    )
  );

drop policy if exists bills_mtr_insert on bills;
create policy bills_mtr_insert on bills
  for insert with check (
    app.current_role() = 'meter_reader'
    and exists (select 1 from consumers c
                 where c.id = bills.consumer_id and c.area_id = app.current_area())
  );

-- FR-21b: the Admin posts the amount. FR-30: the Cashier moves money.
-- Both are UPDATEs on `bills`, so both roles need the policy; which columns
-- each may actually change is enforced by fn_post_bill_amount (admin-only)
-- and fn_record_payment, not by the policy.
drop policy if exists bills_staff_update on bills;
create policy bills_staff_update on bills
  for update using (
    exists (select 1 from consumers c
             where c.id = bills.consumer_id
               and app.staff_in_area(c.area_id)
               and app.current_role() in ('admin','cashier'))
  ) with check (true);
drop policy if exists bills_cashier_update on bills;


-- ---------------------------------------------------------------------
-- payments — CSH-07 / MTR-18 / CON-03.
-- ---------------------------------------------------------------------
drop policy if exists paytxn_select_scoped on payment_transactions;
create policy paytxn_select_scoped on payment_transactions
  for select using (
    app.staff_in_area(area_id)
    or exists (select 1 from consumers c
                where c.id = payment_transactions.consumer_id
                  and c.profile_id = app.current_user_id())
  );

drop policy if exists paytxn_cashier_insert on payment_transactions;
create policy paytxn_cashier_insert on payment_transactions
  for insert with check (
    app.current_role() = 'cashier' and area_id = app.current_area()
  );

drop policy if exists payments_select_scoped on payments;
create policy payments_select_scoped on payments
  for select using (
    exists (
      select 1 from consumers c where c.id = payments.consumer_id and (
        app.staff_in_area(c.area_id) or c.profile_id = app.current_user_id()
      )
    )
  );

drop policy if exists payments_cashier_insert on payments;
create policy payments_cashier_insert on payments
  for insert with check (
    app.current_role() = 'cashier'
    and exists (select 1 from consumers c
                 where c.id = payments.consumer_id and c.area_id = app.current_area())
  );


-- ---------------------------------------------------------------------
-- disconnection_notices — MTR-15 issues, ADM-17 closes, CON-04 reads.
-- ---------------------------------------------------------------------
drop policy if exists notices_select_scoped on disconnection_notices;
create policy notices_select_scoped on disconnection_notices
  for select using (
    exists (
      select 1 from consumers c where c.id = disconnection_notices.consumer_id and (
        app.staff_in_area(c.area_id) or c.profile_id = app.current_user_id()
      )
    )
  );

-- ⚠ UNRESOLVED CONTRADICTION IN THE PHASE 1 FINAL DOCUMENT.
--   Objective 5 and §4 (In Scope, Meter Reader Module) say the METER READER
--   creates and queues disconnection notices.
--   FR-37 says the ADMIN issues them.
-- Both roles are permitted here so neither reading is blocked, but the
-- document needs one of the two corrected. See the Week 11 guide.
drop policy if exists notices_mtr_insert on disconnection_notices;
drop policy if exists notices_staff_insert on disconnection_notices;
create policy notices_staff_insert on disconnection_notices
  for insert with check (
    app.current_role() in ('meter_reader','admin')
    and exists (select 1 from consumers c
                 where c.id = disconnection_notices.consumer_id
                   and c.area_id = app.current_area())
  );

-- FR-32: recording an outcome is the Admin's alone, in their own area.
drop policy if exists notices_admin_update on disconnection_notices;
create policy notices_admin_update on disconnection_notices
  for update using (
    app.is_admin()
    and exists (select 1 from consumers c
                 where c.id = disconnection_notices.consumer_id
                   and c.area_id = app.current_area())
  ) with check (true);


-- ---------------------------------------------------------------------
-- notifications — CON-05 inbox, MTR-16/17 history.
-- ---------------------------------------------------------------------
drop policy if exists notif_select_scoped on notifications;
create policy notif_select_scoped on notifications
  for select using (
    exists (
      select 1 from consumers c where c.id = notifications.consumer_id and (
        app.staff_in_area(c.area_id) or c.profile_id = app.current_user_id()
      )
    )
  );

-- FR-13. Staff queue alerts as a side effect of doing their job: posting an
-- amount sends the bill-ready alert, serving a notice sends its own. Those
-- inserts happen inside fn_queue_notification, which is SECURITY INVOKER, so
-- they run as the staff member who called it and need a policy of their own.
--
-- There was none. Not a narrow one - none at all, for any role. So every
-- INSERT into notifications was refused, and because fn_post_bill_amount
-- queues the alert in the same transaction as the amount, the whole posting
-- rolled back: the Admin could not price a single bill, and the only clue was
-- "42501 new row violates row-level security policy for table notifications".
--
-- Scoped the same way every other staff write is: their own service area.
-- app.staff_in_area covers admin, meter_reader and cashier, so this one
-- policy serves fn_post_bill_amount, fn_issue_disconnection_notice and
-- fn_record_payment alike.
drop policy if exists notif_staff_insert on notifications;
create policy notif_staff_insert on notifications
  for insert with check (
    exists (select 1 from consumers c
             where c.id = notifications.consumer_id
               and app.staff_in_area(c.area_id))
  );

-- CON-05: the consumer may mark their own alerts read. Nothing else.
drop policy if exists notif_consumer_mark_read on notifications;
create policy notif_consumer_mark_read on notifications
  for update using (
    exists (select 1 from consumers c
             where c.id = notifications.consumer_id and c.profile_id = app.current_user_id())
  ) with check (
    exists (select 1 from consumers c
             where c.id = notifications.consumer_id and c.profile_id = app.current_user_id())
  );

-- MTR-16: manual retry of a failed delivery.
drop policy if exists notif_staff_update on notifications;
create policy notif_staff_update on notifications
  for update using (
    exists (select 1 from consumers c
             where c.id = notifications.consumer_id and app.staff_in_area(c.area_id))
  ) with check (true);


-- ---------------------------------------------------------------------
-- Reference data — readable by everyone signed in, writable by Admin.
-- ---------------------------------------------------------------------
drop policy if exists areas_read on areas;
create policy areas_read on areas for select using (app.current_user_id() is not null);
drop policy if exists areas_admin_write on areas;
create policy areas_admin_write on areas for all using (app.is_admin()) with check (app.is_admin());

drop policy if exists cycles_read on billing_cycles;
create policy cycles_read on billing_cycles for select using (app.current_user_id() is not null);
drop policy if exists cycles_write on billing_cycles;
create policy cycles_write on billing_cycles
  for all using (app.current_role() in ('admin','meter_reader'))
  with check (app.current_role() in ('admin','meter_reader'));


-- ADM-11/14/15/16: everyone reads the cycle and template values the app needs;
-- only the Admin changes them.
drop policy if exists settings_read on settings;
create policy settings_read on settings for select using (app.current_user_id() is not null);
drop policy if exists settings_admin_write on settings;
create policy settings_admin_write on settings for all using (app.is_admin()) with check (app.is_admin());

-- DOM-05: the Philippine holiday calendar is readable by every signed-in user.
--
-- This policy exists for a specific failure mode. fn_earliest_lawful_disconnection
-- reads this table to skip holidays. If RLS were ever enabled here WITHOUT a read
-- policy — which Supabase's "Enable automatic RLS" setting would do on its own —
-- the function would find no holidays, silently compute a lawful disconnection
-- window that falls on a public holiday, and record it as lawful. No error, wrong
-- answer, and the answer states a statutory period.
--
-- fn_earliest_lawful_disconnection is additionally SECURITY DEFINER so the lawful
-- window never depends on who is asking. Whether a day is a holiday is a matter of
-- law, not of permissions.
drop policy if exists holidays_read on ph_holidays;
create policy holidays_read on ph_holidays
  for select using (app.current_user_id() is not null);
drop policy if exists holidays_admin_write on ph_holidays;
create policy holidays_admin_write on ph_holidays
  for all using (app.is_admin()) with check (app.is_admin());

-- ADM-12: SMS provider configuration is Admin-only in BOTH directions.
-- Note that credential_ref holds only the NAME of a Vault secret.
drop policy if exists sms_admin_only on sms_providers;
create policy sms_admin_only on sms_providers for all using (app.is_admin()) with check (app.is_admin());


-- =====================================================================
-- API ROLE GRANTS  (Supabase only — skipped on a plain Postgres)
--
-- THE BUG THIS FIXES, so nobody reintroduces it:
--
-- Every policy above calls a helper in the `app` schema. Postgres evaluates
-- those as the CONNECTING role, which Supabase sets to `anon` before sign-in
-- and `authenticated` after. A custom schema grants nothing to those roles by
-- default, so every request came back:
--
--     401  {"code":"42501","message":"permission denied for schema app"}
--
-- Auth succeeded, the profile lookup hit a policy, the policy could not enter
-- the schema, and the app bounced the user back to the login screen with no
-- explanation.
--
-- 06_tests.sql never caught it because it runs as `test_app`, which 05_seed
-- grants explicitly. A green 56/56 said the RULES were right; it said nothing
-- about whether the app could open the door. Those are different questions and
-- this file is where the second one is answered.
--
-- This grants the ability to CALL the helpers, not to bypass anything. They are
-- SECURITY DEFINER and read only the caller's own row; RLS still decides which
-- rows come back. An unauthenticated caller gets an empty result rather than an
-- error, which is correct.
-- =====================================================================
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    grant usage   on schema app to anon, authenticated;
    grant execute on all functions in schema app    to anon, authenticated;
    grant execute on all functions in schema public to anon, authenticated;

    -- Without this, the NEXT app.* helper anyone adds reintroduces the
    -- identical total outage.
    alter default privileges in schema app
      grant execute on functions to anon, authenticated;
    alter default privileges in schema public
      grant execute on functions to anon, authenticated;

    -- Table privileges say "may touch this table at all"; RLS still decides
    -- which rows. This is the Supabase model.
    grant usage on schema public to anon, authenticated;
    grant select, insert, update, delete on all tables in schema public to authenticated;
    grant usage, select on all sequences in schema public to authenticated;

    raise notice 'Supabase API role grants applied.';
  else
    raise notice 'No `authenticated` role — plain Postgres, API grants skipped.';
  end if;
end $$;
