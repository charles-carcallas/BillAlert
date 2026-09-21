-- =====================================================================
-- BillAlert — 17_bill_cooperative_amount.sql
--
-- Keep the cooperative's own amount beside the rounded bill.
--
-- The Area President types BOHECO's figure (say 529.40) and the household
-- is billed the whole-peso ceiling (530.00). The 0.60 difference is the
-- Meter Reader's pay. Until now only the rounded figure was stored, so
-- nobody could tell afterwards how much of the money collected was owed to
-- BOHECO and how much the reader keeps, and Remit told the reader to hand
-- over all of it.
--
-- What this adds:
--   * bills.cooperative_amount: BOHECO's figure, set when the amount is
--     posted. Null for bills posted before this migration (never guessed).
--   * v_payment_history.boheco_share: how much of each payment line is
--     owed to BOHECO. Payments go to BOHECO first and the rounding last, so
--     a household that pays part of a bill has paid BOHECO before the
--     reader. Null where the bill has no cooperative_amount.
--
--   * fn_rounding_fund(area): month by month, the rounding money, the
--     Meter Reader's pay from it and the fund saved from the rest. For the
--     Cashier and the Area President only; the Meter Reader's app does not
--     show a share.
--
-- The rules, decided 2026-09-19:
--   * A remittance month runs from the 29th of the month before through the
--     28th, in Manila, as on the Remit screen.
--   * The rounding collected in the month, plus the fund carried over, is
--     what is available.
--   * BOHECO first: enough of that is kept back to cover what the month's
--     bills still owe BOHECO at the handover (the gap). It is NOT handed
--     over automatically; the Cashier sees it and decides.
--   * Then the Meter Reader is paid, at most 300 pesos a month.
--   * Everything else stays in the fund and carries over.
--
-- The household still sees only the rounded amount.
--
-- Run after 14_bill_sms.sql (and after 15 and 16). The app sends BOHECO's
-- figure as p_amount; an older app build sends the already-rounded figure,
-- which stores a cooperative_amount equal to the bill (a share of zero).
-- =====================================================================

begin;

alter table bills
  add column if not exists cooperative_amount numeric(12,2);

alter table bills drop constraint if exists bills_cooperative_amount_rounds_up;
alter table bills
  add constraint bills_cooperative_amount_rounds_up check (
    cooperative_amount is null
    or (total_amount is not null
        and cooperative_amount > 0
        and cooperative_amount <= total_amount
        and total_amount - cooperative_amount < 1)
  );

comment on column bills.cooperative_amount is
  'BOHECO''s own amount for this bill, before the whole-peso ceiling. total_amount - cooperative_amount is the Meter Reader''s share. Null for bills posted before 17_bill_cooperative_amount.sql.';


-- FR-21b, as in 14_bill_sms.sql, plus cooperative_amount.
create or replace function fn_post_bill_amount(
  p_bill_id    uuid,
  p_amount     numeric,
  p_due_date   date,
  p_posted_at  timestamptz default now()
) returns uuid
language plpgsql as $$
declare
  s        settings%rowtype;
  v_bill   bills%rowtype;
  v_msg    text;
  v_notif  uuid;
begin
  if app.current_user_id() is not null and not app.is_admin() then
    raise exception 'Only an Admin may post a bill amount';
  end if;

  select * into s from settings where id = 1;

  select * into v_bill from bills where id = p_bill_id for update;
  if not found then
    raise exception 'Bill % not found or not visible to you', p_bill_id;
  end if;
  if v_bill.total_amount is not null then
    raise exception 'Bill % already has an amount of %; it cannot be re-posted',
      v_bill.bill_no, v_bill.total_amount;
  end if;
  if p_amount is null or p_amount <= 0 then
    raise exception 'The amount due must be greater than zero';
  end if;
  if p_due_date is null then
    raise exception 'A due date must be supplied with the amount';
  end if;
  if p_due_date < fn_ph_today(p_posted_at) then
    raise exception 'The due date (%) is already in the past', p_due_date;
  end if;

  update bills
     set total_amount       = ceil(p_amount),
         cooperative_amount = p_amount,
         due_date     = p_due_date,
         priced_at    = p_posted_at,
         priced_by    = app.current_user_id()
   where id = p_bill_id;

  v_msg := fn_render_bill_message(p_bill_id);

  -- FR-13: the bill-ready alert fires HERE, not at capture.
  v_notif := fn_queue_notification(
    v_bill.consumer_id, 'bill_ready', s.billready_channel,
    v_msg, p_bill_id, null, v_bill.billing_cycle_id
  );

  -- The same bill by text, for a household whose phone cannot run the app.
  -- Written out rather than through fn_queue_notification, which has no way
  -- to store a row already read. For staff callers,
  -- fn_prepare_notification_insert sets the number and state the same way.
  if s.billready_sms_enabled and s.billready_channel <> 'sms' then
    insert into notifications (
      consumer_id, billing_cycle_id, bill_id, notif_type, channel,
      message_content, status, failed_reason, is_read,
      destination_number, dispatch_state
    )
    select c.id, v_bill.billing_cycle_id, p_bill_id,
           'bill_ready'::notification_type, 'sms'::notification_channel, v_msg,
           (case when c.contact_number is null then 'failed' else 'pending' end)::notification_status,
           case when c.contact_number is null
                then 'No contact number on file for this consumer' end,
           true,
           c.contact_number,
           case when c.contact_number is not null then 'ready' end
      from consumers c
     where c.id = v_bill.consumer_id
    on conflict do nothing;
  end if;

  return v_notif;
end $$;

-- As in 03_views.sql, with boheco_share APPENDED (create or replace view may
-- not reorder existing columns).
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
  c.first_name || ' ' || c.last_name as consumer_name,
  -- BOHECO is paid first: this line's share is the part of it that falls
  -- below cooperative_amount once earlier payments on the bill are counted.
  case when b.cooperative_amount is null then null
       else greatest(0,
              least(prior.paid_before + pay.amount_paid, b.cooperative_amount)
              - least(prior.paid_before, b.cooperative_amount))
  end as boheco_share
from payments pay
join payment_transactions pt on pt.id = pay.transaction_id
join bills b                 on b.id  = pay.bill_id
join billing_cycles bc       on bc.id = b.billing_cycle_id
join consumers c             on c.id  = pay.consumer_id
cross join lateral (
  select coalesce(sum(earlier.amount_paid), 0) as paid_before
    from payments earlier
   where earlier.bill_id = pay.bill_id
     and (earlier.paid_at, earlier.id) < (pay.paid_at, pay.id)
) prior;

alter view v_payment_history set (security_invoker = on);


-- Month by month, oldest first, for one area. Computed from the payments and
-- bills themselves, so there is no second ledger to fall out of step.
create or replace function fn_rounding_fund(p_area uuid)
returns table (
  remit_month   date,          -- first day of the month handed over on the 28th
  collected     numeric(12,2), -- all cash received in the window
  to_boheco     numeric(12,2), -- BOHECO's part of it (unsplit bills in full)
  rounding      numeric(12,2), -- the rest: the month's rounding money
  gap           numeric(12,2), -- what the month's bills still owed BOHECO on the 28th
  fund_before   numeric(12,2), -- carried over from earlier months
  kept_for_gap  numeric(12,2), -- held back to cover the gap, if the Cashier chooses
  reader_pay    numeric(12,2), -- the Meter Reader's pay, at most 300
  fund_after    numeric(12,2)  -- carried into the next month
)
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare
  c_cap   constant numeric := 300;
  v_first date;
  v_last  date;
  v_month date;
  v_end   timestamptz;
  v_fund  numeric(12,2) := 0;
  v_avail numeric(12,2);
begin
  if not (app.current_role() in ('admin','cashier') and p_area = app.current_area()) then
    raise exception 'Only the Cashier or the Area President of this area can see the rounding fund';
  end if;

  -- The month a payment is handed over in: its own month up to the 28th,
  -- the next one from the 29th.
  select min(date_trunc('month', (h.paid_at at time zone 'Asia/Manila')::date
                        + case when extract(day from h.paid_at at time zone 'Asia/Manila') > 28
                               then interval '1 month' else interval '0' end)::date)
    into v_first
    from v_payment_history h
   where h.area_id = p_area;

  if v_first is null then
    return;
  end if;

  v_last := date_trunc('month', fn_ph_today()
                       + case when extract(day from fn_ph_today()) > 28
                              then interval '1 month' else interval '0' end)::date;

  v_month := v_first;
  while v_month <= v_last loop
    -- Midnight at the start of the 29th in Manila. Day 29 of February in a
    -- common year rolls to 1 March, as it does on the Remit screen.
    v_end := ((v_month + 28)::timestamp) at time zone 'Asia/Manila';

    remit_month := v_month;

    select coalesce(sum(h.amount_paid), 0),
           coalesce(sum(coalesce(h.boheco_share, h.amount_paid)), 0)
      into collected, to_boheco
      from v_payment_history h
     where h.area_id = p_area
       and h.paid_at >= (((v_month - interval '1 month')::date + 28)::timestamp) at time zone 'Asia/Manila'
       and h.paid_at <  v_end;

    rounding := collected - to_boheco;

    -- The month's bills: BOHECO's amount, less BOHECO's part of what had been
    -- paid on each by the handover.
    select coalesce(sum(greatest(0,
             coalesce(b.cooperative_amount, b.total_amount)
             - coalesce((select sum(coalesce(h.boheco_share, h.amount_paid))
                           from v_payment_history h
                          where h.bill_id = b.id and h.paid_at < v_end), 0))), 0)
      into gap
      from bills b
      join consumers c       on c.id = b.consumer_id
      join billing_cycles bc on bc.id = b.billing_cycle_id
     where c.area_id = p_area
       and b.total_amount is not null
       and bc.cycle_year  = extract(year  from v_month)
       and bc.cycle_month = extract(month from v_month);

    fund_before  := v_fund;
    v_avail      := v_fund + rounding;
    kept_for_gap := least(gap, v_avail);
    reader_pay   := least(c_cap, v_avail - kept_for_gap);
    fund_after   := v_avail - reader_pay;
    v_fund       := fund_after;

    return next;
    v_month := (v_month + interval '1 month')::date;
  end loop;
end $$;

comment on function fn_rounding_fund(uuid) is
  'The rounding fund, month by month: collected, BOHECO''s part, rounding, gap on the 28th, fund carried over, amount kept for the gap, Meter Reader pay (max 300) and fund after. Cashier and Area President of the area only.';

revoke all on function fn_rounding_fund(uuid) from public, anon;
grant execute on function fn_rounding_fund(uuid) to authenticated;

commit;
