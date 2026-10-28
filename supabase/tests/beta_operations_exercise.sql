-- LOCAL TEST ONLY: exercise the new tables before resetting them.
do $$ begin
 if current_database() not like 'billalert_beta_kit_%' then raise exception 'Disposable beta-kit database required'; end if;
end $$;
begin;
create temp table f(k text primary key,v uuid); grant all on f to authenticated;
insert into f select username,id from profiles where username in('mario.ombajin','ledesman.dormal','mercedita.gales','virgilio.busalanan');
insert into f select p.username||'-bill',b.id from bills b join consumers c on c.id=b.consumer_id join profiles p on p.id=c.profile_id where b.bill_no like 'BETA-%';
set local role authenticated;
select set_config('request.jwt.claim.sub',(select v::text from f where k='mario.ombajin'),true);
select fn_post_bill_amount((select v from f where k='mario.ombajin-bill'),149.40,fn_ph_today()+2,now(),gen_random_uuid());
select set_config('request.jwt.claim.sub',(select v::text from f where k='mercedita.gales'),true);
select fn_record_payment(array[(select v from f where k='mario.ombajin-bill')],array[150::numeric],200,now(),gen_random_uuid());
select fn_record_remit_handover(date_trunc('month',fn_ph_today())::date);
select fn_pay_reader_compensation(date_trunc('month',fn_ph_today())::date,(select v from f where k='ledesman.dormal'));
select set_config('request.jwt.claim.sub',(select v::text from f where k='ledesman.dormal'),true);
insert into f values('trip',fn_close_boheco_trip(date_trunc('month',fn_ph_today())::date));
select set_config('request.jwt.claim.sub',(select v::text from f where k='mercedita.gales'),true);
select fn_allocate_boheco_trip((select v from f where k='trip'),array[(select v from f where k='ledesman.dormal-bill')],array[250::numeric],(select v from f where k='ledesman.dormal'));
select set_config('request.jwt.claim.sub',(select v::text from f where k='ledesman.dormal'),true);
select fn_confirm_boheco_payment((select v from f where k='ledesman.dormal-bill'),249.40,'BETA-LOCAL-RECEIPT',now(),'Local test evidence',gen_random_uuid());
select set_config('request.jwt.claim.sub',(select v::text from f where k='mercedita.gales'),true);
select fn_record_payment(array[(select v from f where k='ledesman.dormal-bill')],array[250::numeric],250,now(),gen_random_uuid());
select set_config('request.jwt.claim.sub',(select v::text from f where k='ledesman.dormal'),true);
select fn_complete_boheco_trip(s.trip_id,array_agg(bill_id order by bill_id)) from bill_settlements s
where trip_id=(select trip_id from bill_settlements where bill_id=(select v from f where k='virgilio.busalanan-bill'))
and route='boheco' and state='awaiting_referral' group by s.trip_id;
select set_config('request.jwt.claim.sub',(select v::text from f where k='mario.ombajin'),true);
select fn_issue_disconnection_notice((select id from consumers where profile_id=(select v from f where k='virgilio.busalanan')),'Local beta test notice',now(),gen_random_uuid());
reset role;
commit;
