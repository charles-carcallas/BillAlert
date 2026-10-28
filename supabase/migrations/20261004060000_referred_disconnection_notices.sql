-- Apply after reserve fund and billing schedule migrations. Preserves existing notices.
begin;
create or replace function fn_issue_disconnection_notice(
  p_consumer_id uuid,
  p_reason      text default null,
  p_served_at   timestamptz default now(),
  p_client_uuid uuid default gen_random_uuid()
) returns uuid
language plpgsql set search_path=public,pg_temp as $$
declare
  v_existing  uuid;
  v_notice_id uuid;
  v_lawful    timestamptz;
  v_consumer  consumers%rowtype;
  v_reason    text;
  v_msg       text;
  v_notice_no text;
  v_amount numeric;
begin
  perform app.lock_own_area();
  if app.current_role() <> 'admin' then raise exception 'Admin work access required'; end if;
  select id into v_existing from disconnection_notices where client_uuid = p_client_uuid;
  if v_existing is not null then
    return v_existing;                                     -- MTR-12 idempotent
  end if;

  select * into v_consumer from consumers where id = p_consumer_id;
  if not found then
    raise exception 'Consumer % not found or not visible to you', p_consumer_id;
  end if;

  -- Revalidate the current route on sync; queued/offline notices may be stale.
  select sum(b.balance) into v_amount
  from bills b join bill_settlements s on s.bill_id=b.id
  where b.consumer_id=p_consumer_id and b.balance>0 and b.waiver_amount=0
    and b.due_date < fn_ph_today(least(p_served_at,now()))
    and s.route='boheco' and s.state='referred' and s.referred_at<=p_served_at
    and not exists(select 1 from boheco_payment_evidence e where e.bill_id=b.id and e.reversed_at is null);
  if coalesce(v_amount,0)<=0 then
    raise exception 'Notice requires an overdue unpaid bill with confirmed BOHECO referral';
  end if;

  v_lawful := fn_earliest_lawful_disconnection(p_served_at);
  v_reason := coalesce(nullif(trim(p_reason), ''), 'Unpaid electricity bill');

  -- "DN-2026-0819-0033"
  v_notice_no := 'DN-' || to_char(p_served_at at time zone 'Asia/Manila', 'YYYY-MMDD')
                 || '-' || lpad(nextval('notice_no_seq')::text, 4, '0');

  insert into disconnection_notices (
    notice_no, consumer_id, reason, served_at, earliest_lawful_at, issued_by, client_uuid
  ) values (
    v_notice_no, p_consumer_id, v_reason, p_served_at, v_lawful,
    app.current_user_id(), p_client_uuid
  ) returning id into v_notice_id;

  v_msg := format(
    'NOTICE %s: Account %s has PHP %s unpaid past due date and has been referred to BOHECO for possible disconnection. '
    || 'Please pay at the BOHECO main office. If already paid, contact your Meter Reader for verification. Reason: %s.',
    v_notice_no, v_consumer.consumer_no, v_amount, v_reason
  );

  -- Objective 3: disconnection notices go by SMS, so they reach a consumer
  -- who does not open the app.
  perform fn_queue_notification(
    p_consumer_id, 'disconnection', 'sms', v_msg, null, v_notice_id, null
  );

  return v_notice_id;
end $$;
create or replace function app.capture_notice_bills() returns trigger language plpgsql security definer
set search_path=public,pg_temp as $$
begin
 insert into notice_bill_items(notice_id,bill_id,amount_at_issue)
 select new.id,b.id,b.balance from bills b join bill_settlements s on s.bill_id=b.id
 where b.consumer_id=new.consumer_id and b.balance>0 and b.waiver_amount=0
 and b.due_date<fn_ph_today(least(new.served_at,now()))
 and s.route='boheco' and s.state='referred' and s.referred_at<=new.served_at
 and not exists(select 1 from boheco_payment_evidence e where e.bill_id=b.id and e.reversed_at is null);
 return new;
end $$;
revoke all on function app.capture_notice_bills() from public,anon,authenticated;

commit;
