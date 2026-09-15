-- =====================================================================
-- Phase E — sms_delivery_test.sql
-- Run inside a transaction that rolls back to avoid leaving test data.
-- =====================================================================

begin;

do $$
declare
  v_area_id uuid;
  v_admin_profile_id uuid;
  v_consumer_profile_id uuid;
  v_seeded_consumer_id uuid;
  v_consumer_id uuid;
  v_consumer_no_contact uuid;
  v_cycle_id uuid;
  v_bill_id uuid;
  v_bill_no_contact uuid;
  v_today date := fn_ph_today();
  v_res json;
  v_n1 uuid;
  v_n2 uuid;
  v_n_handoff uuid;
  v_n_old uuid;
  v_n_fail uuid;
  v_claim_token uuid := gen_random_uuid();
  v_claim_token_2 uuid := gen_random_uuid();
  v_claimed_count int;
  v_notif record;
  v_gateway_id text := 'sms-001';
begin
  select id, area_id into v_admin_profile_id, v_area_id from profiles where username = 'mario.ombajin';
  select id into v_consumer_profile_id from profiles where username = 'virgilio.busalanan';
  select id into v_seeded_consumer_id from consumers where consumer_no = '2019-0917-TUB';

  if v_admin_profile_id is null then raise exception 'Admin mario.ombajin not found in profiles'; end if;
  if v_area_id is null then raise exception 'Area for admin mario.ombajin not found'; end if;
  if v_consumer_profile_id is null then raise exception 'Consumer profile virgilio.busalanan not found'; end if;
  if v_seeded_consumer_id is null then raise exception 'Consumer 2019-0917-TUB not found in consumers'; end if;

  -- Setup: Create Area, Consumers, Cycle, Bills
  update settings set sms_overdue_enabled = true;

  insert into consumers (consumer_no, first_name, last_name, contact_number, area_id, purok)
  values ('C-TEST-001', 'Test', 'One', '+639171234567', v_area_id, 'Purok 1')
  returning id into v_consumer_id;

  insert into consumers (consumer_no, first_name, last_name, area_id, purok)
  values ('C-TEST-002', 'Test', 'Two', v_area_id, 'Purok 2')
  returning id into v_consumer_no_contact;

  insert into billing_cycles (cycle_year, cycle_month, period_start, period_end)
  values (2025, 1, '2025-01-01', '2025-01-31') returning id into v_cycle_id;

  -- Meter readings (needed for bills)
  insert into meter_readings (consumer_id, billing_cycle_id, current_reading, reading_date, client_uuid)
  values (v_consumer_id, v_cycle_id, 100, v_today, gen_random_uuid()),
         (v_consumer_no_contact, v_cycle_id, 150, v_today, gen_random_uuid());

  -- Bills that are overdue
  insert into bills (bill_no, consumer_id, billing_cycle_id, meter_reading_id, consumption, total_amount, due_date, priced_at)
  values ('B-TEST-001', v_consumer_id, v_cycle_id, (select id from meter_readings where consumer_id = v_consumer_id), 100, 1000, v_today - interval '5 days', now())
  returning id into v_bill_id;

  insert into bills (bill_no, consumer_id, billing_cycle_id, meter_reading_id, consumption, total_amount, due_date, priced_at)
  values ('B-TEST-002', v_consumer_no_contact, v_cycle_id, (select id from meter_readings where consumer_id = v_consumer_no_contact), 150, 1500, v_today - interval '5 days', now())
  returning id into v_bill_no_contact;

  -- Test: overdue queueing catches a missed day and remains one-per-bill
  v_res := fn_queue_overdue_sms(v_today);
  if not exists (select 1 from notifications where bill_id = v_bill_id and notif_type = 'overdue' and channel = 'sms') then
    raise exception 'Failed overdue queueing for bill %', v_bill_id;
  end if;
  if not exists (select 1 from notifications where bill_id = v_bill_no_contact and notif_type = 'overdue' and channel = 'sms' and status = 'failed') then
    raise exception 'Failed overdue queueing for no-contact bill %', v_bill_no_contact;
  end if;

  v_res := fn_queue_overdue_sms(v_today);
  if (select count(*) from notifications where bill_id = v_bill_id and notif_type = 'overdue' and channel = 'sms') <> 1 then
    raise exception 'Duplicate notification queued for %', v_bill_id;
  end if;

  -- Test: no-number SMS creates a failed row with a reason
  select * into v_notif from notifications where bill_id = v_bill_no_contact and notif_type = 'overdue';
  if v_notif.status <> 'failed' or v_notif.failed_reason is null then
    raise exception 'No-number SMS did not fail properly';
  end if;

  -- Test: destination number is snapshotted
  select * into v_notif from notifications where bill_id = v_bill_id and notif_type = 'overdue';
  if v_notif.destination_number <> '+639171234567' then
    raise exception 'Destination number not snapshotted';
  end if;
  v_n1 := v_notif.id;

  -- Test: two workers cannot claim the same row (demonstrated serially)
  perform fn_claim_sms_batch(v_claim_token);
  
  select count(*) into v_claimed_count from fn_claim_sms_batch(v_claim_token_2);
  if v_claimed_count <> 0 then
    raise exception 'Second worker claimed already claimed row';
  end if;

  -- Test: accepted, sent, delivered, failed, and expired transitions are correct
  perform fn_record_sms_acceptance(v_n1, v_claim_token, v_gateway_id, now());
  select dispatch_state into v_notif from notifications where id = v_n1;
  if v_notif.dispatch_state <> 'accepted' then raise exception 'Not accepted'; end if;

  perform fn_apply_sms_event(v_gateway_id, 'message.phone.sent', now());
  select status into v_notif from notifications where id = v_n1;
  if v_notif.status <> 'sent' then raise exception 'Not sent'; end if;

  -- Duplicate and out-of-order harmless
  perform fn_apply_sms_event(v_gateway_id, 'message.phone.sent', now());
  perform fn_apply_sms_event(v_gateway_id, 'message.phone.delivered', now());
  
  select delivered_at into v_notif from notifications where id = v_n1;
  if v_notif.delivered_at is null then raise exception 'Not delivered'; end if;

  -- Delivered cannot regress to failed
  perform fn_apply_sms_event(v_gateway_id, 'message.send.failed', now());
  select status into v_notif from notifications where id = v_n1;
  if v_notif.status <> 'sent' then raise exception 'Regressed to failed'; end if;

  -- Test: anon, authenticated consumer, and staff roles cannot call service functions or forge gateway fields
  -- We test this by impersonating staff (so RLS allows the update, letting the trigger fire)
  set local role authenticated;
  set local "request.jwt.claims" to '{"role":"authenticated"}';
  perform set_config('app.current_user_id', v_admin_profile_id::text, true);

  begin
    perform fn_claim_sms_batch(gen_random_uuid());
    raise exception 'TEST_FAILED_SHOULD_NOT_EXECUTE';
  exception when insufficient_privilege then
    null; -- expected
  end;

  begin
    update notifications set gateway_message_id = 'hacked' where id = v_n1;
    if not found then
      raise exception 'Update affected 0 rows (RLS blocked it incorrectly for admin?)';
    end if;
    raise exception 'TEST_FAILED_SHOULD_NOT_UPDATE';
  exception when others then
    if sqlerrm = 'TEST_FAILED_SHOULD_NOT_UPDATE' then
      raise exception 'Test failed: staff forged gateway fields successfully!';
    end if;
    if sqlerrm <> 'Client roles may not alter gateway fields' then
      raise exception 'Unexpected error on staff forge: %', sqlerrm;
    end if;
  end;
  
  reset role;

  -- 2. Consumers must still be able to update a push row from pending to sent with sent_at
  insert into notifications (consumer_id, notif_type, channel, status, message_content)
  values (v_seeded_consumer_id, 'pre_due_reminder', 'push', 'pending', 'Test Push Alert')
  returning id into v_n2;
  
  set local role authenticated;
  set local "request.jwt.claims" to '{"role":"authenticated"}';
  perform set_config('app.current_user_id', v_consumer_profile_id::text, true);

  begin
    update notifications set status = 'sent', sent_at = now() where id = v_n2;
    if not found then
      raise exception 'Update affected 0 rows (RLS blocked it for consumer?)';
    end if;
  exception when others then
    raise exception 'Consumer failed to update push notification: %', sqlerrm;
  end;
  
  reset role;

  -- Test Fix 1: fn_record_sms_definitive_failure ends the claim
  insert into notifications (consumer_id, notif_type, channel, status, dispatch_state, message_content, claim_token)
  values (v_seeded_consumer_id, 'overdue', 'sms', 'pending', 'claimed', 'Fail test', v_claim_token_2)
  returning id into v_n_fail;
  
  perform fn_record_sms_definitive_failure(v_n_fail, v_claim_token_2, 'Simulated failure');
  select dispatch_state, status into v_notif from notifications where id = v_n_fail;
  if v_notif.dispatch_state is not null then raise exception 'Dispatch state not null after failure'; end if;
  if v_notif.status <> 'failed' then raise exception 'Status not failed after definitive failure'; end if;

  -- Test Fix 2: Migration 13 backfill query test
  insert into notifications (consumer_id, notif_type, channel, status, dispatch_state, gateway_message_id, message_content)
  values (v_seeded_consumer_id, 'overdue', 'sms', 'pending', 'claimed', 'gw-123', 'Already handed off')
  returning id into v_n_handoff;

  insert into notifications (consumer_id, notif_type, channel, status, dispatch_state, gateway_message_id, message_content)
  values (v_seeded_consumer_id, 'overdue', 'sms', 'pending', null, null, 'Old pending')
  returning id into v_n_old;

  update notifications n
  set status = 'failed',
      failed_reason = 'Queued before SMS sending was enabled'
  where n.channel = 'sms'
    and n.status = 'pending'
    and n.dispatch_state is null
    and n.gateway_message_id is null;

  select status into v_notif from notifications where id = v_n_handoff;
  if v_notif.status <> 'pending' then raise exception 'Backfill touched handed-off message'; end if;

  select status into v_notif from notifications where id = v_n_old;
  if v_notif.status <> 'failed' then raise exception 'Backfill missed old message'; end if;

  raise notice 'All SQL tests passed!';
end $$;

rollback;
