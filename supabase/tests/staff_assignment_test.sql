-- DISPOSABLE LOCAL ONLY. Synthetic 05_seed fixtures, migrations through
-- 20261002151432_staff_assignment.sql. Every fixture change rolls back.
\set ON_ERROR_STOP on
begin;
create function pg_temp.assert_true(ok boolean, label text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'FAILED: %',label; end if; end $$;
create function pg_temp.denied(q text, expected text) returns void language plpgsql as $$
begin begin execute q; exception when others then
  if position(expected in sqlerrm)>0 then return; end if;
  raise exception 'Wrong refusal: % (expected %)',sqlerrm,expected; end;
  raise exception 'Unexpected permission: %',q; end $$;
create function pg_temp.change_to(target uuid, staff_role public.user_role,
  reconciled boolean default true, operation uuid default gen_random_uuid())
returns void language plpgsql as $$
declare old profiles%rowtype; incoming_version bigint;
begin
  select * into old from profiles where area_id=app.current_area() and role=staff_role
    and account_status='active' and staff_enabled;
  select access_version into incoming_version from profiles where id=target;
  perform fn_assign_staff(operation,staff_role,target,coalesce(incoming_version,0),old.id,old.access_version,reconciled);
end $$;
create temp table saved(k text primary key, v jsonb);
grant all on saved to authenticated;

-- Build real synthetic reading -> posting -> receipt history, and link the
-- outgoing reader's household so coverage and household access can be checked.
update consumers set profile_id='33333333-0000-0000-0000-000000000002'
where id='55555555-0000-0000-0000-000000000001';
set local role authenticated;
select set_config('request.jwt.claim.sub','33333333-0000-0000-0000-000000000002',true);
insert into saved values('bill',to_jsonb(fn_record_meter_reading(
  '55555555-0000-0000-0000-000000000002',100,now(),'bbbbbbbb-0000-0000-0000-000000000080')));
select set_config('request.jwt.claim.sub','33333333-0000-0000-0000-000000000001',true);
select fn_post_bill_amount((select (v#>>'{}')::uuid from saved where k='bill'),500,fn_ph_today()+7,now(),
  'bbbbbbbb-0000-0000-0000-000000000081');
select fn_assign_reader_waiver('33333333-0000-0000-0000-000000000002',
  '55555555-0000-0000-0000-000000000001',date_trunc('month',fn_ph_today())::date);
select set_config('request.jwt.claim.sub','33333333-0000-0000-0000-000000000003',true);
select fn_record_payment(array[(select (v#>>'{}')::uuid from saved where k='bill')],array[500::numeric],500,now(),
  'bbbbbbbb-0000-0000-0000-000000000082');
select pg_temp.denied($q$select pg_temp.change_to('44444444-0000-0000-0000-000000000002','cashier')$q$,'Only the active Area President');
reset role;
insert into saved select 'readings',jsonb_agg(to_jsonb(r) order by id) from meter_readings r;
insert into saved select 'payments',jsonb_agg(to_jsonb(p) order by id) from payments p;
insert into saved select 'receipts',jsonb_agg(to_jsonb(p) order by id) from payment_transactions p;
insert into saved select 'households',jsonb_agg(to_jsonb(c) order by id) from consumers c;
insert into saved select 'bills',jsonb_agg(to_jsonb(b) order by id) from bills b;
insert into saved select 'versions',jsonb_object_agg(id,access_version) from profiles;

set local role authenticated;
select set_config('request.jwt.claim.sub','33333333-0000-0000-0000-000000000001',true);
select pg_temp.assert_true((fn_account_workspace()->'people'->0 ? 'access_version'),'Workspace carries version guards');
select pg_temp.denied($q$select pg_temp.change_to('44444444-0000-0000-0000-000000000002','meter_reader',false)$q$,'Confirm that all affected');
select pg_temp.denied($q$select pg_temp.change_to('44444444-0000-0000-0000-000000000002','admin')$q$,'Choose Meter Reader or Cashier');
select pg_temp.denied($q$select pg_temp.change_to('33333333-0000-0000-0000-000000000001','meter_reader')$q$,'Choose an active person');
select pg_temp.denied($q$select pg_temp.change_to('33333333-0000-0000-0000-000000000003','meter_reader')$q$,'Choose an active person');
select pg_temp.denied($q$select pg_temp.change_to('44444444-0000-0000-0000-000000000007','meter_reader')$q$,'Choose an active person');
select pg_temp.denied($q$select fn_assign_staff(gen_random_uuid(),'meter_reader',
 '44444444-0000-0000-0000-000000000002',-1,'33333333-0000-0000-0000-000000000002',
 (select access_version from profiles where id='33333333-0000-0000-0000-000000000002'),true)$q$,'replacement account changed');
select pg_temp.denied($q$select fn_assign_staff(gen_random_uuid(),'meter_reader',
 '44444444-0000-0000-0000-000000000002',0,null,null,true)$q$,'staff assignment changed');
select pg_temp.assert_true(app.active_staff('33333333-0000-0000-0000-000000000002','meter_reader'),'Failures leave outgoing staff enabled');

-- Simulate a failure after the old staff UPDATE but before the new one finishes.
reset role;
create function pg_temp.fail_promotion() returns trigger language plpgsql as $$
begin
  if new.id='44444444-0000-0000-0000-000000000002' and new.role='meter_reader' then
    raise exception 'Simulated promotion failure';
  end if;
  return new;
end $$;
create trigger fail_promotion before update on profiles for each row execute function pg_temp.fail_promotion();
set local role authenticated;
select pg_temp.denied($q$select pg_temp.change_to('44444444-0000-0000-0000-000000000002','meter_reader')$q$,'Simulated promotion failure');
select pg_temp.assert_true(app.active_staff('33333333-0000-0000-0000-000000000002','meter_reader'),'Mid-transaction failure restores outgoing work access');
select pg_temp.assert_true((select ended_at is null from reader_waiver_assignments
 where reader_id='33333333-0000-0000-0000-000000000002'),'Mid-transaction failure also restores coverage');
reset role;
drop trigger fail_promotion on profiles;
set local role authenticated;

select pg_temp.change_to('44444444-0000-0000-0000-000000000002','meter_reader',true,'bbbbbbbb-0000-0000-0000-000000000083');
select pg_temp.assert_true(app.active_staff('44444444-0000-0000-0000-000000000002','meter_reader'),'Existing consumer promoted in place');
select pg_temp.assert_true(not app.active_staff('33333333-0000-0000-0000-000000000002'),'Outgoing work access ended');
select pg_temp.assert_true((select ended_at is not null from reader_waiver_assignments
  where reader_id='33333333-0000-0000-0000-000000000002'),'Outgoing coverage ended');
select pg_temp.assert_true((select count(*)=0 from reader_waiver_assignments
  where reader_id='44444444-0000-0000-0000-000000000002'),'New coverage requires explicit approval');
select pg_temp.assert_true((select access_version=(select (v->>'44444444-0000-0000-0000-000000000002')::bigint+1
  from saved where k='versions') from profiles where id='44444444-0000-0000-0000-000000000002'),'New staff access version changes');
-- Same operation and exact original request is a no-op even after response loss.
select fn_assign_staff('bbbbbbbb-0000-0000-0000-000000000083','meter_reader',
 '44444444-0000-0000-0000-000000000002',
 (select (v->>'44444444-0000-0000-0000-000000000002')::bigint from saved where k='versions'),
 '33333333-0000-0000-0000-000000000002',
 (select (v->>'33333333-0000-0000-0000-000000000002')::bigint from saved where k='versions'),true);
select pg_temp.assert_true((select count(*)=1 from account_events where action='staff_assigned'),'Replay writes one audit event');
select pg_temp.denied($q$select pg_temp.change_to('44444444-0000-0000-0000-000000000003','meter_reader',true,
 'bbbbbbbb-0000-0000-0000-000000000083')$q$,'different staff change');

-- A former reader can become cashier without deleting their identity/history.
select pg_temp.change_to('33333333-0000-0000-0000-000000000002','cashier');
select pg_temp.assert_true(app.active_staff('33333333-0000-0000-0000-000000000002','cashier'),'Former staff may fill a different position');
select set_config('request.jwt.claim.sub','33333333-0000-0000-0000-000000000003',true);
select pg_temp.assert_true(app.current_role()='consumer','Outgoing cashier loses collection powers');
select pg_temp.denied($q$select fn_check_collection(array[]::uuid[],array[]::numeric[])$q$,'active Cashier');
select pg_temp.denied($q$select * from app.staff_assignment_operations$q$,'permission denied');
reset role;
select pg_temp.assert_true((select jsonb_agg(to_jsonb(r) order by id) from meter_readings r)=(select v from saved where k='readings'),'Reading authors preserved');
select pg_temp.assert_true((select jsonb_agg(to_jsonb(p) order by id) from payments p)=(select v from saved where k='payments'),'Payment history preserved');
select pg_temp.assert_true((select jsonb_agg(to_jsonb(p) order by id) from payment_transactions p)=(select v from saved where k='receipts'),'Receipt authors preserved');
select pg_temp.assert_true((select jsonb_agg(to_jsonb(c) order by id) from consumers c)=(select v from saved where k='households'),'Household links and details preserved');
select pg_temp.assert_true((select jsonb_agg(to_jsonb(b) order by id) from bills b)=(select v from saved where k='bills'),'Bills preserved');
select pg_temp.assert_true((select count(*)=13 from profiles),'No extra identity created by replacement');

-- Vacant position, inactive candidate and stale versions after an ABA change.
update profiles set staff_enabled=false where id='44444444-0000-0000-0000-000000000002';
update profiles set account_status='inactive' where id='44444444-0000-0000-0000-000000000003';
set local role authenticated;
select set_config('request.jwt.claim.sub','33333333-0000-0000-0000-000000000001',true);
select pg_temp.denied($q$select pg_temp.change_to('44444444-0000-0000-0000-000000000003','meter_reader')$q$,'Choose an active person');
select pg_temp.change_to('44444444-0000-0000-0000-000000000004','meter_reader');
select pg_temp.assert_true(app.active_staff('44444444-0000-0000-0000-000000000004','meter_reader'),'Vacancy assigned without a separate end-work step');
reset role;
set local role anon;
select pg_temp.denied($q$select fn_assign_staff(gen_random_uuid(),'cashier',gen_random_uuid(),0,null,null,true)$q$,'permission denied');
rollback;
