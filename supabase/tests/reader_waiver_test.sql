-- Disposable local PostgreSQL only; synthetic 05_seed fixtures. Rolls back.
\set ON_ERROR_STOP on
begin;
create function pg_temp.assert_true(ok boolean,label text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'FAILED: %',label; end if; end $$;
create function pg_temp.denied(q text,expected text) returns void language plpgsql as $$
begin begin execute q; exception when others then
 if position(expected in sqlerrm)>0 then return; end if;
 raise exception 'Wrong refusal: % (expected %)',sqlerrm,expected; end;
 raise exception 'Unexpected permission: %',q; end $$;
create temp table waiver_fixture(k text primary key,v uuid);
grant all on waiver_fixture to authenticated;
update consumers set profile_id='33333333-0000-0000-0000-000000000002' where id='55555555-0000-0000-0000-000000000001';
set local role authenticated;
select set_config('request.jwt.claim.sub','33333333-0000-0000-0000-000000000002',true);
insert into waiver_fixture values('early',fn_record_meter_reading('55555555-0000-0000-0000-000000000001',90,
 (date_trunc('month',now())-interval '2 months'+interval '5 days')::timestamptz,'bbbbbbbb-0000-0000-0000-000000000030'));
insert into waiver_fixture values('old',fn_record_meter_reading('55555555-0000-0000-0000-000000000001',100,
 (date_trunc('month',now())-interval '1 month'+interval '5 days')::timestamptz,'bbbbbbbb-0000-0000-0000-000000000021'));
insert into waiver_fixture values('covered',fn_record_meter_reading('55555555-0000-0000-0000-000000000001',110,now(),'bbbbbbbb-0000-0000-0000-000000000022'));
insert into waiver_fixture values('cash',fn_record_meter_reading('55555555-0000-0000-0000-000000000002',100,now(),'bbbbbbbb-0000-0000-0000-000000000023'));
select pg_temp.denied($q$select fn_assign_reader_waiver('33333333-0000-0000-0000-000000000002','55555555-0000-0000-0000-000000000001',date_trunc('month',fn_ph_today())::date)$q$,'Only an active Admin');
select set_config('request.jwt.claim.sub','33333333-0000-0000-0000-000000000001',true);
select fn_post_bill_amount((select v from waiver_fixture where k='old'),99.40,fn_ph_today()+2,now(),'bbbbbbbb-0000-0000-0000-000000000024');
select pg_temp.denied($q$select fn_assign_reader_waiver('33333333-0000-0000-0000-000000000004','55555555-0000-0000-0000-000000000007',date_trunc('month',fn_ph_today())::date)$q$,'in your area');
select pg_temp.denied($q$select fn_assign_reader_waiver('33333333-0000-0000-0000-000000000002','55555555-0000-0000-0000-000000000002',date_trunc('month',fn_ph_today())::date)$q$,'linked to this Meter Reader');
select pg_temp.denied($q$select fn_assign_reader_waiver('33333333-0000-0000-0000-000000000002','55555555-0000-0000-0000-000000000001',(date_trunc('month',fn_ph_today())-interval '1 month')::date)$q$,'current or future');
insert into waiver_fixture select 'future',id from fn_assign_reader_waiver('33333333-0000-0000-0000-000000000002','55555555-0000-0000-0000-000000000001',(date_trunc('month',fn_ph_today())+interval '1 month')::date);
select fn_post_bill_amount((select v from waiver_fixture where k='early'),9.40,fn_ph_today()+3,now(),'bbbbbbbb-0000-0000-0000-000000000031');
select pg_temp.assert_true((select waiver_amount=0 and balance=10 from bills where id=(select v from waiver_fixture where k='early')),'Posting an older billing month never receives future coverage');
select fn_end_reader_waiver((select v from waiver_fixture where k='future'),'Choose current month instead');
select fn_end_reader_waiver((select v from waiver_fixture where k='future'),'Retry reason must not replace original');
select pg_temp.assert_true((select end_reason='Choose current month instead' from reader_waiver_assignments where id=(select v from waiver_fixture where k='future')),'Ending replay preserves original audit reason');
insert into waiver_fixture select 'assignment',id from fn_assign_reader_waiver('33333333-0000-0000-0000-000000000002','55555555-0000-0000-0000-000000000001',date_trunc('month',fn_ph_today())::date);
select pg_temp.denied($q$select fn_assign_reader_waiver('33333333-0000-0000-0000-000000000002','55555555-0000-0000-0000-000000000001',date_trunc('month',fn_ph_today())::date)$q$,'End the existing');
select fn_post_bill_amount((select v from waiver_fixture where k='covered'),529.40,fn_ph_today()+5,now(),'bbbbbbbb-0000-0000-0000-000000000025');
select fn_post_bill_amount((select v from waiver_fixture where k='covered'),529.40,fn_ph_today()+5,now(),'bbbbbbbb-0000-0000-0000-000000000025');
select fn_post_bill_amount((select v from waiver_fixture where k='cash'),99.40,fn_ph_today()+5,now(),'bbbbbbbb-0000-0000-0000-000000000026');
select pg_temp.assert_true((select waiver_amount=530 and total_amount=530 and cooperative_amount=529.40 and amount_paid=0 and balance=0 and status::text='waived' from bills where id=(select v from waiver_fixture where k='covered')),'Full noncash coverage retains original figure');
select pg_temp.assert_true((select balance=100 and waiver_amount=0 from bills where id=(select v from waiver_fixture where k='old')),'Older unpaid debt unchanged');
select pg_temp.assert_true((select count(*)=0 from payments),'No fake payment');
select pg_temp.assert_true((select count(*)=0 from payment_transactions),'No fake receipt');
select pg_temp.assert_true((select count(*)=0 from v_payment_history),'No cash history for coverage');
select pg_temp.assert_true((select total_outstanding=110 and payable_bill_count=2 from v_consumer_outstanding where consumer_id='55555555-0000-0000-0000-000000000001'),'Outstanding excludes covered bill');
select pg_temp.assert_true((select bill_id=(select v from waiver_fixture where k='old') from v_consumer_current_bill where consumer_id='55555555-0000-0000-0000-000000000001'),'Current bill shows older debt');
select pg_temp.assert_true(position('Full bill covered by BOHECO' in fn_render_bill_message((select v from waiver_fixture where k='covered')))>0,'Bill-ready text explains noncash coverage');
select pg_temp.assert_true((select total_billed=100 and payable_count=1 from v_cashier_collection_progress where area_id=app.current_area() and cycle_year=extract(year from fn_ph_today()) and cycle_month=extract(month from fn_ph_today())),'Collection demand excludes covered bill');
select set_config('request.jwt.claim.sub','33333333-0000-0000-0000-000000000003',true);
select pg_temp.denied(format('select fn_record_payment(array[%L::uuid],array[530::numeric],530,now(),%L::uuid)',(select v from waiver_fixture where k='covered'),'bbbbbbbb-0000-0000-0000-000000000027'),'Balance changed');
select fn_record_payment(array[(select v from waiver_fixture where k='cash')],array[100::numeric],100,now(),'bbbbbbbb-0000-0000-0000-000000000028');
select pg_temp.assert_true((select collected=100 and to_boheco=99.40 and rounding=.60 and gap=0 and reader_pay=.60 from fn_rounding_fund(app.current_area()) where remit_month=date_trunc('month',fn_ph_today()+case when extract(day from fn_ph_today())>28 then interval '1 month' else interval '0' end)::date),'Rounding gap excludes waiver; reader pay remains independent');
select pg_temp.assert_true((select count(*)=1 from payments),'Only actual cash produces payment');
select set_config('request.jwt.claim.sub','33333333-0000-0000-0000-000000000006',true);
select pg_temp.assert_true((select count(*)=0 from fn_reader_waiver_history('33333333-0000-0000-0000-000000000002')),'Other area cannot read assignment history');
select pg_temp.denied(format('select fn_end_reader_waiver(%L,%L)',(select v from waiver_fixture where k='assignment'),'Test'),'unavailable in your area');
reset role;
select pg_temp.denied(format('update bills set amount_paid=530 where id=%L',(select v from waiver_fixture where k='covered')),'immutable');
select pg_temp.denied(format('delete from bills where id=%L',(select v from waiver_fixture where k='covered')),'immutable');
update profiles set staff_enabled=false where id='33333333-0000-0000-0000-000000000002';
select pg_temp.assert_true((select ended_at is not null from reader_waiver_assignments where id=(select v from waiver_fixture where k='assignment')),'Disabling staff ends coverage automatically');
update profiles set staff_enabled=true where id='33333333-0000-0000-0000-000000000002';
set local role authenticated;
select set_config('request.jwt.claim.sub','33333333-0000-0000-0000-000000000001',true);
insert into waiver_fixture select 'replacement',id from fn_assign_reader_waiver('33333333-0000-0000-0000-000000000002','55555555-0000-0000-0000-000000000001',(date_trunc('month',fn_ph_today())+interval '1 month')::date);
reset role;
update consumers set profile_id='44444444-0000-0000-0000-000000000001' where id='55555555-0000-0000-0000-000000000001';
select pg_temp.assert_true((select ended_at is not null from reader_waiver_assignments where id=(select v from waiver_fixture where k='replacement')),'Changing household link ends coverage automatically');
select pg_temp.assert_true((select waiver_amount=530 and amount_paid=0 and balance=0 from bills where id=(select v from waiver_fixture where k='covered')),'Historical coverage survives lifecycle changes');
select pg_temp.assert_true(not has_table_privilege('authenticated','reader_waiver_assignments','INSERT'),'No direct assignment writes');
select pg_temp.assert_true(not has_function_privilege('anon','fn_assign_reader_waiver(uuid,uuid,date)','EXECUTE'),'No anonymous assignment RPC');
-- A legacy notice item may reference a covered bill. Its zero balance alone
-- is insufficient; the noncash coverage amount supplies the settlement evidence.
insert into disconnection_notices(notice_no,consumer_id,reason,served_at,earliest_lawful_at,issued_by,client_uuid)
values('DN-WAIVER-EVIDENCE','55555555-0000-0000-0000-000000000001','Synthetic audit',now(),now()+interval '48 hours','33333333-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000029');
insert into notice_bill_items(notice_id,bill_id,legacy)
select n.id,f.v,true from disconnection_notices n cross join waiver_fixture f where n.notice_no='DN-WAIVER-EVIDENCE' and f.k='covered';
set local role authenticated;
select set_config('request.jwt.claim.sub','33333333-0000-0000-0000-000000000001',true);
select pg_temp.assert_true((select ready_to_close from v_notice_review_records where notice_no='DN-WAIVER-EVIDENCE'),'Coverage is valid noncash notice settlement evidence');
select pg_temp.assert_true((select (fn_notice_review(notice_id)->'covered_bills'->0->>'waiver_amount')::numeric=530 from v_notice_review_records where notice_no='DN-WAIVER-EVIDENCE'),'Notice review exposes coverage audit amount');
select pg_temp.assert_true((select jsonb_array_length(fn_notice_review(notice_id)->'receipts')=0 from v_notice_review_records where notice_no='DN-WAIVER-EVIDENCE'),'Coverage audit creates no receipt');
reset role;
-- Staff role disabled leaves an active login but must not receive remit cash.
update profiles set staff_enabled=false where id='33333333-0000-0000-0000-000000000002';
set local role authenticated;
select set_config('request.jwt.claim.sub','33333333-0000-0000-0000-000000000003',true);
select pg_temp.assert_true((select handed_to is null from fn_record_remit_handover(date_trunc('month',fn_ph_today()+case when extract(day from fn_ph_today())>28 then interval '1 month' else interval '0' end)::date)),'Disabled reader is not remittance recipient');
reset role;
update profiles set account_status='inactive' where id='33333333-0000-0000-0000-000000000002';
set local role authenticated;
select set_config('request.jwt.claim.sub','33333333-0000-0000-0000-000000000002',true);
select pg_temp.assert_true((select count(*)=0 from fn_reader_waiver_history('33333333-0000-0000-0000-000000000002')),'Inactive login cannot read its coverage history');
rollback;


