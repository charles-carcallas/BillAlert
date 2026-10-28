-- DISPOSABLE LOCAL ONLY: synthetic 05 fixtures, through lifecycle migration.
\set ON_ERROR_STOP on
begin;
create function pg_temp.assert_true(ok boolean,label text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'FAILED: %',label; end if; end $$;
create function pg_temp.denied(q text,expected text) returns void language plpgsql as $$
begin begin execute q; exception when others then
 if position(expected in sqlerrm)>0 then return; end if;
 raise exception 'Wrong refusal: % (expected %)',sqlerrm,expected; end;
 raise exception 'Unexpected permission: %',q; end $$;
create temp table lifecycle_fixture(k text primary key,v uuid);
grant all on lifecycle_fixture to authenticated;
insert into lifecycle_fixture values('registered',gen_random_uuid()),('registered_household',gen_random_uuid());
insert into consumers(id,consumer_no,first_name,last_name,area_id)
select (select v from lifecycle_fixture where k='registered_household'),'SYNTHETIC-REGISTERED','Registered','Household',area_id
from profiles where id='33333333-0000-0000-0000-000000000001';
select fn_create_household_login('33333333-0000-0000-0000-000000000001',
 (select v from lifecycle_fixture where k='registered'),
 (select v from lifecycle_fixture where k='registered_household'),'registered.household');
select pg_temp.assert_true((select area_id is not null from profiles where id=(select v from lifecycle_fixture where k='registered')),'New household identity retains management area');
-- Preserve named fixture identities; every synthetic change rolls back.
set local role authenticated;
select set_config('request.jwt.claim.sub','33333333-0000-0000-0000-000000000001',true);
select pg_temp.assert_true(jsonb_array_length(fn_account_workspace()->'people')>0,'Admin sees own area workspace');
select pg_temp.denied($q$update profiles set role='admin' where id=auth.uid()$q$,'permission denied');
select pg_temp.denied($q$update profiles set staff_enabled=false where id=auth.uid()$q$,'permission denied');
select pg_temp.denied($q$update consumers set profile_id=auth.uid()$q$,'permission denied');
select pg_temp.denied($q$select fn_manage_account('33333333-0000-0000-0000-000000000002','end_work','End appointment',false)$q$,'Review pending');
select fn_manage_account('33333333-0000-0000-0000-000000000002','end_work','Reconciled appointment end',true);
select set_config('request.jwt.claim.sub','33333333-0000-0000-0000-000000000002',true);
select pg_temp.assert_true(app.current_role()='consumer' and app.current_area() is null,'Departing reader loses work role without renaming identity');
select pg_temp.denied($q$select fn_record_meter_reading('55555555-0000-0000-0000-000000000001',100,now())$q$,'assigned active Meter Reader');
select pg_temp.denied($q$select fn_account_workspace()$q$,'active Area President');
select set_config('request.jwt.claim.sub','33333333-0000-0000-0000-000000000001',true);
select fn_manage_account('33333333-0000-0000-0000-000000000002','restore_work','Return to duty',true);
select fn_manage_account('33333333-0000-0000-0000-000000000003','disable_login','Emergency suspension',false);
select set_config('request.jwt.claim.sub','33333333-0000-0000-0000-000000000003',true);
select pg_temp.assert_true(app.current_role() is null and app.current_area() is null,'Disabled cashier has no work role');
select pg_temp.denied($q$select fn_check_collection(array[]::uuid[],array[]::numeric[])$q$,'active Cashier');
select pg_temp.assert_true((select count(*)=0 from bills),'Disabled cashier cannot read household bills');
select set_config('request.jwt.claim.sub','33333333-0000-0000-0000-000000000001',true);
select fn_manage_account('33333333-0000-0000-0000-000000000003','enable_login','Access restored',false);
select pg_temp.assert_true((select not staff_enabled from profiles where id='33333333-0000-0000-0000-000000000003'),'Login restore does not silently restore cash powers');
select fn_manage_account('33333333-0000-0000-0000-000000000003','restore_work','Cash assignment reviewed',true);
select pg_temp.denied($q$select fn_manage_account('33333333-0000-0000-0000-000000000006','disable_login','Other area',false)$q$,'Area President transfer');
select pg_temp.denied($q$select fn_prepare_president_transfer(auth.uid(),gen_random_uuid(),'successor','Test','Next','Verified')$q$,'permission denied');
-- Private provision helpers emulate the Edge Function; no real Auth accounts.
reset role;
insert into lifecycle_fixture values('next',gen_random_uuid()),('family',gen_random_uuid()),('occupant',gen_random_uuid());
select fn_prepare_consumer_identity('33333333-0000-0000-0000-000000000001',(select v from lifecycle_fixture where k='family'),'family.member','Family','Member','In-person identity checked');
select fn_prepare_consumer_identity('33333333-0000-0000-0000-000000000001',(select v from lifecycle_fixture where k='occupant'),'new.occupant','New','Occupant','In-person identity checked');
insert into lifecycle_fixture values('transfer',fn_prepare_president_transfer('33333333-0000-0000-0000-000000000001',(select v from lifecycle_fixture where k='next'),'new.president','New','President','Appointment verified'));
set local role authenticated;
select set_config('request.jwt.claim.sub',(select v::text from lifecycle_fixture where k='next'),true);
select pg_temp.assert_true(app.current_role()='consumer','Candidate has no staff power');
select pg_temp.assert_true(jsonb_array_length(fn_my_president_transfers())=1,'Candidate can find their invitation');
select pg_temp.denied(format('select fn_accept_president_transfer(%L)',(select v from lifecycle_fixture where k='transfer')),'change your temporary password');
update profiles set must_change_password=false where id=auth.uid();
select fn_accept_president_transfer((select v from lifecycle_fixture where k='transfer'));
select set_config('request.jwt.claim.sub','33333333-0000-0000-0000-000000000001',true);
select pg_temp.denied(format('select fn_complete_president_transfer(%L,false)',(select v from lifecycle_fixture where k='transfer')),'Reconcile');
select fn_complete_president_transfer((select v from lifecycle_fixture where k='transfer'),true);
select pg_temp.assert_true(app.current_role()='consumer','Outgoing President loses work access atomically');
select pg_temp.denied($q$select fn_account_workspace()$q$,'active Area President');
select set_config('request.jwt.claim.sub',(select v::text from lifecycle_fixture where k='next'),true);
select pg_temp.assert_true(app.current_role()='admin','Successor receives existing area');
select pg_temp.assert_true((select count(*)=1 from profiles where role='admin' and staff_enabled and account_status='active' and area_id=app.current_area()),'Exactly one active President');
select pg_temp.assert_true((select first_name='Mario' from profiles where id='33333333-0000-0000-0000-000000000001'),'Outgoing name was not overwritten');
-- Household linkage preserves old debt; replaced login loses access.
select fn_link_household('55555555-0000-0000-0000-000000000001',(select v from lifecycle_fixture where k='family'),'same_household','Same-family access reviewed');
select pg_temp.assert_true((select access_version>0 from profiles where id=(select v from lifecycle_fixture where k='family')),'Membership bumps cache version');
select pg_temp.denied(format('select fn_link_household(%L,%L,%L,%L)','55555555-0000-0000-0000-000000000001',(select v from lifecycle_fixture where k='occupant'),'unrelated','Verified'),'Unrelated occupants');
insert into lifecycle_fixture values('new_household',fn_household_handover('55555555-0000-0000-0000-000000000001','SYNTHETIC-NEW','New','Occupant',(select v from lifecycle_fixture where k='occupant'),'Appointment and closing reading checked',0));
select pg_temp.assert_true((select account_status='inactive' from consumers where id='55555555-0000-0000-0000-000000000001'),'Old service retained and retired');
select set_config('request.jwt.claim.sub',(select v::text from lifecycle_fixture where k='occupant'),true);
select pg_temp.assert_true(app.current_consumer_id()=(select v from lifecycle_fixture where k='new_household'),'New occupant has separate ledger');
select pg_temp.assert_true((select count(*)=0 from consumers where id='55555555-0000-0000-0000-000000000001'),'New occupant cannot read old household');
select set_config('request.jwt.claim.sub',(select v::text from lifecycle_fixture where k='family'),true);
select pg_temp.assert_true(app.current_consumer_id()='55555555-0000-0000-0000-000000000001','Old occupant retains their historical ledger');
select pg_temp.denied($q$select fn_recover_president(gen_random_uuid(),gen_random_uuid(),'fake reference')$q$,'permission denied');
reset role;
select pg_temp.assert_true((select count(*)>5 from account_events),'Lifecycle decisions retain audit history');
-- A verified maintainer recovery creates a distinct candidate, never edits
-- the outgoing person's identity or invents their consent.
insert into lifecycle_fixture values('recovery',gen_random_uuid());
select fn_prepare_president_recovery(
 (select area_id from profiles where id=(select v from lifecycle_fixture where k='next')),
 (select v from lifecycle_fixture where k='recovery'),'recovered.president','Recovery','Candidate','Synthetic appointment evidence');
select pg_temp.denied(format('select fn_recover_president(%L,%L,%L)',
 (select area_id from profiles where id=(select v from lifecycle_fixture where k='next')),
 (select v from lifecycle_fixture where k='recovery'),'Synthetic verified recovery'),'Prepare and verify');
update profiles set must_change_password=false where id=(select v from lifecycle_fixture where k='recovery');
select fn_recover_president(
 (select area_id from profiles where id=(select v from lifecycle_fixture where k='next')),
 (select v from lifecycle_fixture where k='recovery'),'Synthetic verified recovery');
select pg_temp.assert_true((select staff_enabled from profiles where id=(select v from lifecycle_fixture where k='recovery')),'Verified recovery activates candidate');
select pg_temp.assert_true((select not staff_enabled from profiles where id=(select v from lifecycle_fixture where k='next')),'Recovery ends former work assignment');
select pg_temp.assert_true(exists(select 1 from account_events where actor_id is null and target_id=(select v from lifecycle_fixture where k='recovery')),'Maintainer recovery records its real origin');
rollback;
select 'Account permissions, replacement, President transfer and household separation passed.' as result;
