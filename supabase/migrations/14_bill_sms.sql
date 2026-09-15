-- =====================================================================
-- BillAlert — 14_bill_sms.sql
--
-- Bill-ready alerts also go out as a text.
--
-- Objective 3 kept SMS for overdue and disconnection notices only, because
-- every text costs load and the bill-ready alert is the message BillAlert
-- sends most. That left a household with only a keypad phone no way to learn
-- its bill was ready: the app notification needs the app. Decided 2026-09-15:
-- every household gets the bill by text as well as in the app.
--
-- The app alert stays the alert of record (settings.billready_channel, push
-- by default). The text is a second row beside it:
--   • queued ready for send-sms when the household has a mobile number;
--   • FAILED with the reason when it has none (SYS-04), so the Area
--     President can see whose number is missing;
--   • stored already read, so the Inbox badge does not count one bill
--     twice. The app leaves the copy out of the Inbox list for the same
--     reason (withoutTextCopies in notification_repository.dart);
--   • switched off for everyone with settings.billready_sms_enabled = false,
--     for when the gateway SIM runs out of load.
--
-- Run after 13_sms_delivery.sql. send-sms needs no change: the copy is an
-- ordinary queued text.
-- =====================================================================

alter table settings
  add column if not exists billready_sms_enabled boolean not null default true;

-- The rule was one alert per bill per type. It is now one per bill per type
-- per channel. Otherwise the text copy collides with the app alert, and the
-- "on conflict do nothing" below drops it without a word.
drop index if exists uq_notif_one_per_bill_type;
create unique index if not exists uq_notif_one_per_bill_type_channel
  on notifications (bill_id, notif_type, channel)
  where bill_id is not null and notif_type in ('bill_ready','pre_due_reminder','overdue');


-- FR-21b, as in 02_functions.sql, plus the text copy.
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
     set total_amount = ceil(p_amount),
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
