-- DISPOSABLE LOCAL DATABASE ONLY, with 05 fixtures and migrations 19/20.
-- auth.uid() in the local harness reads request.jwt.claim.sub.
\set ON_ERROR_STOP on
begin;
create function pg_temp.assert_true(ok boolean, label text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'FAILED: %',label; end if; end $$;
create function pg_temp.denied(q text, expected text) returns void language plpgsql as $$
begin
  begin execute q; exception when others then
    if position(expected in sqlerrm)>0 then return; end if;
    raise exception 'Wrong refusal: % (expected %)',sqlerrm,expected;
  end;
  raise exception 'Unexpected permission: %',q;
end $$;
create temp table fixture(k text primary key,v uuid);
grant all on fixture to authenticated;

set local role authenticated;
select set_config('request.jwt.claim.sub','33333333-0000-0000-0000-000000000002',true);
insert into fixture values('old',fn_record_meter_reading('55555555-0000-0000-0000-000000000001',100,(date_trunc('month',now())-interval '1 month'+interval '5 days')::timestamptz,'aaaaaaaa-0000-0000-0000-000000000001'));
insert into fixture values('current',fn_record_meter_reading('55555555-0000-0000-0000-000000000001',110,now(),'aaaaaaaa-0000-0000-0000-000000000002'));
select pg_temp.assert_true((select count(*)=0 from staff_alerts),'Reader cannot see Admin alerts');
select set_config('request.jwt.claim.sub','33333333-0000-0000-0000-000000000001',true);
select pg_temp.assert_true((select count(*)=2 from staff_alerts),'Two Admin reading events');
select fn_post_bill_amount((select v from fixture where k='old'),99.40,fn_ph_today()+2,now(),'aaaaaaaa-0000-0000-0000-000000000003');
select fn_post_bill_amount((select v from fixture where k='old'),99.40,fn_ph_today()+2,now(),'aaaaaaaa-0000-0000-0000-000000000003');
select pg_temp.denied(format('select fn_post_bill_amount(%L,99.10,fn_ph_today()+2,now(),%L)',(select v from fixture where k='old'),'aaaaaaaa-0000-0000-0000-000000000003'),'conflicts');
select fn_post_bill_amount((select v from fixture where k='current'),200,fn_ph_today()+5,now(),'aaaaaaaa-0000-0000-0000-000000000004');
reset role;
-- Simulate passage of time on the synthetic older bill.
update bills set due_date=fn_ph_today()-1 where id=(select v from fixture where k='old');
set local role authenticated;
select set_config('request.jwt.claim.sub','33333333-0000-0000-0000-000000000003',true);
select pg_temp.assert_true((select count(*)=2 from staff_alerts),'Cashier bill-ready events');
select pg_temp.denied(format('update bills set amount_paid=1 where id=%L',(select v from fixture where k='old')),'permission denied');
select pg_temp.denied(format('select fn_record_payment(array[%L::uuid],array[200::numeric],200,now(),%L)',(select v from fixture where k='current'),'aaaaaaaa-0000-0000-0000-000000000005'),'Settle all overdue');
select pg_temp.denied(format('select fn_record_payment(array[%L::uuid],array[100::numeric],100,now(),%L)',(select v from fixture where k='old'),'aaaaaaaa-0000-0000-0000-000000000006'),'Admin authorization');
select fn_overdue_decision((select v from fixture where k='old'),'requested');
select fn_overdue_decision((select v from fixture where k='old'),'requested');
select pg_temp.denied(format('select fn_overdue_decision(%L,%L)',(select v from fixture where k='old'),'approved'),'Only the Admin');
select set_config('request.jwt.claim.sub','33333333-0000-0000-0000-000000000006',true);
select pg_temp.denied(format('select fn_overdue_decision(%L,%L)',(select v from fixture where k='old'),'approved'),'your area');
select set_config('request.jwt.claim.sub','33333333-0000-0000-0000-000000000001',true);
select pg_temp.assert_true((select count(*)=1 from staff_alerts where title='Overdue approval needed'),'Repeated request is deduplicated');
select fn_overdue_decision((select v from fixture where k='old'),'approved');
select pg_temp.assert_true((select balance=100 from bills where id=(select v from fixture where k='old')),'Approval creates no payment');
select fn_overdue_decision((select v from fixture where k='old'),'revoked');
select set_config('request.jwt.claim.sub','33333333-0000-0000-0000-000000000003',true);
select pg_temp.denied(format('select fn_check_collection(array[%L::uuid],array[100::numeric])',(select v from fixture where k='old')),'authorization');
select set_config('request.jwt.claim.sub','33333333-0000-0000-0000-000000000001',true);
select fn_overdue_decision((select v from fixture where k='old'),'approved');
select set_config('request.jwt.claim.sub','33333333-0000-0000-0000-000000000003',true);
select pg_temp.denied(format('select fn_check_collection(array[%L::uuid],array[200::numeric])',(select v from fixture where k='current')),'Settle every overdue');
insert into fixture values('receipt',fn_record_payment(array[(select v from fixture where k='old')],array[100::numeric],100,now(),'aaaaaaaa-0000-0000-0000-000000000006'));
select pg_temp.assert_true(fn_record_payment(array[(select v from fixture where k='old')],array[100::numeric],100,now(),'aaaaaaaa-0000-0000-0000-000000000006')=(select v from fixture where k='receipt'),'Retry returns exact receipt');
select pg_temp.denied(format('select fn_record_payment(array[%L::uuid],array[99::numeric],100,now(),%L)',(select v from fixture where k='old'),'aaaaaaaa-0000-0000-0000-000000000006'),'conflicts');
select fn_check_collection(array[(select v from fixture where k='current')],array[200::numeric]);
select fn_record_payment(array[(select v from fixture where k='current')],array[200::numeric],200,now(),'aaaaaaaa-0000-0000-0000-000000000005');
select pg_temp.assert_true((select count(*)=2 and sum(total_collected)=300 from payment_transactions),'Only two cash handovers counted');
select pg_temp.assert_true((select state='consumed' from overdue_collection_approvals where bill_id=(select v from fixture where k='old')),'Approval consumed atomically');
select pg_temp.assert_true((select count(*)>0 from fn_claim_staff_alerts('aaaaaaaa-0000-0000-0000-000000000010')),'First device claims alerts');
select pg_temp.assert_true((select count(*)=0 from fn_claim_staff_alerts('aaaaaaaa-0000-0000-0000-000000000010')),'Concurrent foreground/background claims deduplicate');
select pg_temp.assert_true((select count(*)>0 from fn_claim_staff_alerts('aaaaaaaa-0000-0000-0000-000000000011')),'Second device receives its own alerts');
-- Delivered or currently leased alerts must not starve later batches.
reset role;
insert into staff_alerts(recipient_id,area_id,recipient_role,event_key,title,body,destination)
select '33333333-0000-0000-0000-000000000003', area_id, 'cashier', 'batch:'||n, 'Test','Test','/cashier'
from profiles cross join generate_series(1,55) n where id='33333333-0000-0000-0000-000000000003';
set local role authenticated;
select pg_temp.assert_true((select count(*)=50 from fn_claim_staff_alerts('aaaaaaaa-0000-0000-0000-000000000010')),'Next batch claims fifty new alerts');
select pg_temp.assert_true((select count(*)=5 from fn_claim_staff_alerts('aaaaaaaa-0000-0000-0000-000000000010')),'Older claims cannot starve remaining alerts');
select set_config('request.jwt.claim.sub','44444444-0000-0000-0000-000000000001',true);
select pg_temp.assert_true((select count(*)=0 from staff_alerts),'Consumer sees no staff alerts');
select pg_temp.denied('select fn_record_payment(array[]::uuid[],array[]::numeric[])','Only an active Cashier');
reset role;
rollback;
\echo 'Overdue collection, exact replay, role/area isolation, and alert claim tests passed.'
