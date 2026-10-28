-- DISPOSABLE LOCAL DATABASE ONLY. Uses synthetic 05 fixtures; rolls back all data.
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
insert into fixture values('one',fn_record_meter_reading('55555555-0000-0000-0000-000000000001',100,(date_trunc('month',now())-interval '2 months'+interval '5 days')::timestamptz,'bbbbbbbb-0000-0000-0000-000000000001'));
insert into fixture values('two',fn_record_meter_reading('55555555-0000-0000-0000-000000000001',110,(date_trunc('month',now())-interval '1 month'+interval '5 days')::timestamptz,'bbbbbbbb-0000-0000-0000-000000000002'));
select set_config('request.jwt.claim.sub','33333333-0000-0000-0000-000000000001',true);
select fn_post_bill_amount((select v from fixture where k='one'),100,fn_ph_today()+2,now(),'bbbbbbbb-0000-0000-0000-000000000003');
select fn_post_bill_amount((select v from fixture where k='two'),200,fn_ph_today()+2,now(),'bbbbbbbb-0000-0000-0000-000000000004');
reset role;
update bills set due_date=fn_ph_today()-1 where id in(select v from fixture);
create temp table before_counts as select (select count(*) from payment_transactions) receipts,(select count(*) from notifications) notifications,(select count(*) from disconnection_notices) notices;
set local role authenticated;
select set_config('request.jwt.claim.sub','33333333-0000-0000-0000-000000000003',true);
select pg_temp.denied(format('select fn_request_overdue_household(%L,array[%L::uuid,%L::uuid],array[100,201])','55555555-0000-0000-0000-000000000001',(select v from fixture where k='one'),(select v from fixture where k='two')),'Balance changed');
select pg_temp.assert_true((select count(*)=0 from overdue_collection_approvals where bill_id in(select v from fixture)),'Changed balance rejects entire request');
select fn_request_overdue_household('55555555-0000-0000-0000-000000000001',array[(select v from fixture where k='one'),(select v from fixture where k='two')],array[100,200]);
select fn_request_overdue_household('55555555-0000-0000-0000-000000000001',array[(select v from fixture where k='one'),(select v from fixture where k='two')],array[100,200]);
select pg_temp.assert_true((select count(*)=2 from overdue_collection_approvals where bill_id in(select v from fixture) and state='requested'),'One request covers both overdue bills');
select pg_temp.assert_true((select count(*)=2 from overdue_collection_audit where bill_id in(select v from fixture) and action='requested'),'Repeat creates no duplicate request audit');
select pg_temp.denied(format('select fn_check_collection(array[%L::uuid],array[100::numeric])',(select v from fixture where k='one')),'authorization');
select set_config('request.jwt.claim.sub','33333333-0000-0000-0000-000000000005',true);
select pg_temp.denied(format('select fn_request_overdue_household(%L,array[%L::uuid],array[100])','55555555-0000-0000-0000-000000000001',(select v from fixture where k='one')),'your area');
select set_config('request.jwt.claim.sub','33333333-0000-0000-0000-000000000001',true);
select pg_temp.denied(format('select fn_request_overdue_household(%L,array[%L::uuid],array[100])','55555555-0000-0000-0000-000000000001',(select v from fixture where k='one')),'Cashier');
select fn_overdue_decision((select v from fixture where k='one'),'approved');
select set_config('request.jwt.claim.sub','33333333-0000-0000-0000-000000000003',true);
select fn_request_overdue_household('55555555-0000-0000-0000-000000000001',array[(select v from fixture where k='one'),(select v from fixture where k='two')],array[100,200]);
select pg_temp.assert_true((select state='approved' from overdue_collection_approvals where bill_id=(select v from fixture where k='one')),'Request preserves existing Admin approval');
reset role;
select pg_temp.assert_true((select sum(balance)=300 from bills where id in(select v from fixture)),'Requests do not pay bills');
select pg_temp.assert_true((select receipts=(select count(*) from payment_transactions) and notifications=(select count(*) from notifications) and notices=(select count(*) from disconnection_notices) from before_counts),'No receipt, consumer notification or notice from requesting');
rollback;
\echo 'Household request, unchanged retry, payment blocking and role/area tests passed.'

