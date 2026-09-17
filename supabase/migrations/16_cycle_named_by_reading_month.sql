-- =====================================================================
-- BillAlert — 16_cycle_named_by_reading_month.sql
--
-- A bill is named for the month it is READ and FALLS DUE.
--
-- The cooperative reads the meter on the 7th and the bill falls due on the
-- 28th of that same month. The household calls that "the July bill" when
-- both dates are in July. Calling it the June bill — because June is the
-- month the electricity was actually used — is the confusion this migration
-- removes.
--
-- The live application already works this way: fn_ensure_billing_cycle takes
-- the month of the reading date, so a reading captured on 7 August lands in
-- the August cycle. It is only the rows that 08_calendar_cycles.sql
-- back-dated that follow the other convention, which is why History shows
-- "July 2026 · read 7 August 2026 · due 28 August 2026".
--
-- WHAT THIS CHANGES: which cycle each reading and bill belongs to. It does
-- NOT touch a single reading, consumption, amount, due date or payment.
-- Every figure a household has been shown stays exactly as it was; only the
-- month printed beside it moves.
--
-- THE TRADE, written down so nobody rediscovers it: period_start and
-- period_end still describe a calendar month, and the consumption recorded
-- against the August cycle was in fact used during July. Under this
-- convention the cycle names WHEN THE BILL WAS RAISED, not the period the
-- kilowatt-hours were burned in. That is the cooperative's own language and
-- the households', and it is the one the app has to speak.
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 1. Refuse to run if the shift would collide.
--
-- bills_one_per_cycle and meter_readings_one_per_cycle both forbid two rows
-- for one household in one cycle. A uniform shift cannot collide, but a
-- household that already has a correctly-filed reading in the target month
-- would. Better to stop with a readable message than to fail halfway
-- through on a constraint name.
-- ---------------------------------------------------------------------
do $$
declare
  v_clash int;
begin
  select count(*) into v_clash
    from meter_readings r
    join billing_cycles c on c.id = r.billing_cycle_id
    join billing_cycles target
      on target.cycle_year  = extract(year  from r.reading_date)::smallint
     and target.cycle_month = extract(month from r.reading_date)::smallint
   where (c.cycle_year, c.cycle_month)
      <> (extract(year from r.reading_date)::smallint,
          extract(month from r.reading_date)::smallint)
     and exists (
           select 1 from meter_readings other
            where other.consumer_id = r.consumer_id
              and other.billing_cycle_id = target.id
              and (extract(year  from other.reading_date)::smallint,
                   extract(month from other.reading_date)::smallint)
                = (target.cycle_year, target.cycle_month)
         );

  if v_clash > 0 then
    raise exception
      '% reading(s) would land in a cycle that already holds a correctly filed reading for the same household. Resolve those before running this migration.',
      v_clash;
  end if;
end $$;


-- ---------------------------------------------------------------------
-- 2. Make sure every target cycle exists.
--
-- A reading taken on 7 September belongs to the September cycle, which may
-- never have been created — the old convention would not have needed it
-- until October.
-- ---------------------------------------------------------------------
insert into billing_cycles (cycle_year, cycle_month, period_start, period_end)
select distinct
  extract(year  from r.reading_date)::smallint,
  extract(month from r.reading_date)::smallint,
  make_date(extract(year from r.reading_date)::int,
            extract(month from r.reading_date)::int, 1),
  (make_date(extract(year from r.reading_date)::int,
             extract(month from r.reading_date)::int, 1)
   + interval '1 month - 1 day')::date
from meter_readings r
on conflict (cycle_year, cycle_month) do nothing;


-- ---------------------------------------------------------------------
-- 3. Re-point the readings and their bills, NEWEST CYCLE FIRST.
--
-- Order matters. A plain unique index is enforced row by row, not at the
-- end of the statement, so moving July into August while August is still
-- occupied trips meter_readings_one_per_cycle even though the finished
-- state is sound. Walking from the newest cycle down means each target has
-- already been vacated by the pass before it.
-- ---------------------------------------------------------------------
do $$
declare
  c record;
begin
  for c in
    select bc.id, bc.cycle_year, bc.cycle_month
      from billing_cycles bc
     order by bc.cycle_year desc, bc.cycle_month desc
  loop
    -- Readings in this cycle whose reading_date says they belong elsewhere.
    update meter_readings r
       set billing_cycle_id = target.id
      from billing_cycles target
     where r.billing_cycle_id = c.id
       and target.cycle_year  = extract(year  from r.reading_date)::smallint
       and target.cycle_month = extract(month from r.reading_date)::smallint
       and target.id <> c.id;

    -- The bill follows its reading. bills.meter_reading_id is NOT NULL and
    -- UNIQUE, so this is one bill per moved reading and never a guess.
    update bills b
       set billing_cycle_id = r.billing_cycle_id
      from meter_readings r
     where b.meter_reading_id = r.id
       and b.billing_cycle_id <> r.billing_cycle_id;
  end loop;
end $$;


-- ---------------------------------------------------------------------
-- 4. Bring the bill numbers back into agreement with the month.
--
-- bill_no is 'BA-' || to_char(period_start,'YYYYMM') || '-' || a six-digit
-- serial. The serial comes from one global sequence, so it is unique on its
-- own and re-prefixing can never collide.
--
-- This DOES change identifiers that have already been shown to households
-- and quoted in SMS. It is done anyway because the alternative is a bill
-- headed "August 2026" carrying the number BA-202607-000902, which reads as
-- a fault every time anyone looks at it. To keep the numbers exactly as
-- issued instead, delete this one statement — nothing else depends on it,
-- and bill_no is a foreign key to nothing.
-- ---------------------------------------------------------------------
update bills b
   set bill_no = 'BA-' || to_char(c.period_start, 'YYYYMM') || '-'
                       || split_part(b.bill_no, '-', 3)
  from billing_cycles c
 where c.id = b.billing_cycle_id
   and split_part(b.bill_no, '-', 2) <> to_char(c.period_start, 'YYYYMM');

commit;


-- ---------------------------------------------------------------------
-- 5. What it looks like afterwards. reading_month_matches must be true on
--    every row that has a reading.
-- ---------------------------------------------------------------------
select
  c.cycle_year,
  c.cycle_month,
  to_char(c.period_start, 'FMMonth YYYY') as cycle_label,
  min(r.reading_date)                     as read_on,
  min(b.due_date)                         as due_on,
  count(distinct b.id)                    as bills,
  bool_and(
    extract(month from r.reading_date)::smallint = c.cycle_month
  )                                       as reading_month_matches
from billing_cycles c
left join meter_readings r on r.billing_cycle_id = c.id
left join bills b          on b.billing_cycle_id = c.id
group by c.cycle_year, c.cycle_month, c.period_start
order by c.cycle_year, c.cycle_month;
