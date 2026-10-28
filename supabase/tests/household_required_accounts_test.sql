-- DISPOSABLE LOCAL DATABASE ONLY, with 05_seed fixtures and latest migrations.
\set ON_ERROR_STOP on
begin;
create function pg_temp.ok(v boolean,label text) returns void language plpgsql as $$
begin if v is distinct from true then raise exception 'FAILED: %',label; end if; end $$;
create function pg_temp.denied(q text,expected text) returns void language plpgsql as $$
begin
 begin execute q; exception when others then
 if position(expected in sqlerrm)>0 then return; end if;
 raise exception 'Wrong error: % expected %',sqlerrm,expected; end;
 raise exception 'Unexpected success: %',q;
end $$;
create function pg_temp.make_account(u uuid,n text,h jsonb,r text default 'consumer',a uuid default '33333333-0000-0000-0000-000000000001') returns uuid language sql as $$
 select public.fn_create_linked_account(a,u,n,'Test','Person','Reviewed test setup',r,h)
$$;
select pg_temp.denied($q$select pg_temp.make_account('aaaaaaaa-1111-4000-8000-000000000001','required.test','{}')$q$,'Choose and confirm');
select pg_temp.denied($q$select pg_temp.make_account('aaaaaaaa-1111-4000-8000-000000000001','required.test','{"mode":"new","consumer_no":"H-NEW","confirmed":true}','consumer','33333333-0000-0000-0000-000000000002')$q$,'Only the active');
select pg_temp.denied($q$select pg_temp.make_account('aaaaaaaa-1111-4000-8000-000000000001','required.test','{"mode":"existing","id":"55555555-0000-0000-0000-000000000007","confirmed":true}')$q$,'Choose an active household');
select pg_temp.denied($q$select pg_temp.make_account('aaaaaaaa-1111-4000-8000-000000000001','required.test','{"mode":"existing","id":"55555555-0000-0000-0000-000000000002","confirmed":true}')$q$,'already has a login');
select pg_temp.make_account('aaaaaaaa-1111-4000-8000-000000000001','required.test','{"mode":"new","consumer_no":"H-NEW","confirmed":true}');
set constraints all immediate;
set constraints all deferred;
select pg_temp.ok(exists(select 1 from consumers where consumer_no='H-NEW' and profile_id='aaaaaaaa-1111-4000-8000-000000000001'),'New household is linked');
select pg_temp.ok((select must_change_password and not staff_enabled from profiles where id='aaaaaaaa-1111-4000-8000-000000000001'),'Consumer password change required; no staff authority');
select pg_temp.denied($q$select pg_temp.make_account('aaaaaaaa-1111-4000-8000-000000000002','required.other','{"mode":"new","consumer_no":"H-NEW","confirmed":true}')$q$,'duplicate key');
select pg_temp.ok(not exists(select 1 from profiles where id='aaaaaaaa-1111-4000-8000-000000000002'),'Failed household insert rolls back profile');
select pg_temp.denied($q$select pg_temp.make_account('aaaaaaaa-1111-4000-8000-000000000002','required.other','{"mode":"new","consumer_no":"H-STAFF","confirmed":true}','cashier')$q$,'already the active');
update profiles set staff_enabled=false where id='33333333-0000-0000-0000-000000000003';
select pg_temp.make_account('aaaaaaaa-1111-4000-8000-000000000002','required.cashier','{"mode":"new","consumer_no":"H-STAFF","confirmed":true}','cashier');
select pg_temp.ok(exists(select 1 from consumers c join profiles p on c.profile_id=p.id where c.consumer_no='H-STAFF' and p.role='cashier' and p.staff_enabled),'Staff gets household atomically');
select pg_temp.ok(not exists(select 1 from reader_waiver_assignments where reader_id='aaaaaaaa-1111-4000-8000-000000000002'),'No automatic coverage for cashier');
insert into consumers(id,consumer_no,first_name,last_name,area_id,created_by)
values('bbbbbbbb-1111-4000-8000-000000000001','H-LEGACY','Legacy','Person','11111111-0000-0000-0000-00000000000a','33333333-0000-0000-0000-000000000001');
select pg_temp.make_account('aaaaaaaa-1111-4000-8000-000000000003','required.legacy','{"mode":"existing","id":"bbbbbbbb-1111-4000-8000-000000000001","confirmed":true}');
select pg_temp.ok((select profile_id='aaaaaaaa-1111-4000-8000-000000000003' from consumers where consumer_no='H-LEGACY'),'Legacy household reused');
set constraints all immediate;
set constraints all deferred;
select pg_temp.denied($q$select pg_temp.make_account('aaaaaaaa-1111-4000-8000-000000000004','required.same','{"mode":"same_household","id":"bbbbbbbb-1111-4000-8000-000000000001","reference":"Reviewed","confirmed":true}')$q$,'Disable the previous');
update profiles set account_status='inactive' where id='aaaaaaaa-1111-4000-8000-000000000003';
select pg_temp.make_account('aaaaaaaa-1111-4000-8000-000000000004','required.same','{"mode":"same_household","id":"bbbbbbbb-1111-4000-8000-000000000001","reference":"Reviewed","confirmed":true}');
select pg_temp.make_account('aaaaaaaa-1111-4000-8000-000000000005','required.occupant','{"mode":"handover","id":"bbbbbbbb-1111-4000-8000-000000000001","reference":"Reviewed occupant","consumer_no":"H-OCCUPANT","opening_reading":"0","confirmed":true}');
select pg_temp.ok((select account_status='inactive' and profile_id='aaaaaaaa-1111-4000-8000-000000000004' from consumers where consumer_no='H-LEGACY'),'Old occupant retains retired household history');
select pg_temp.ok(exists(select 1 from consumers where consumer_no='H-OCCUPANT' and profile_id='aaaaaaaa-1111-4000-8000-000000000005'),'New occupant linked separately');
-- A legacy outgoing reader without a household must be resolved first.
set local role authenticated;
select set_config('request.jwt.claim.sub','33333333-0000-0000-0000-000000000001',true);
select pg_temp.denied($q$select fn_assign_staff('cccccccc-1111-4000-8000-000000000001','meter_reader','aaaaaaaa-1111-4000-8000-000000000001',(select access_version from profiles where id='aaaaaaaa-1111-4000-8000-000000000001'),'33333333-0000-0000-0000-000000000002',(select access_version from profiles where id='33333333-0000-0000-0000-000000000002'),true)$q$,'Link the outgoing');
reset role;
insert into consumers(consumer_no,first_name,last_name,profile_id,area_id,created_by)
values('H-OLD-READER','Old','Reader','33333333-0000-0000-0000-000000000002','11111111-0000-0000-0000-00000000000a','33333333-0000-0000-0000-000000000001');
create temp table assignment_versions as select
 (select access_version from profiles where id='aaaaaaaa-1111-4000-8000-000000000001') as incoming,
 (select access_version from profiles where id='33333333-0000-0000-0000-000000000002') as outgoing;
grant select on assignment_versions to authenticated;
set local role authenticated;
select fn_assign_staff('cccccccc-1111-4000-8000-000000000001','meter_reader','aaaaaaaa-1111-4000-8000-000000000001',(select incoming from assignment_versions),'33333333-0000-0000-0000-000000000002',(select outgoing from assignment_versions),true);
select fn_assign_staff('cccccccc-1111-4000-8000-000000000001','meter_reader','aaaaaaaa-1111-4000-8000-000000000001',(select incoming from assignment_versions),'33333333-0000-0000-0000-000000000002',(select outgoing from assignment_versions),true);
reset role;
select pg_temp.ok((select count(*)=1 from app.staff_assignment_operations where id='cccccccc-1111-4000-8000-000000000001'),'Assignment replay remains idempotent');
select pg_temp.ok((select not staff_enabled and account_status='active' from profiles where id='33333333-0000-0000-0000-000000000002'),'Outgoing retains personal login');
-- Check the deferred guard in a subtransaction: no orphan can commit.
select pg_temp.denied($q$do $inner$ begin
 perform public.fn_prepare_consumer_identity('33333333-0000-0000-0000-000000000001','aaaaaaaa-1111-4000-8000-000000000009','required.orphan','No','Household','Test');
 set constraints require_new_account_household immediate;
end $inner$$q$,'New accounts require a household');
select pg_temp.make_account('aaaaaaaa-1111-4000-8000-000000000006','required.successor','{"mode":"new","consumer_no":"H-PRESIDENT","confirmed":true}','successor');
select pg_temp.ok((select role='admin' and not staff_enabled and must_change_password from profiles where id='aaaaaaaa-1111-4000-8000-000000000006'),'Successor has household but no work authority yet');
select pg_temp.ok(not has_function_privilege('authenticated','public.fn_create_linked_account(uuid,uuid,text,text,text,text,text,jsonb)','EXECUTE'),'Provisioning is service-only');
select pg_temp.ok(not has_function_privilege('authenticated','app.assign_staff_before_household_rule(uuid,public.user_role,uuid,bigint,uuid,bigint,boolean)','EXECUTE'),'Old assignment cannot bypass household guard');
set constraints all immediate;
rollback;
