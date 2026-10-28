-- Disposable local synthetic 05_seed database only; rolls back every change.
\set ON_ERROR_STOP on
begin;
create function pg_temp.assert_true(ok boolean,label text) returns void language plpgsql as $$ begin if ok is distinct from true then raise exception 'FAILED: %',label; end if; end $$;
create function pg_temp.denied(q text,expected text) returns void language plpgsql as $$ begin begin execute q; exception when others then if position(expected in sqlerrm)>0 then return; end if; raise exception 'Wrong refusal: %',sqlerrm; end; raise exception 'Unexpected permission: %',q; end $$;
create temp table result(k text primary key,v jsonb); grant all on result to authenticated;
set local role authenticated;
select set_config('request.jwt.claim.sub','33333333-0000-0000-0000-000000000002',true);
insert into result values('bill',to_jsonb(fn_record_meter_reading('55555555-0000-0000-0000-000000000001',100,date_trunc('month',now())+interval '1 day','abababab-0000-0000-0000-000000000010')));
select set_config('request.jwt.claim.sub','33333333-0000-0000-0000-000000000001',true);
select fn_post_bill_amount((select (v#>>'{}')::uuid from result where k='bill'),249.40,date_trunc('month',fn_ph_today())::date+27,now(),'abababab-0000-0000-0000-000000000011');
insert into result values('initial',fn_get_billing_schedule());
select pg_temp.assert_true((select (v->>'cutoff_minutes')::integer=720 from result where k='initial'),'Default noon');
insert into result values('saved',fn_save_billing_schedule(25,31,810,(select (v->>'version')::uuid from result where k='initial'),'abababab-0000-0000-0000-000000000001'));
select pg_temp.assert_true((select v->>'due_day'='25' and v->>'cutoff_day'='31' and v->>'cutoff_minutes'='810' from result where k='saved'),'One atomic save');
select pg_temp.assert_true(fn_save_billing_schedule(25,31,810,(select (v->>'version')::uuid from result where k='initial'),'abababab-0000-0000-0000-000000000001')=(select v from result where k='saved'),'Retry does not duplicate revision');
select pg_temp.denied(format('select fn_save_billing_schedule(26,31,810,%L::uuid,%L::uuid)',(select v->>'version' from result where k='initial'),'abababab-0000-0000-0000-000000000002'),'Schedule changed');
select pg_temp.assert_true(not exists(select 1 from billing_schedule_versions where area_id<>app.current_area()),'Area RLS');
select set_config('request.jwt.claim.sub','33333333-0000-0000-0000-000000000003',true);
select pg_temp.assert_true(fn_get_billing_schedule()->>'due_day'='25','Cashier can read schedule');
select pg_temp.denied($q$select fn_save_billing_schedule(25,28,720,null,'abababab-0000-0000-0000-000000000003')$q$,'required role');
reset role;
select pg_temp.assert_true((app.trip_cutoff('11111111-0000-0000-0000-00000000000a',date '2028-02-01') at time zone 'Asia/Manila')=timestamp '2028-02-29 13:30','Last-day clamp and PH timezone');
set local role authenticated;
select set_config('request.jwt.claim.sub','33333333-0000-0000-0000-000000000002',true);
select fn_close_boheco_trip(date_trunc('month',fn_ph_today())::date);
reset role;
insert into result select 'closed',to_jsonb(t) from boheco_trips t where area_id='11111111-0000-0000-0000-00000000000a' and trip_month=date_trunc('month',fn_ph_today())::date;
set local role authenticated;
select set_config('request.jwt.claim.sub','33333333-0000-0000-0000-000000000001',true);
insert into result values('future',fn_save_billing_schedule(27,27,660,(select (v->>'version')::uuid from result where k='saved'),'abababab-0000-0000-0000-000000000004'));
select pg_temp.assert_true((select (v->>'effective_month')::date=(date_trunc('month',fn_ph_today())+interval '1 month')::date from result where k='future'),'Closed month defers changes');
reset role;
select pg_temp.assert_true((select due_date=date_trunc('month',fn_ph_today())::date+27 from bills where id=(select (v#>>'{}')::uuid from result where k='bill')),'Posted due date unchanged');
select pg_temp.assert_true(fn_save_billing_schedule(25,31,810,(select (v->>'version')::uuid from result where k='initial'),'abababab-0000-0000-0000-000000000001')=(select v from result where k='saved'),'Lost-response retry returns original saved revision');
select pg_temp.assert_true((select to_jsonb(t)=(select v from result where k='closed') from boheco_trips t where area_id='11111111-0000-0000-0000-00000000000a' and trip_month=date_trunc('month',fn_ph_today())::date),'Closed trip unchanged');
select pg_temp.assert_true(app.bill_collection_deadline('11111111-0000-0000-0000-00000000000a',date_trunc('month',fn_ph_today())::date+24)=(select (v->>'closed_at')::timestamptz from result where k='closed'),'Early closure is effective immediately');
select pg_temp.assert_true(not has_function_privilege('anon','fn_get_billing_schedule()','execute'),'Anonymous cannot read');
select pg_temp.assert_true(not has_function_privilege('authenticated','app.billing_schedule_payload(uuid)','execute'),'Private payload cannot bypass RLS');

-- A non-default deadline is enforced by the background tick without a staff snapshot.
set local role authenticated;
select set_config('request.jwt.claim.sub','33333333-0000-0000-0000-000000000004',true);
insert into result values('other_bill',to_jsonb(fn_record_meter_reading('55555555-0000-0000-0000-000000000007',100,date_trunc('month',now())+interval '1 day','abababab-0000-0000-0000-000000000020')));
select set_config('request.jwt.claim.sub','33333333-0000-0000-0000-000000000006',true);
select fn_post_bill_amount((select (v#>>'{}')::uuid from result where k='other_bill'),100,fn_ph_today(),now(),'abababab-0000-0000-0000-000000000021');
reset role;
update billing_schedule_versions set cutoff_day=extract(day from fn_ph_today()),cutoff_minutes=0 where area_id='11111111-0000-0000-0000-00000000000b';
select pg_temp.assert_true(not exists(select 1 from bill_settlements where bill_id=(select (v#>>'{}')::uuid from result where k='other_bill')),'Custom deadline initially open');
select app.run_boheco_cutoffs();
select pg_temp.assert_true(exists(select 1 from bill_settlements where bill_id=(select (v#>>'{}')::uuid from result where k='other_bill') and state='review'),'Server tick enforces saved deadline');
set local role authenticated;
select set_config('request.jwt.claim.sub','44444444-0000-0000-0000-000000000007',true);
select pg_temp.assert_true((select count(*)=1 from v_bill_status where collection_cutoff_at is not null),'Consumer can read own deadline');
select pg_temp.assert_true(not exists(select 1 from billing_schedule_versions where area_id<>'11111111-0000-0000-0000-00000000000b'),'Consumer cannot read another area schedule');
reset role;
rollback;
\echo 'Atomic schedule, retries, stale versions, role/area access, timezone and frozen early closure passed.'
