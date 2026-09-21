-- LOCAL database only, after migrations 01-15. No SMS is sent.
-- Uses an existing local household; all test rows are rolled back.
begin;
do $$
declare
  v_consumer uuid;
  v_id uuid;
  v_other uuid;
  v_claim uuid := gen_random_uuid();
  v_gateway text;
  v_event text;
  v_first boolean;
  v_row notifications%rowtype;
  v_at timestamptz := '2026-09-19 00:00:00+00';
begin
  select id into v_consumer from consumers limit 1;
  if v_consumer is null then raise exception 'Load a local household fixture first'; end if;

  foreach v_first in array array[true, false] loop
    foreach v_event in array array['message.phone.sent', 'message.phone.delivered',
                                   'message.send.failed', 'message.send.expired'] loop
      v_id := gen_random_uuid();
      v_gateway := 'ordering-' || v_id::text;
      insert into notifications(id, consumer_id, notif_type, channel,
        message_content, status, dispatch_state, claim_token)
      values(v_id, v_consumer, 'overdue', 'sms', 'Local ordering test',
        'pending', 'claimed', v_claim);

      if not v_first then
        perform fn_record_sms_acceptance(v_id, v_claim, v_gateway, v_at);
        select * into v_row from notifications where id = v_id;
        if v_row.dispatch_state is distinct from 'accepted' then
          raise exception 'Acceptance did not advance pending claim';
        end if;
      end if;
      perform fn_apply_sms_event(v_gateway, v_event, v_at, 'Local fixture reason', v_id::text);
      -- Assert immediately after late acceptance; a replayed webhook must not
      -- accidentally hide a regression caused by that acceptance.
      perform fn_record_sms_acceptance(v_id, v_claim, v_gateway, v_at);
      select * into v_row from notifications where id = v_id;
      if v_row.gateway_message_id is distinct from v_gateway
         or v_row.accepted_at is distinct from v_at
         or v_row.dispatch_state is not null then
        raise exception 'Binding/acceptance regressed: %, webhook first %', v_event, v_first;
      end if;
      if v_event in ('message.phone.sent', 'message.phone.delivered') then
        if v_row.status is distinct from 'sent' or v_row.sent_at is distinct from v_at then
          raise exception 'Sent status lost: %', v_event;
        end if;
      elsif v_row.status is distinct from 'failed' then
        raise exception 'Final failure lost: %', v_event;
      end if;
      perform fn_apply_sms_event(v_gateway, v_event, v_at, 'Local fixture reason', v_id::text);
      if v_event = 'message.phone.delivered' then
        perform fn_apply_sms_event(v_gateway, 'message.send.failed', v_at, 'Late failure');
        select * into v_row from notifications where id = v_id;
        if v_row.delivered_at is distinct from v_at or v_row.status is distinct from 'sent' then
          raise exception 'Delivered status regressed';
        end if;
      end if;
    end loop;
  end loop;

  -- Gateway binding wins over a contradictory request ID.
  v_other := gen_random_uuid();
  insert into notifications(id, consumer_id, notif_type, channel, message_content)
  values(v_other, v_consumer, 'overdue', 'sms', 'Local untouched test');
  perform fn_apply_sms_event(v_gateway, 'message.phone.delivered', v_at, null, v_other::text);
  select * into v_row from notifications where id = v_other;
  if v_row.gateway_message_id is not null or v_row.status is distinct from 'pending' then
    raise exception 'Request ID overrode established gateway binding';
  end if;

  -- Unknown events must not be silently acknowledged; malformed IDs are safe.
  begin
    perform fn_apply_sms_event('unknown', 'message.phone.sent', v_at, null, 'not-a-uuid');
    raise exception 'TEST: unmatched event was acknowledged';
  exception when raise_exception then
    if sqlerrm <> 'SMS event has no matching notification' then raise; end if;
  end;
  -- Cannot replace an existing binding using a request ID.
  begin
    perform fn_apply_sms_event('different', 'message.phone.sent', v_at, null, v_id::text);
    raise exception 'TEST: gateway binding was replaced';
  exception when raise_exception then
    if sqlerrm <> 'SMS event has no matching notification' then raise; end if;
  end;

  if has_function_privilege('anon', 'public.fn_apply_sms_event(text,text,timestamptz,text,text)', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.fn_apply_sms_event(text,text,timestamptz,text,text)', 'EXECUTE')
     or not has_function_privilege('service_role', 'public.fn_apply_sms_event(text,text,timestamptz,text,text)', 'EXECUTE') then
    raise exception 'Service-only SMS grants are incorrect';
  end if;
  raise notice 'PASS: both event orders, replay, final states, binding precedence, unmatched events and grants';
end $$;
rollback;
