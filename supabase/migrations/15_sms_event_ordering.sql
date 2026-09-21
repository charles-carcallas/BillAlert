-- Apply after 13_sms_delivery.sql and 14_bill_sms.sql.
-- Independent of the existing 15_bill_meter_readings.sql; retain both files.
-- Then redeploy httpsms-webhook and send-sms. No client grants are added.
begin;

-- Five arguments deliberately have no defaults: the old four-argument
-- signature remains an unambiguous compatibility wrapper for older callers.
create or replace function public.fn_apply_sms_event(
  p_gateway_id text, p_event_type text, p_event_at timestamptz,
  p_reason text, p_request_id text
) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_id uuid;
begin
  if nullif(p_gateway_id, '') is null then
    raise exception 'Missing gateway ID';
  end if;
  if p_event_type not in ('message.phone.sent', 'message.phone.delivered',
                         'message.send.failed', 'message.send.expired') then
    raise exception 'Unsupported SMS event';
  end if;

  -- Prefer the established binding, even if request_id names another row.
  select id into v_id from notifications
  where channel = 'sms' and gateway_message_id = p_gateway_id
  for update;
  if v_id is null then
    -- Compare as text so malformed/external request IDs cannot cause a UUID
    -- cast failure. Never rebind a row already associated with another send.
    select id into v_id from notifications
    where channel = 'sms' and id::text = p_request_id
      and (gateway_message_id is null or gateway_message_id = p_gateway_id)
    for update;
  end if;
  if v_id is null then
    -- Do not acknowledge a lost event. The webhook returns 500 for RPC errors.
    raise exception 'SMS event has no matching notification';
  end if;

  update notifications set gateway_message_id = p_gateway_id where id = v_id;
  if p_event_type = 'message.phone.sent' then
    update notifications
    set status = 'sent', sent_at = coalesce(sent_at, p_event_at),
        dispatch_state = null, failed_reason = null
    where id = v_id and status = 'pending';
  elsif p_event_type = 'message.phone.delivered' then
    update notifications
    set status = 'sent', sent_at = coalesce(sent_at, p_event_at),
        delivered_at = coalesce(delivered_at, p_event_at),
        dispatch_state = null, failed_reason = null
    where id = v_id;
  else
    -- The webhook filters non-final expiry before calling this function.
    update notifications
    set status = 'failed', failed_reason = coalesce(p_reason, 'Provider reported failure'),
        dispatch_state = null
    where id = v_id and delivered_at is null;
  end if;
end $$;

create or replace function public.fn_apply_sms_event(
  p_gateway_id text, p_event_type text, p_event_at timestamptz,
  p_reason text default null
) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform public.fn_apply_sms_event(p_gateway_id, p_event_type, p_event_at, p_reason, null);
end $$;

create or replace function public.fn_record_sms_acceptance(
  p_notification uuid, p_claim uuid, p_gateway_id text, p_accepted_at timestamptz
) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  -- The row lock taken by UPDATE serializes this with webhook processing.
  -- Late acceptance may fill metadata but must never reset a final status.
  update notifications
  set gateway_message_id = coalesce(gateway_message_id, p_gateway_id),
      accepted_at = coalesce(accepted_at, p_accepted_at),
      last_attempted_at = now(),
      dispatch_state = case
        when status = 'pending' and delivered_at is null
          and dispatch_state = 'claimed' then 'accepted'
        else dispatch_state end
  where id = p_notification and channel = 'sms' and claim_token = p_claim
    and (gateway_message_id is null or gateway_message_id = p_gateway_id);
end $$;

revoke all on function public.fn_apply_sms_event(text,text,timestamptz,text,text) from public, anon, authenticated;
grant execute on function public.fn_apply_sms_event(text,text,timestamptz,text,text) to service_role;
revoke all on function public.fn_apply_sms_event(text,text,timestamptz,text) from public, anon, authenticated;
grant execute on function public.fn_apply_sms_event(text,text,timestamptz,text) to service_role;
revoke all on function public.fn_record_sms_acceptance(uuid,uuid,text,timestamptz) from public, anon, authenticated;
grant execute on function public.fn_record_sms_acceptance(uuid,uuid,text,timestamptz) to service_role;
commit;
