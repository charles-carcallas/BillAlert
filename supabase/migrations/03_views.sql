-- =====================================================================
-- BillAlert — 03_views.sql
-- The aggregate reads behind the screens. Each one exists because a
-- specific Figma screen displays a number that is expensive or
-- error-prone to assemble in Dart.
--
-- Views inherit the RLS of their underlying tables, so a Meter Reader
-- querying v_meter_reader_progress still only sees their own area.
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
  c.area_id
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
  coalesce((select sum(b.balance) from bills b
             where b.consumer_id = dn.consumer_id
               and b.total_amount is not null
               and b.status <> 'paid'), 0)         as amount_overdue
from disconnection_notices dn
join consumers c on c.id = dn.consumer_id
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
