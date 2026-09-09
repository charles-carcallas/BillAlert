-- =====================================================================
-- BillAlert — 08_calendar_cycles.sql
--
-- A billing cycle is a CALENDAR MONTH. An August cycle covers August.
--
-- It previously ran from the 15th to the 14th, because the Figma mockup
-- shows "15 July 2026 - 14 August 2026" and 01_schema.sql followed it.
-- That is a deliberate departure from the design, decided by the domain
-- owner: a cycle that starts on the 15th means the "August" cycle covers
-- half of September, and every screen that prints "August 2026" over it
-- is telling a half-truth.
--
-- Consequence worth understanding before running this: with the cycle
-- resolved by calendar month, TODAY (10 September) falls in the September
-- cycle, which has no readings yet. The meter reader's round opens with
-- every household unread, instead of being blocked by FR-23 because all
-- five were already read in the 15 Aug - 14 Sep window.
--
-- Safe to run more than once.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. The definition. fn_ensure_billing_cycle reads this and nothing else.
-- ---------------------------------------------------------------------
update settings set cycle_start_day = 1 where id = 1;


-- ---------------------------------------------------------------------
-- 2. The cycles that already exist, moved onto calendar months.
--
-- cycle_year and cycle_month do not change, so bill numbers built from
-- to_char(period_start,'YYYYMM') keep the values already issued, and
-- cycle_label — to_char(period_start,'FMMonth YYYY') — still reads
-- "July 2026" and "August 2026".
-- ---------------------------------------------------------------------
update billing_cycles
   set period_start = make_date(cycle_year, cycle_month, 1),
       period_end   = (make_date(cycle_year, cycle_month, 1)
                       + interval '1 month - 1 day')::date
 where period_start <> make_date(cycle_year, cycle_month, 1);


-- ---------------------------------------------------------------------
-- 3. The reading and due dates the cooperative actually works to: the
--    meter is read on the 7th of the following month, and the bill falls
--    due on the 28th of that same month.
--
--    A reading therefore sits AFTER its cycle's period_end, which is
--    correct — you cannot read a month's consumption until the month is
--    over.
-- ---------------------------------------------------------------------
update meter_readings r
   set reading_date = (make_date(c.cycle_year, c.cycle_month, 7)
                       + interval '1 month')::date,
       captured_at  = ((make_date(c.cycle_year, c.cycle_month, 7)
                        + interval '1 month')::date
                       + time '09:15') at time zone 'Asia/Manila'
  from billing_cycles c
 where r.billing_cycle_id = c.id;

-- Only priced bills. bills_pricing_consistent requires due_date to stay
-- null while total_amount is null, so an unpriced bill is left alone.
update bills b
   set due_date = (make_date(c.cycle_year, c.cycle_month, 28)
                   + interval '1 month')::date
  from billing_cycles c
 where b.billing_cycle_id = c.id
   and b.total_amount is not null;


-- ---------------------------------------------------------------------
-- 4. What this looks like afterwards. Run it and read the output.
--
--    July 2026   read 07 Aug, due 28 Aug  -> OVERDUE on 10 September
--    August 2026 read 07 Sep, due 28 Sep  -> current
-- ---------------------------------------------------------------------
select
  c.cycle_year,
  c.cycle_month,
  c.period_start,
  c.period_end,
  min(r.reading_date)                                   as read_on,
  min(b.due_date)                                       as due_on,
  count(distinct r.id)                                  as readings,
  count(distinct b.id) filter (where b.due_date < fn_ph_today()
                                 and b.status <> 'paid') as overdue_bills
from billing_cycles c
left join meter_readings r on r.billing_cycle_id = c.id
left join bills b          on b.billing_cycle_id = c.id
group by c.cycle_year, c.cycle_month, c.period_start, c.period_end
order by c.cycle_year, c.cycle_month;
