-- Disposable seeded LOCAL database only. All fixtures roll back.
\set ON_ERROR_STOP on
begin;
create function pg_temp.check_it(ok boolean,label text) returns void language plpgsql as $$ begin if ok is distinct from true then raise exception 'FAILED: %',label; end if; end $$;
create function pg_temp.denied(q text,expected text) returns void language plpgsql as $$ begin begin execute q; exception when others then if position(expected in sqlerrm)>0 then return; end if; raise exception 'Wrong refusal: %',sqlerrm; end; raise exception 'Unexpected success: %',q; end $$;
create temp table f(k text primary key,v uuid); grant all on f to authenticated;
create temp table versions(k text primary key,v timestamptz); grant all on versions to authenticated;
set local role authenticated;
select set_config('request.jwt.claim.sub','33333333-0000-0000-0000-000000000002',true);
insert into f values
 ('covered',fn_record_meter_reading('55555555-0000-0000-0000-000000000001',100,now(),gen_random_uuid())),
 ('direct',fn_record_meter_reading('55555555-0000-0000-0000-000000000002',100,now(),gen_random_uuid())),
 ('returned',fn_record_meter_reading('55555555-0000-0000-0000-000000000003',100,now(),gen_random_uuid()));
select set_config('request.jwt.claim.sub','33333333-0000-0000-0000-000000000001',true);
select fn_post_bill_amount(v,249.40,fn_ph_today()+1,now(),gen_random_uuid()) from f;
select set_config('request.jwt.claim.sub','33333333-0000-0000-0000-000000000002',true);
select fn_close_boheco_trip(date_trunc('month',fn_ph_today())::date);
insert into f select 'trip',trip_id from bill_settlements where bill_id=(select v from f where k='covered');
select set_config('request.jwt.claim.sub','33333333-0000-0000-0000-000000000003',true);
select fn_pondo_entry(1500,'opening','Synthetic cash',gen_random_uuid());
select fn_allocate_boheco_trip((select v from f where k='trip'),
 array[(select v from f where k='covered'),(select v from f where k='returned')],
 array[250::numeric,250::numeric],'33333333-0000-0000-0000-000000000002');
select set_config('request.jwt.claim.sub','33333333-0000-0000-0000-000000000002',true);
select fn_confirm_boheco_payment((select v from f where k='direct'),249.40,'DIRECT-WRONG',now(),'Receipt evidence',gen_random_uuid());
select fn_confirm_boheco_payment((select v from f where k='covered'),249.40,'COVERED-WRONG',now(),'Receipt evidence',gen_random_uuid());
insert into versions select 'direct',updated_at from bill_settlements where bill_id=(select v from f where k='direct');
insert into versions select 'covered',updated_at from bill_settlements where bill_id=(select v from f where k='covered');
insert into versions select 'returned',updated_at from bill_settlements where bill_id=(select v from f where k='returned');
-- Reader and other-area Admin cannot reverse these verifications.
select pg_temp.denied(format('select fn_correct_settlement_checked(%L,''Wrong receipt'',''reverse_verification'',%L,%L)',
 (select v from f where k='covered'),(select v from versions where k='covered'),gen_random_uuid()),'required role');
select set_config('request.jwt.claim.sub','33333333-0000-0000-0000-000000000006',true);
select pg_temp.denied(format('select fn_correct_settlement_checked(%L,''Wrong receipt'',''reverse_verification'',%L,%L)',
 (select v from f where k='covered'),(select v from versions where k='covered'),gen_random_uuid()),'unavailable');
select set_config('request.jwt.claim.sub','33333333-0000-0000-0000-000000000001',true);
select fn_correct_settlement_checked((select v from f where k='direct'),'Wrong receipt','reverse_verification',
 (select v from versions where k='direct'),'eeeeeeee-1000-0000-0000-000000000001');
select pg_temp.check_it((select state='awaiting_referral' and referred_at is null from bill_settlements where bill_id=(select v from f where k='direct')),'Unreported payment returns to awaiting report');
select pg_temp.check_it((select balance=250 and external_paid=0 from bills where id=(select v from f where k='direct')),'Direct reversal restores debt');
select fn_correct_settlement_checked((select v from f where k='covered'),'Wrong receipt','reverse_verification',
 (select v from versions where k='covered'),'eeeeeeee-1000-0000-0000-000000000002');
select fn_correct_settlement_checked((select v from f where k='covered'),'Wrong receipt','reverse_verification',
 (select v from versions where k='covered'),'eeeeeeee-1000-0000-0000-000000000002');
select pg_temp.check_it((select route='pondo' and state='handed_over' from bill_settlements where bill_id=(select v from f where k='covered')),'Covered correction keeps cash with Reader');
select pg_temp.check_it((select sum(amount)=1001.20 from pondo_ledger),'Reversal and retry do not credit returned cash');
select pg_temp.check_it((select count(*)=1 from boheco_payment_evidence where bill_id=(select v from f where k='covered') and reversed_at is not null),'Evidence retained as reversed');
select pg_temp.denied(format('select fn_correct_settlement_checked(%L,''Changed reason'',''reverse_verification'',%L,%L)',
 (select v from f where k='covered'),(select v from versions where k='covered'),'eeeeeeee-1000-0000-0000-000000000002'),'different details');
select pg_temp.denied(format('select fn_correct_settlement_checked(%L,''Stale screen'',''return_funds'',%L,%L)',
 (select v from f where k='covered'),(select v from versions where k='covered'),gen_random_uuid()),'Settlement changed');
select fn_correct_settlement_checked((select v from f where k='returned'),'Cash physically returned','return_funds',
 (select v from versions where k='returned'),'eeeeeeee-1000-0000-0000-000000000003');
select fn_correct_settlement_checked((select v from f where k='returned'),'Cash physically returned','return_funds',
 (select v from versions where k='returned'),'eeeeeeee-1000-0000-0000-000000000003');
select pg_temp.check_it((select sum(amount)=1250.60 from pondo_ledger),'Physical cash return credits once');
select set_config('request.jwt.claim.sub','33333333-0000-0000-0000-000000000003',true);
select pg_temp.denied(format('select fn_check_collection(array[%L::uuid],array[250::numeric])',(select v from f where k='covered')),'Collection is closed');
select set_config('request.jwt.claim.sub','33333333-0000-0000-0000-000000000002',true);
select fn_confirm_boheco_payment((select v from f where k='covered'),249.40,'COVERED-CORRECT',now(),'Correct receipt evidence',gen_random_uuid());
select fn_complete_boheco_trip((select v from f where k='trip'),array[(select v from f where k='direct'),(select v from f where k='returned')]);
insert into versions select 'reported',referred_at from bill_settlements where bill_id=(select v from f where k='direct');
select fn_confirm_boheco_payment((select v from f where k='direct'),249.40,'DIRECT-SECOND',now(),'Receipt evidence',gen_random_uuid());
select set_config('request.jwt.claim.sub','33333333-0000-0000-0000-000000000001',true);
-- Legacy clients cannot bypass an explicit action and version check.
select pg_temp.check_it(not has_function_privilege('authenticated','public.fn_correct_settlement(uuid,text)','EXECUTE'),'Legacy endpoint blocked');
select pg_temp.denied(format('select fn_correct_settlement(%L,''Wrong second receipt'')',(select v from f where k='direct')),'permission denied');
select fn_correct_settlement_checked((select v from f where k='direct'),'Wrong second receipt','reverse_verification',
 (select updated_at from bill_settlements where bill_id=(select v from f where k='direct')),gen_random_uuid());
select pg_temp.check_it((select state='referred' and referred_at=(select v from versions where k='reported') from bill_settlements where bill_id=(select v from f where k='direct')),'Existing reporting date survives reversal');
-- An old successful retry must not undo the newer correct verification.
select fn_correct_settlement_checked((select v from f where k='covered'),'Wrong receipt','reverse_verification',
 (select v from versions where k='covered'),'eeeeeeee-1000-0000-0000-000000000002');
select pg_temp.check_it((select state='awaiting_repayment' from bill_settlements where bill_id=(select v from f where k='covered')),'Retry does not reverse newer evidence');
reset role;
update bills set due_date=fn_ph_today()-1 where id=(select v from f where k='direct');
set local role authenticated;
select set_config('request.jwt.claim.sub','33333333-0000-0000-0000-000000000001',true);
select fn_issue_disconnection_notice('55555555-0000-0000-0000-000000000002','Unpaid after actual report',now(),gen_random_uuid());
select set_config('request.jwt.claim.sub','33333333-0000-0000-0000-000000000003',true);
select fn_record_payment(array[(select v from f where k='covered')],array[250::numeric],250,now(),gen_random_uuid());
select set_config('request.jwt.claim.sub','33333333-0000-0000-0000-000000000001',true);
select pg_temp.denied(format('select fn_correct_settlement_checked(%L,''Already repaid'',''reverse_verification'',%L,%L)',
 (select v from f where k='covered'),(select updated_at from bill_settlements where bill_id=(select v from f where k='covered')),gen_random_uuid()),'Reconcile');
select pg_temp.check_it((select sum(amount)=1500.60 from pondo_ledger),'Receipt money preserved after rejected reversal');
rollback;
