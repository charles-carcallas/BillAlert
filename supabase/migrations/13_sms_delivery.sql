-- =====================================================================
-- Phase A — migration 13_sms_delivery.sql
-- =====================================================================

-- A1. Add delivery metadata
alter table notifications
  add column if not exists destination_number text,
  add column if not exists gateway_message_id text,
  add column if not exists dispatch_state text check (dispatch_state in ('ready', 'claimed', 'accepted', 'uncertain')),
  add column if not exists claim_token uuid,
  add column if not exists claimed_at timestamptz,
  add column if not exists accepted_at timestamptz,
  add column if not exists last_attempted_at timestamptz,
  add column if not exists delivered_at timestamptz;

create unique index if not exists idx_notif_gateway_id on notifications(gateway_message_id) where gateway_message_id is not null;

alter table settings
  add column if not exists sms_overdue_enabled boolean not null default false;

-- Backfill: mark pre-existing pending SMS rows as failed
update notifications n
set status = 'failed',
    failed_reason = 'Queued before SMS sending was enabled'
where n.channel = 'sms'
  and n.status = 'pending'
  and n.dispatch_state is null
  and n.gateway_message_id is null;


-- A2. Update notification queuing
create or replace function fn_queue_notification(
  p_consumer_id      uuid,
  p_notif_type       notification_type,
  p_channel          notification_channel,
  p_message          text,
  p_bill_id          uuid default null,
  p_disconnection_id uuid default null,
  p_cycle_id         uuid default null
) returns uuid
language plpgsql as $$
declare
  v_contact text;
  v_id      uuid;
begin
  select contact_number into v_contact from consumers where id = p_consumer_id;

  insert into notifications (
    consumer_id, billing_cycle_id, bill_id, disconnection_id,
    notif_type, channel, message_content, status, failed_reason,
    destination_number, dispatch_state
  ) values (
    p_consumer_id, p_cycle_id, p_bill_id, p_disconnection_id,
    p_notif_type, p_channel, p_message,
    (case when p_channel = 'sms' and v_contact is null then 'failed' else 'pending' end)::notification_status,
    case when p_channel = 'sms' and v_contact is null
         then 'No contact number on file for this consumer' end,
    case when p_channel = 'sms' then v_contact else null end,
    case when p_channel = 'sms' and v_contact is not null then 'ready' else null end
  )
  on conflict do nothing
  returning id into v_id;

  return v_id;
end $$;


-- A3. Queue overdue notifications
create or replace function fn_queue_overdue_sms(p_today date default fn_ph_today())
returns json
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  s settings%rowtype;
  r record;
  v_msg text;
  v_queued int := 0;
  v_failed int := 0;
  v_present int := 0;
  v_id uuid;
begin
  select * into s from settings where id = 1;
  if not s.sms_overdue_enabled then
    return json_build_object('queued', 0, 'present', 0, 'failed', 0);
  end if;

  for r in (
    select b.id, b.consumer_id, b.billing_cycle_id, c.contact_number
    from bills b
    join consumers c on c.id = b.consumer_id
    where b.status in ('unpaid', 'partial')
      and b.total_amount is not null
      and b.due_date is not null
      and b.due_date + s.overdue_days_after <= p_today
      and not exists (
        select 1 from disconnection_notices dn
        where dn.consumer_id = b.consumer_id and dn.status = 'active'
      )
  ) loop
    if exists (
      select 1 from notifications n 
      where n.bill_id = r.id and n.notif_type = 'overdue'
    ) then
      v_present := v_present + 1;
      continue;
    end if;

    v_msg := 'Your bill is overdue. Please pay immediately.';
    v_id := fn_queue_notification(
      r.consumer_id,
      'overdue',
      s.overdue_channel,
      v_msg,
      r.id,
      null,
      r.billing_cycle_id
    );

    if r.contact_number is null and s.overdue_channel = 'sms' then
      v_failed := v_failed + 1;
    else
      v_queued := v_queued + 1;
    end if;
  end loop;

  return json_build_object(
    'queued', v_queued,
    'present', v_present,
    'failed', v_failed
  );
end $$;


-- A4. Claim a batch atomically
create or replace function fn_claim_sms_batch(p_claim_token uuid)
returns table(id uuid, destination_number text, message_content text)
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  return query
  with claimed as (
    select n.id
    from notifications n
    where n.channel = 'sms'
      and n.status = 'pending'
      and n.dispatch_state = 'ready'
      and n.destination_number is not null
      and n.gateway_message_id is null
      and n.retry_count < 3
    order by n.created_at asc
    limit 5
    for update skip locked
  )
  update notifications n
  set dispatch_state = 'claimed',
      claim_token = p_claim_token,
      claimed_at = now(),
      retry_count = n.retry_count + 1
  from claimed c
  where n.id = c.id
  returning n.id, n.destination_number, n.message_content;
end $$;


-- A5. Record outcomes
create or replace function fn_record_sms_acceptance(p_notification uuid, p_claim uuid, p_gateway_id text, p_accepted_at timestamptz)
returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  update notifications
  set gateway_message_id = p_gateway_id,
      dispatch_state = 'accepted',
      accepted_at = p_accepted_at,
      last_attempted_at = now()
  where id = p_notification
    and claim_token = p_claim
    and dispatch_state = 'claimed';
end $$;

create or replace function fn_record_sms_definitive_failure(p_notification uuid, p_claim uuid, p_reason text)
returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  update notifications
  set status = 'failed',
      failed_reason = p_reason,
      dispatch_state = null,
      last_attempted_at = now()
  where id = p_notification
    and claim_token = p_claim
    and dispatch_state = 'claimed';
end $$;

create or replace function fn_record_sms_uncertain(p_notification uuid, p_claim uuid, p_reason text)
returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  update notifications
  set dispatch_state = 'uncertain',
      failed_reason = p_reason,
      last_attempted_at = now()
  where id = p_notification
    and claim_token = p_claim
    and dispatch_state = 'claimed';
end $$;

create or replace function fn_apply_sms_event(p_gateway_id text, p_event_type text, p_event_at timestamptz, p_reason text default null)
returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if p_event_type = 'message.phone.sent' then
    update notifications
    set status = 'sent',
        sent_at = coalesce(sent_at, p_event_at)
    where gateway_message_id = p_gateway_id
      and status = 'pending';
  elsif p_event_type = 'message.phone.delivered' then
    update notifications
    set status = 'sent',
        sent_at = coalesce(sent_at, p_event_at),
        delivered_at = coalesce(delivered_at, p_event_at)
    where gateway_message_id = p_gateway_id;
  elsif p_event_type in ('message.send.failed', 'message.send.expired') then
    update notifications
    set status = 'failed',
        failed_reason = coalesce(p_reason, 'Provider reported failure')
    where gateway_message_id = p_gateway_id
      and delivered_at is null;
  end if;
end $$;


-- A6. Lock down access
revoke execute on function fn_queue_overdue_sms(date) from public, anon, authenticated;
grant execute on function fn_queue_overdue_sms(date) to service_role;

revoke execute on function fn_claim_sms_batch(uuid) from public, anon, authenticated;
grant execute on function fn_claim_sms_batch(uuid) to service_role;

revoke execute on function fn_record_sms_acceptance(uuid, uuid, text, timestamptz) from public, anon, authenticated;
grant execute on function fn_record_sms_acceptance(uuid, uuid, text, timestamptz) to service_role;

revoke execute on function fn_record_sms_definitive_failure(uuid, uuid, text) from public, anon, authenticated;
grant execute on function fn_record_sms_definitive_failure(uuid, uuid, text) to service_role;

revoke execute on function fn_record_sms_uncertain(uuid, uuid, text) from public, anon, authenticated;
grant execute on function fn_record_sms_uncertain(uuid, uuid, text) to service_role;

revoke execute on function fn_apply_sms_event(text, text, timestamptz, text) from public, anon, authenticated;
grant execute on function fn_apply_sms_event(text, text, timestamptz, text) to service_role;

create or replace function fn_protect_gateway_fields() returns trigger as $$
begin
  if current_user in ('anon', 'authenticated') then
    if new.destination_number is distinct from old.destination_number or
       new.gateway_message_id is distinct from old.gateway_message_id or
       new.dispatch_state is distinct from old.dispatch_state or
       new.claim_token is distinct from old.claim_token or
       new.claimed_at is distinct from old.claimed_at or
       new.accepted_at is distinct from old.accepted_at or
       new.last_attempted_at is distinct from old.last_attempted_at or
       new.delivered_at is distinct from old.delivered_at
    then
      raise exception 'Client roles may not alter gateway fields';
    end if;

    if app.current_role() = 'consumer'::user_role and old.channel = 'sms' then
       if new.status is distinct from old.status or
          new.failed_reason is distinct from old.failed_reason or
          new.sent_at is distinct from old.sent_at then
          raise exception 'Consumers may not alter delivery status';
       end if;
    end if;
  end if;
  return new;
end $$ language plpgsql;

drop trigger if exists trg_protect_gateway_fields on notifications;
create trigger trg_protect_gateway_fields
before update on notifications
for each row execute function fn_protect_gateway_fields();

create or replace function fn_prepare_notification_insert() returns trigger as $$
begin
  if current_user in ('anon', 'authenticated') then
    if new.channel = 'sms' then
      select contact_number into new.destination_number from consumers where id = new.consumer_id;
      new.gateway_message_id := null;
      new.claim_token := null;
      new.claimed_at := null;
      new.accepted_at := null;
      new.delivered_at := null;
      new.last_attempted_at := null;

      if new.destination_number is not null then
        new.dispatch_state := 'ready';
        new.status := 'pending';
      else
        new.dispatch_state := null;
        new.status := 'failed';
        new.failed_reason := 'No contact number on file for this consumer';
      end if;
    else
      new.destination_number := null;
      new.dispatch_state := null;
    end if;
  end if;
  return new;
end $$ language plpgsql;

drop trigger if exists trg_prepare_notification_insert on notifications;
create trigger trg_prepare_notification_insert
before insert on notifications
for each row execute function fn_prepare_notification_insert();
