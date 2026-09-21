-- =====================================================================
-- BillAlert — 18_remit_handovers.sql
--
-- The Cashier records handing the month's BOHECO money to the Meter Reader.
--
-- The Cashier takes the cash at the counter; on the 28th the Meter Reader
-- carries BOHECO's part to the office. Until now nothing recorded that the
-- money changed hands, or how much. This adds one row per area per month,
-- written by the Cashier, with the amounts frozen at that moment:
--   * to_boheco   what the reader was given for the BOHECO office;
--   * reader_pay  the reader's pay from the rounding (at most 300);
--   * gap         what the month's bills still owed BOHECO then.
-- Frozen because later payments change fn_rounding_fund's figures, and a
-- record of a handover must keep saying what was actually handed over.
--
-- Only the Cashier and the Area President of the area can read it. The
-- Meter Reader's app does not show the rounding or the pay.
--
-- Run after 17_bill_cooperative_amount.sql, which defines fn_rounding_fund.
-- =====================================================================

begin;

create table if not exists remit_handovers (
  id           uuid primary key default gen_random_uuid(),
  area_id      uuid not null references areas(id),
  remit_month  date not null check (extract(day from remit_month) = 1),
  to_boheco    numeric(12,2) not null check (to_boheco >= 0),
  reader_pay   numeric(12,2) not null check (reader_pay >= 0 and reader_pay <= 300),
  gap          numeric(12,2) not null check (gap >= 0),
  handed_by    uuid not null references profiles(id),
  handed_to    uuid references profiles(id),
  handed_to_name text,
  handed_at    timestamptz not null default now(),
  constraint uq_remit_handover_area_month unique (area_id, remit_month)
);

comment on table remit_handovers is
  'One per area per remittance month: the Cashier handing BOHECO''s part of the collections to the Meter Reader. Amounts frozen at the handover.';

alter table remit_handovers enable row level security;

drop policy if exists remit_handovers_select on remit_handovers;
create policy remit_handovers_select on remit_handovers
  for select using (
    app.current_role() in ('admin','cashier') and area_id = app.current_area()
  );
-- No insert, update or delete policy: rows are written only through
-- fn_record_remit_handover below, and never changed afterwards.

grant select on remit_handovers to authenticated;


-- The Cashier marks p_month (any day in it) as handed over. Takes the
-- figures from fn_rounding_fund at this moment. Refuses a second record for
-- the same month.
create or replace function fn_record_remit_handover(p_month date)
returns remit_handovers
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_area   uuid := app.current_area();
  v_month  date := date_trunc('month', p_month)::date;
  f        record;
  v_reader profiles%rowtype;
  v_row    remit_handovers;
begin
  if app.current_role() is distinct from 'cashier'::user_role then
    raise exception 'Only the Cashier can record a handover';
  end if;
  if exists (select 1 from remit_handovers
              where area_id = v_area and remit_month = v_month) then
    raise exception 'The handover for % is already recorded',
      to_char(v_month, 'FMMonth YYYY');
  end if;

  select * into f from fn_rounding_fund(v_area) r where r.remit_month = v_month;
  if not found then
    raise exception 'Nothing was collected for % yet',
      to_char(v_month, 'FMMonth YYYY');
  end if;

  select * into v_reader from profiles
   where role = 'meter_reader' and area_id = v_area and account_status = 'active'
   order by created_at desc limit 1;

  insert into remit_handovers (
    area_id, remit_month, to_boheco, reader_pay, gap,
    handed_by, handed_to, handed_to_name
  ) values (
    v_area, v_month, f.to_boheco, f.reader_pay, f.gap,
    app.current_user_id(), v_reader.id,
    nullif(trim(coalesce(v_reader.first_name, '') || ' ' || coalesce(v_reader.last_name, '')), '')
  )
  returning * into v_row;

  return v_row;
end $$;

revoke all on function fn_record_remit_handover(date) from public, anon;
grant execute on function fn_record_remit_handover(date) to authenticated;

commit;
