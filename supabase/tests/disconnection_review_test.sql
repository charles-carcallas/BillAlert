-- DISPOSABLE LOCAL DB ONLY: 05 synthetic fixtures, 19/20 and disconnection_review.
-- Simulated auth.uid() reads request.jwt.claim.sub. No real users or phone numbers.
\set ON_ERROR_STOP on
begin;
create function pg_temp.assert_true(ok boolean,label text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'FAILED: %',label; end if; end $$;
create function pg_temp.denied(q text,expected text) returns void language plpgsql as $$
begin begin execute q; exception when others then
  if position(expected in sqlerrm)>0 then return; end if;
  raise exception 'Wrong refusal: % (expected %)',sqlerrm,expected; end;
  raise exception 'Unexpected permission: %',q; end $$;
create temp table fixture(k text primary key,v uuid);
grant all on fixture to authenticated;
set local role authenticated;
select set_config('request.jwt.claim.sub','33333333-0000-0000-0000-000000000002',true);
insert into fixture values('old',fn_record_meter_reading('55555555-0000-0000-0000-000000000001',100,
 (date_trunc('month',now())-interval '1 month'+interval '5 days')::timestamptz,'bbbbbbbb-0000-0000-0000-000000000001'));
insert into fixture values('current',fn_record_meter_reading('55555555-0000-0000-0000-000000000001',110,now(),'bbbbbbbb-0000-0000-0000-000000000002'));
select set_config('request.jwt.claim.sub','33333333-0000-0000-0000-000000000001',true);
select fn_post_bill_amount((select v from fixture where k='old'),99.40,fn_ph_today()+2,now(),'bbbbbbbb-0000-0000-0000-000000000003');
select fn_post_bill_amount((select v from fixture where k='current'),200,fn_ph_today()+5,now(),'bbbbbbbb-0000-0000-0000-000000000004');
reset role;
update bills set due_date=fn_ph_today()-1 where id=(select v from fixture where k='old');
set local role authenticated;
insert into fixture values('cancelled',fn_issue_disconnection_notice('55555555-0000-0000-0000-000000000001','Test',now(),'bbbbbbbb-0000-0000-0000-000000000005'));
select pg_temp.assert_true((select count(*)=1 and min(amount_at_issue)=100 from notice_bill_items),'Only overdue bill captured, original balance frozen');
select pg_temp.assert_true(jsonb_array_length(fn_notice_review((select v from fixture where k='cancelled'))->'covered_bills')=1,'Review has covered bill');
select pg_temp.denied(format('select fn_close_disconnection_notice(%L,%L)',(select v from fixture where k='cancelled'),'settled'),'Payment is not confirmed');
select pg_temp.denied(format('select fn_close_disconnection_notice(%L,%L)',(select v from fixture where k='cancelled'),'cancelled'),'cancellation reason');
select pg_temp.denied(format('update disconnection_notices set status=%L where id=%L','settled',(select v from fixture where k='cancelled')),'permission denied');
select fn_close_disconnection_notice((select v from fixture where k='cancelled'),'cancelled','Wrong service record');
select fn_close_disconnection_notice((select v from fixture where k='cancelled'),'cancelled','Wrong service record');
select pg_temp.assert_true((select balance=100 from bills where id=(select v from fixture where k='old')),'Cancellation erases no debt');
insert into fixture values('referred',fn_issue_disconnection_notice('55555555-0000-0000-0000-000000000001','Test',now(),'bbbbbbbb-0000-0000-0000-000000000006'));
select pg_temp.denied(format('select fn_close_disconnection_notice(%L,%L)',(select v from fixture where k='referred'),'referred'),'referral details');
select fn_close_disconnection_notice((select v from fixture where k='referred'),'referred','Handed to BOHECO office, reference TEST');
insert into fixture values('settled',fn_issue_disconnection_notice('55555555-0000-0000-0000-000000000001','Test',now(),'bbbbbbbb-0000-0000-0000-000000000007'));
select fn_overdue_decision((select v from fixture where k='old'),'approved');
select pg_temp.denied(format('select fn_close_disconnection_notice(%L,%L)',(select v from fixture where k='settled'),'settled'),'Payment is not confirmed');
select set_config('request.jwt.claim.sub','33333333-0000-0000-0000-000000000003',true);
select pg_temp.denied(format('select fn_close_disconnection_notice(%L,%L)',(select v from fixture where k='settled'),'settled'),'Only an active Admin');
select fn_record_payment(array[(select v from fixture where k='old')],array[100::numeric],100,now(),'bbbbbbbb-0000-0000-0000-000000000008');
select set_config('request.jwt.claim.sub','33333333-0000-0000-0000-000000000001',true);
select pg_temp.assert_true((select ready_to_close from v_active_disconnection_warnings where notice_id=(select v from fixture where k='settled')),'Paid notice ready while current bill is unpaid');
select pg_temp.assert_true((select count(*)=1 from staff_alerts where title='Notice payment confirmed'),'Ready alert emitted once for active notice');
select pg_temp.assert_true(jsonb_array_length(fn_notice_review((select v from fixture where k='settled'))->'receipts')=1,'Exact covered bill receipt included');
select pg_temp.assert_true(jsonb_array_length(fn_notice_review((select v from fixture where k='settled'))->'overdue_bills')=0,'Paid overdue debt gone, current debt excluded');
select pg_temp.assert_true(jsonb_array_length(fn_notice_review((select v from fixture where k='settled'))->'sms')=1,'Notice SMS state visible without destination numbers');
reset role;
update bills set due_date=fn_ph_today()-1 where id=(select v from fixture where k='current');
set local role authenticated;
select pg_temp.denied(format('select fn_close_disconnection_notice(%L,%L)',(select v from fixture where k='settled'),'settled'),'Payment is not confirmed');
reset role;
update bills set due_date=fn_ph_today()+5 where id=(select v from fixture where k='current');
set local role authenticated;
select set_config('request.jwt.claim.sub','33333333-0000-0000-0000-000000000006',true);
select pg_temp.assert_true(fn_notice_review((select v from fixture where k='settled')) is null,'Other area gets no review');
select pg_temp.denied(format('select fn_close_disconnection_notice(%L,%L)',(select v from fixture where k='settled'),'settled'),'your area');
select set_config('request.jwt.claim.sub','33333333-0000-0000-0000-000000000001',true);
select fn_close_disconnection_notice((select v from fixture where k='settled'),'settled','Cash receipt verified');
select fn_close_disconnection_notice((select v from fixture where k='settled'),'settled','Cash receipt verified');
select pg_temp.assert_true((select count(*)=3 from v_disconnection_history),'History keeps all three outcomes');
select pg_temp.assert_true((fn_notice_review((select v from fixture where k='settled'))->>'status')='settled','Closed detail remains readable');
select pg_temp.denied(format('select fn_close_disconnection_notice(%L,%L,%L)',(select v from fixture where k='settled'),'cancelled','Changed'),'already closed');
-- Mimic a pre-upgrade closed record without original captured items.
reset role;
alter table disconnection_notices disable trigger capture_notice_bills;
insert into disconnection_notices(notice_no,consumer_id,reason,served_at,earliest_lawful_at,status,closed_at,closed_by,issued_by,client_uuid)
select 'DN-LEGACY-TEST',consumer_id,reason,served_at,earliest_lawful_at,'cancelled',now(),closed_by,issued_by,'bbbbbbbb-0000-0000-0000-000000000009'
from disconnection_notices where id=(select v from fixture where k='cancelled');
alter table disconnection_notices enable trigger capture_notice_bills;
insert into notice_bill_items(notice_id,bill_id,legacy)
select n.id,b.id,true from disconnection_notices n join bills b on b.consumer_id=n.consumer_id
where n.notice_no='DN-LEGACY-TEST' and b.total_amount is not null and b.due_date<fn_ph_today(n.served_at)
  and b.generated_at<=n.created_at and b.priced_at<=n.created_at
  and (b.balance>0 or exists(select 1 from payments p where p.bill_id=b.id and p.paid_at>=n.served_at));
select pg_temp.assert_true((select count(*)=1 and bool_and(i.legacy) and bool_and(i.amount_at_issue is null)
  from notice_bill_items i join disconnection_notices n on n.id=i.notice_id where n.notice_no='DN-LEGACY-TEST'),'Legacy links never invent original balances');
set local role authenticated;
select set_config('request.jwt.claim.sub','44444444-0000-0000-0000-000000000001',true);
select pg_temp.assert_true((select count(*)=0 from v_disconnection_history),'Consumer cannot inspect Admin history');
select pg_temp.denied(format('select fn_notice_review(%L)',(select v from fixture where k='settled')),'Only an active Admin');
reset role;
rollback;
\echo 'Disconnection receipt guards, history, isolation, notes, and delivery review passed.'
