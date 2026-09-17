-- =====================================================================
-- BillAlert — 15_bill_meter_readings.sql
--
-- The Consumer's Bill Details shows the meter readings behind the figure.
--
-- FR-25 names the reading, not only the consumption: a household checking
-- its bill wants to see the two numbers on the dial and satisfy itself that
-- the difference is the kWh it is being charged for. Until now the only view
-- carrying them was v_consumer_current_bill, which answers one question —
-- "what is open right now" — so History and the Bill Details sheet, which
-- both read v_bill_status, had nothing to show but the consumption.
--
-- This appends the three reading columns to v_bill_status. Every bill has
-- exactly one reading (bills.meter_reading_id is NOT NULL UNIQUE), so an
-- inner join would be correct; it is written as a LEFT JOIN anyway, so that
-- a reading deleted out from under a bill degrades to a missing reading on
-- one screen rather than a bill that vanishes from the household's history.
--
-- APPEND ONLY. `create or replace view` may not rename or reorder an
-- existing column, so the three new ones go at the end of the select list.
-- =====================================================================

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
       else greatest(0, fn_ph_today() - b.due_date) end             as days_overdue,
  -- Appended 2026-09-16 for FR-25 on Consumer › Bill Details.
  mr.previous_reading,
  mr.current_reading,
  mr.reading_date
from bills b
join consumers c       on c.id  = b.consumer_id
join billing_cycles bc on bc.id = b.billing_cycle_id
left join meter_readings mr on mr.id = b.meter_reading_id;

comment on view v_bill_status is
  'DOM-04, MTR-14, CON-01, FR-25. Single source of truth for "is this bill overdue", "is it priced yet", and the meter readings behind it.';

-- `create or replace view` keeps the options the view already had, but this
-- one is not worth taking on trust: without security_invoker the view runs
-- as its owner and bypasses RLS, and every household would read every other
-- household's bills. Re-asserting it costs nothing.
alter view v_bill_status set (security_invoker = on);
