-- =====================================================================
-- BillAlert — 03_views.sql
-- The aggregate reads behind the screens. Each one exists because a
-- specific Figma screen displays a number that is expensive or
-- error-prone to assemble in Dart.
--
-- Views do NOT inherit the RLS of their underlying tables by default.
-- A view runs as the role that OWNS it, and these are owned by postgres,
-- which bypasses RLS entirely. `security_invoker = on` is what makes a
-- Meter Reader querying v_meter_reader_progress see only their own area,
-- and it is set on every view at the foot of this file. Read that block
-- before adding a view here.
--
-- ADDING A COLUMN TO AN EXISTING VIEW: put it at the END of the select
-- list. `create or replace view` may only APPEND. Inserting a column
-- mid-list renames every column after it, and Postgres refuses the whole
-- script with 42P16 "cannot change name of view column". Order does not
-- matter to PostgREST, which selects by name.
-- =====================================================================

-- DOM-04. "Overdue" depends on today's date, so it can never be a stored
-- column. An UNPRICED bill has no due date and can never be overdue.
create or replace view v_bill_status as
select
  b.*,
  c.consumer_no,
  c.first_name,
  c.last_name,
  c.purok,
  c.area_id,
  bc.cycle_year,
  bc.cycle_month,
  bc.period_start,
  bc.period_end,
  to_char(bc.period_start, 'FMMonth YYYY')                          as cycle_label,
  (b.total_amount is null)                                          as is_unpriced,
  (b.total_amount is not null and b.status <> 'paid'
     and b.due_date < fn_ph_today())                                as is_overdue,
  case when b.due_date is null then 0
       else greatest(0, fn_ph_today() - b.due_date) end             as days_overdue
from bills b
join consumers c       on c.id  = b.consumer_id
join billing_cycles bc on bc.id = b.billing_cycle_id;

comment on view v_bill_status is
  'DOM-04, MTR-14, CON-01. Single source of truth for "is this bill overdue" and "is it priced yet".';


-- CON-01 / FR-25: the Consumer's current bill.
--
-- Deliberately includes UNPRICED bills. FR-25 requires the screen to show
-- the reading, the consumption, the date read, and that the amount is
-- awaiting the cooperative — that seven-day window is the whole point of
-- the application, and a view that filtered unpriced bills out would make
-- the screen impossible to build.
create or replace view v_consumer_current_bill as
select distinct on (vb.consumer_id)
  vb.consumer_id,
  vb.id            as bill_id,
  vb.bill_no,
  vb.cycle_label,
  vb.consumption,
  mr.previous_reading,
  mr.current_reading,
  mr.reading_date,
  vb.total_amount,
  vb.amount_paid,
  vb.balance,
  vb.due_date,
  vb.status,
  vb.is_unpriced,
  vb.is_overdue,
  vb.days_overdue,
  vb.period_start,
  vb.period_end
from v_bill_status vb
join meter_readings mr on mr.id = vb.meter_reading_id
where vb.status <> 'paid'
order by vb.consumer_id, vb.due_date asc nulls last, vb.period_start asc;


-- FR-21b / Admin › Amounts: "4 readings awaiting an amount".
-- The Admin's work queue, oldest first, with everything the screen shows.
create or replace view v_readings_awaiting_amount as
select
  b.id                                as bill_id,
  b.bill_no,
  c.id                                as consumer_id,
  c.consumer_no,
  c.first_name || ' ' || c.last_name  as consumer_name,
  c.area_id,
  c.purok,
  mr.previous_reading,
  mr.current_reading,
  b.consumption,
  mr.reading_date,
  bc.id                               as billing_cycle_id,
  to_char(bc.period_start, 'FMMonth YYYY') as cycle_label,
  fn_ph_today() - mr.reading_date      as days_waiting,
  -- Appended at the END on purpose: `create or replace view` can add columns
  -- but cannot insert them mid-list or rename existing ones.
  --
  -- The app builds its CycleLabel from these two integers rather than by
  -- parsing cycle_label. Reading a month back out of rendered text is
  -- guesswork next to reading an integer the server already computed, and
  -- this was the only view offering nothing but the text.
  bc.cycle_year,
  bc.cycle_month
from bills b
join consumers c       on c.id  = b.consumer_id
join meter_readings mr on mr.id = b.meter_reading_id
join billing_cycles bc on bc.id = b.billing_cycle_id
where b.total_amount is null
order by mr.reading_date asc;


-- FR-19 / Meter Reader › Readings: "14 of 62 read", "48 not yet read".
--
-- Counts READINGS, not bills. The reader's job is complete at the reading;
-- billing happens elsewhere, later, and their progress must not depend on
-- whether the cooperative has returned an amount.
create or replace view v_meter_reader_progress as
select
  bc.id                                        as billing_cycle_id,
  bc.cycle_year,
  bc.cycle_month,
  bc.period_start,
  bc.period_end,
  a.id                                         as area_id,
  a.name                                       as area_name,
  p.id                                         as meter_reader_id,
  p.first_name || ' ' || p.last_name           as meter_reader_name,
  count(c.id) filter (where c.account_status = 'active')                    as total_consumers,
  count(mr.id)                                                              as read_count,
  count(c.id) filter (where c.account_status = 'active') - count(mr.id)     as not_yet_read_count,
  round(
    100.0 * count(mr.id)
    / nullif(count(c.id) filter (where c.account_status = 'active'), 0), 0
  )                                                                         as completion_pct
from billing_cycles bc
cross join areas a
left join profiles p
       on p.area_id = a.id and p.role = 'meter_reader' and p.account_status = 'active'
left join consumers c
       on c.area_id = a.id
left join meter_readings mr
       on mr.consumer_id = c.id and mr.billing_cycle_id = bc.id
where a.is_active
group by bc.id, bc.cycle_year, bc.cycle_month, bc.period_start, bc.period_end,
         a.id, a.name, p.id, p.first_name, p.last_name;


-- ADM-09 / CSH-02 / Cashier › Consumers: "5 consumers with payable bills
-- · ₱5,580.15 outstanding". Counts only PAYABLE bills — an unpriced bill
-- is not collectable and must not appear in a collection target.
create or replace view v_cashier_collection_progress as
select
  bc.id                                        as billing_cycle_id,
  bc.cycle_year,
  bc.cycle_month,
  a.id                                         as area_id,
  a.name                                       as area_name,
  p.id                                         as cashier_id,
  p.first_name || ' ' || p.last_name           as cashier_name,
  count(b.id) filter (where b.total_amount is not null)                  as payable_count,
  count(b.id) filter (where b.status = 'paid')                           as paid_count,
  count(b.id) filter (where b.total_amount is not null
                        and b.status <> 'paid')                          as outstanding_count,
  count(b.id) filter (where b.total_amount is null)                      as awaiting_amount_count,
  coalesce(sum(b.total_amount), 0)                                       as total_billed,
  coalesce(sum(b.amount_paid), 0)                                        as total_collected,
  coalesce(sum(b.balance) filter (where b.status <> 'paid'), 0)          as total_outstanding,
  round(100.0 * count(b.id) filter (where b.status = 'paid')
        / nullif(count(b.id) filter (where b.total_amount is not null), 0), 0) as completion_pct
from billing_cycles bc
cross join areas a
left join profiles p
       on p.area_id = a.id and p.role = 'cashier' and p.account_status = 'active'
left join consumers c on c.area_id = a.id
left join bills b     on b.consumer_id = c.id and b.billing_cycle_id = bc.id
where a.is_active
group by bc.id, bc.cycle_year, bc.cycle_month, a.id, a.name, p.id, p.first_name, p.last_name;


-- Cashier › Consumers: the per-consumer outstanding roll-up —
-- "₱1,975.35 · 3 bills · oldest June · 2 overdue".
create or replace view v_consumer_outstanding as
select
  vb.consumer_id,
  vb.consumer_no,
  vb.first_name || ' ' || vb.last_name  as consumer_name,
  vb.purok,
  vb.area_id,
  count(*) filter (where not vb.is_unpriced)              as payable_bill_count,
  count(*) filter (where vb.is_unpriced)                  as unpriced_bill_count,
  count(*) filter (where vb.is_overdue)                   as overdue_count,
  coalesce(sum(vb.balance), 0)                            as total_outstanding,
  min(vb.period_start) filter (where not vb.is_unpriced)  as oldest_payable_period
from v_bill_status vb
where vb.status <> 'paid'
group by vb.consumer_id, vb.consumer_no, vb.first_name, vb.last_name, vb.purok, vb.area_id;


-- CSH-01 / Cashier › Consumers: "Today's collections ₱3,697.15 · 3 receipts".
create or replace view v_cashier_daily_summary as
select
  pt.area_id,
  pt.cashier_id,
  fn_ph_today(pt.paid_at)                as collection_date,
  count(*)                               as receipt_count,
  coalesce(sum(pt.total_collected), 0)   as total_collected
from payment_transactions pt
group by pt.area_id, pt.cashier_id, fn_ph_today(pt.paid_at);


-- CON-03 / Consumer › History: one row per bill settled, carrying the OR
-- number of the transaction that settled it. The same OR number appears
-- against several months when one payment cleared several bills — which
-- is exactly what the mockup shows.
create or replace view v_payment_history as
select
  pay.id            as payment_id,
  pay.consumer_id,
  pay.bill_id,
  b.bill_no,
  to_char(bc.period_start, 'FMMonth YYYY') as cycle_label,
  pt.receipt_no,
  pt.verification_code,
  pay.amount_paid,
  pt.total_collected as transaction_total,
  pt.cash_tendered,
  pt.change_due,
  pay.paid_at,
  pt.cashier_id,
  c.area_id,
  c.first_name || ' ' || c.last_name as consumer_name
from payments pay
join payment_transactions pt on pt.id = pay.transaction_id
join bills b                 on b.id  = pay.bill_id
join billing_cycles bc       on bc.id = b.billing_cycle_id
join consumers c             on c.id  = pay.consumer_id;


-- CON-04 / Admin › Notices: the active disconnection warnings.
create or replace view v_active_disconnection_warnings as
select
  dn.id            as notice_id,
  dn.notice_no,
  dn.consumer_id,
  c.consumer_no,
  c.first_name || ' ' || c.last_name as consumer_name,
  c.area_id,
  dn.reason,
  dn.served_at,
  dn.earliest_lawful_at,
  dn.served_at at time zone 'Asia/Manila'          as served_at_ph,
  dn.earliest_lawful_at at time zone 'Asia/Manila' as earliest_lawful_at_ph,
  (now() >= dn.earliest_lawful_at)                 as notice_period_elapsed,
  -- Genuinely OVERDUE, not merely unpaid. Without the due-date filter this
  -- summed every payable bill, so a notice document printed "amount overdue
  -- P1,191.75" at a household whose past-due balance was P533.45 — the rest
  -- was a bill not yet due. A disconnection notice is the last document that
  -- may overstate what somebody owes.
  --
  -- The expression may change here; the NAME may not. `create or replace
  -- view` refuses a rename, so the filter is added in place.
  coalesce((select sum(b.balance) from bills b
             where b.consumer_id = dn.consumer_id
               and b.total_amount is not null
               and b.status <> 'paid'
               and b.due_date < fn_ph_today()), 0) as amount_overdue,
  -- Added for the notice document (132:2), and added HERE, at the end, on
  -- purpose. `create or replace view` may only APPEND columns: inserting one
  -- mid-list renames every column after it and Postgres refuses with 42P16.
  -- Anything added later goes below this line, never above it.
  c.purok,
  c.meter_serial_no,
  dn.issued_by,
  -- Who served it. LEFT JOIN on purpose: this view is security_invoker, so an
  -- inner join would make a whole notice vanish from the Admin's list the
  -- moment the issuing profile stopped being visible to them — a missing row
  -- with no error, the same class of bug as the views that once bypassed RLS
  -- entirely.
  p.first_name || ' ' || p.last_name as issued_by_name
from disconnection_notices dn
join consumers c on c.id = dn.consumer_id
left join profiles p on p.id = dn.issued_by
where dn.status = 'active';


-- MTR-16/17 + CON-05: notification delivery status.
create or replace view v_notification_status as
select
  n.id,
  n.consumer_id,
  c.area_id,
  c.consumer_no,
  c.first_name || ' ' || c.last_name as consumer_name,
  n.billing_cycle_id,
  n.notif_type,
  n.channel,
  n.status,
  n.failed_reason,
  n.retry_count,
  n.sent_at,
  n.is_read,
  n.created_at
from notifications n
join consumers c on c.id = n.consumer_id;


-- SYS-02: bills due for a pre-due reminder today. Read by the scheduled job.
-- Only priced bills have a due date to count back from.
create or replace view v_due_for_predue_reminder as
select b.id as bill_id, b.consumer_id, b.billing_cycle_id, b.due_date, b.balance
from bills b
cross join settings s
where s.id = 1
  and b.total_amount is not null
  and b.status <> 'paid'
  and b.due_date = fn_ph_today() + s.predue_reminder_days
  and not exists (
    select 1 from notifications n
     where n.bill_id = b.id and n.notif_type = 'pre_due_reminder'
  );

-- SYS-03: bills due for an overdue notice today. Consumers already under
-- an active disconnection notice are excluded — they get the warning instead.
create or replace view v_due_for_overdue_notice as
select b.id as bill_id, b.consumer_id, b.billing_cycle_id, b.due_date, b.balance
from bills b
cross join settings s
where s.id = 1
  and s.overdue_enabled
  and b.total_amount is not null
  and b.status <> 'paid'
  and b.due_date = fn_ph_today() - s.overdue_days_after
  and not exists (
    select 1 from notifications n
     where n.bill_id = b.id and n.notif_type = 'overdue'
  )
  and not exists (
    select 1 from disconnection_notices dn
     where dn.consumer_id = b.consumer_id and dn.status = 'active'
  );


-- =====================================================================
-- SECURITY INVOKER — the views must run as the CALLER, not as their owner.
--
-- THE BUG THIS FIXES
--
-- The header of this file used to claim that "views inherit the RLS of
-- their underlying tables". They do not. A Postgres view runs with the
-- privileges of the role that OWNS it unless `security_invoker` is set,
-- and these views are owned by `postgres`, which bypasses RLS on every
-- table they read.
--
-- Measured on the live project, signed in as the consumer Virgilio
-- Busalanan through PostgREST with the anon key:
--
--   select on the bills TABLE          -> 1 row   (his own)
--   select on v_bill_status            -> 5 rows  (four other households)
--   select on v_consumer_current_bill  -> 5 rows  (four other households)
--   select on v_consumer_outstanding   -> 5 rows  (four other households)
--
-- The tables were never the problem. The views were, and the app reads
-- through the views by design — so a consumer signed into BillAlert could
-- read every household's consumption, bills and payment history in their
-- service area. This is the whole of GEN-08 and the RLS criterion.
--
-- WHY THE TEST SUITE DID NOT CATCH IT
--
-- Same reason 07_api_grants.sql exists: 06_tests.sql runs as `test_app`,
-- and the owner-privilege bypass applies whatever role is asking, so the
-- suite could not see the difference either.
--
-- WHAT THIS DOES
--
-- `security_invoker = on` makes the view execute as the querying role, so
-- the RLS policies on bills, consumers and payments apply normally. It
-- grants nothing: the caller still needs SELECT on the underlying tables,
-- which `authenticated` already has.
--
-- Requires PostgreSQL 15 or later. Supabase is well past that.
--
-- Every view is listed explicitly rather than looped over, so that adding
-- a view and forgetting this line shows up as a missing line in a diff.
-- =====================================================================
alter view v_bill_status                  set (security_invoker = on);
alter view v_consumer_current_bill        set (security_invoker = on);
alter view v_readings_awaiting_amount     set (security_invoker = on);
alter view v_meter_reader_progress        set (security_invoker = on);
alter view v_cashier_collection_progress  set (security_invoker = on);
alter view v_consumer_outstanding         set (security_invoker = on);
alter view v_cashier_daily_summary        set (security_invoker = on);
alter view v_payment_history              set (security_invoker = on);
alter view v_active_disconnection_warnings set (security_invoker = on);
alter view v_notification_status          set (security_invoker = on);
alter view v_due_for_predue_reminder      set (security_invoker = on);
alter view v_due_for_overdue_notice       set (security_invoker = on);
