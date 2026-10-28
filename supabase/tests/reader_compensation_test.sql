-- Disposable local seeded database only. All fixture changes roll back.
\set ON_ERROR_STOP on
begin;
create function pg_temp.check_it(ok boolean,label text) returns void language plpgsql as $$ begin if ok is distinct from true then raise exception 'FAILED: %',label; end if; end $$;
create function pg_temp.denied(q text,expected text) returns void language plpgsql as $$ begin begin execute q; exception when others then if position(expected in sqlerrm)>0 then return; end if; raise exception 'Wrong refusal: %',sqlerrm; end; raise exception 'Unexpected permission: %',q; end $$;
create temp table f(k text primary key,v uuid); grant all on f to authenticated;
-- Existing recorded coverage must no longer waive the Reader's newly posted bill.
update consumers set profile_id='33333333-0000-0000-0000-000000000002' where id='55555555-0000-0000-0000-000000000001';
insert into reader_waiver_assignments(reader_id,consumer_id,area_id,meter_serial_no,start_month,assigned_by)
select '33333333-0000-0000-0000-000000000002',id,area_id,meter_serial_no,date '2026-10-01','33333333-0000-0000-0000-000000000001' from consumers where id='55555555-0000-0000-0000-000000000001';
set local role authenticated;
select set_config('request.jwt.claim.sub','33333333-0000-0000-0000-000000000002',true);
insert into f values('bill',fn_record_meter_reading('55555555-0000-0000-0000-000000000001',100,now(),gen_random_uuid()));
select pg_temp.denied($q$select fn_pay_reader_compensation(date '2026-10-01','33333333-0000-0000-0000-000000000002')$q$,'required role');
select set_config('request.jwt.claim.sub','33333333-0000-0000-0000-000000000001',true);
select fn_post_bill_amount((select v from f where k='bill'),249.40,fn_ph_today()+2,now(),gen_random_uuid());
select pg_temp.check_it((select waiver_amount=0 and balance=250 from bills where id=(select v from f where k='bill')),'New reader bill is payable normally');
select pg_temp.denied($q$select fn_assign_reader_waiver('33333333-0000-0000-0000-000000000002','55555555-0000-0000-0000-000000000001',date '2026-10-01')$q$,'permission denied');
select set_config('request.jwt.claim.sub','33333333-0000-0000-0000-000000000003',true);
select pg_temp.check_it((fn_settlement_snapshot()->>'compensation_reserved')::numeric>=500,'Current month reserved without ledger deduction');
select pg_temp.denied($q$select fn_pay_reader_compensation(date '2026-10-01','33333333-0000-0000-0000-000000000002')$q$,'insufficient');
select fn_pondo_entry(1000,'opening','Synthetic cash',gen_random_uuid());
select pg_temp.denied($q$select fn_pondo_entry(-501,'withdrawal','Cannot consume salary reserve',gen_random_uuid())$q$,'Insufficient');
select pg_temp.denied($q$select fn_pay_reader_compensation(date '2026-09-01','33333333-0000-0000-0000-000000000002')$q$,'October 2026');
select pg_temp.denied($q$select fn_pay_reader_compensation(date '2099-10-01','33333333-0000-0000-0000-000000000002')$q$,'this month');
select pg_temp.denied($q$select fn_pay_reader_compensation(date '2026-10-01','33333333-0000-0000-0000-000000000004')$q$,'your area');
select fn_pondo_entry(-300,'withdrawal','Synthetic expense',gen_random_uuid());
select set_config('request.jwt.claim.sub','33333333-0000-0000-0000-000000000002',true);
insert into f values('trip',fn_close_boheco_trip(date_trunc('month',fn_ph_today())::date));
select set_config('request.jwt.claim.sub','33333333-0000-0000-0000-000000000003',true);
select pg_temp.denied(format('select fn_allocate_boheco_trip(%L,array[%L::uuid],array[250::numeric],%L)',(select v from f where k='trip'),(select v from f where k='bill'),'33333333-0000-0000-0000-000000000002'),'Insufficient');
select fn_pondo_entry(300,'contribution','Replace test cash',gen_random_uuid());
insert into f values('payout',fn_pay_reader_compensation(date '2026-10-01','33333333-0000-0000-0000-000000000002'));
select pg_temp.check_it(fn_pay_reader_compensation(date '2026-10-01','33333333-0000-0000-0000-000000000004')=(select v from f where k='payout'),'Replacement cannot create a second payout');
select pg_temp.check_it((select sum(amount)=500 from pondo_ledger),'Exactly PHP500 deducted');
select pg_temp.check_it((select balance=250 from bills where id=(select v from f where k='bill')),'Payout does not pay own electricity bill');
select pg_temp.denied(format('select fn_reverse_reader_compensation(%L,''Mistake'')',(select v from f where k='payout')),'required role');
select set_config('request.jwt.claim.sub','33333333-0000-0000-0000-000000000006',true);
select pg_temp.check_it((select count(*)=0 from reader_compensation),'Other area cannot read payouts');
select pg_temp.denied(format('select fn_reverse_reader_compensation(%L,''Mistake'')',(select v from f where k='payout')),'unavailable');
select set_config('request.jwt.claim.sub','33333333-0000-0000-0000-000000000001',true);
select fn_reverse_reader_compensation((select v from f where k='payout'),'Cash was returned');
select fn_reverse_reader_compensation((select v from f where k='payout'),'Cash was returned');
select pg_temp.check_it((select sum(amount)=1000 from pondo_ledger),'Reversal restores cash once');
select pg_temp.check_it((fn_settlement_snapshot()->>'compensation_reserved')::numeric>=500,'Reversed month becomes pending again');
select set_config('request.jwt.claim.sub','33333333-0000-0000-0000-000000000003',true);
select fn_pay_reader_compensation(date '2026-10-01','33333333-0000-0000-0000-000000000002');
select pg_temp.check_it((select count(*)=1 from reader_compensation where reversed_at is null),'One valid payout after correction');
rollback;
