-- Save as "BA 40 - Sample bills PREVIEW". SYNTHETIC amounts, not actual debts.
-- Requires 20 + 30 committed. Defaults to rollback; review then change last line.
-- No receipt, payment, reported referral, or notice is fabricated.
begin;
set local lock_timeout='5s';
create temp table beta_seed_result(username text,scenario text,bill_id uuid) on commit drop;
do $$ declare
 a uuid; admin_id uuid; reader_id uuid; cashier_id uuid; c public.consumers;
 m date:=date_trunc('month',public.fn_ph_today())::date;
 old_m date:=(date_trunc('month',public.fn_ph_today())-interval '1 month')::date;
 due date; d integer; cycle uuid; reading uuid; bill uuid; r record;
begin
 select id,area_id into strict admin_id,a from public.profiles
 where username='mario.ombajin' and role='admin' and account_status='active' and staff_enabled;
 perform 1 from public.areas where id=a for update;
 select id into strict reader_id from public.profiles where username='ledesman.dormal'
 and role='meter_reader' and area_id=a and account_status='active' and staff_enabled;
 select id into strict cashier_id from public.profiles where username='mercedita.gales'
 and role='cashier' and area_id=a and account_status='active' and staff_enabled;
 if exists(select 1 from public.bills b join public.consumers hh on hh.id=b.consumer_id where hh.area_id=a)
 or exists(select 1 from public.meter_readings mr join public.consumers hh on hh.id=mr.consumer_id where hh.area_id=a)
 or exists(select 1 from public.pondo_ledger where area_id=a)
 then raise exception 'Area is not empty. Seed only after a reviewed reset; never overwrite testing.'; end if;
 if to_regclass('app.beta_job_pause') is null then raise exception 'Run 10_pause_jobs first.'; end if;
 if exists(select 1 from cron.job where jobname in('invoke-send-sms','billalert-billing-cutoffs') and active)
 then raise exception 'Pause background jobs before seeding.'; end if;

 -- Keep the upcoming payable samples ahead of the configured cutoff.
 if app.trip_cutoff(a,m)<=now()+interval '1 day' then m:=(m+interval '1 month')::date; end if;
 select due_day into d from public.billing_schedule_versions where area_id=a and effective_month<=m
 order by effective_month desc,created_at desc,id desc limit 1;
 due:=m+least(coalesce(d,28),extract(day from m+interval '1 month'-interval '1 day')::int)-1;
 if due<=public.fn_ph_today() then raise exception 'Sample due date is not in the future; review schedule first.'; end if;
 insert into public.billing_cycles(cycle_year,cycle_month,period_start,period_end)
 select extract(year from x)::int,extract(month from x)::int,x,(x+interval '1 month'-interval '1 day')::date
 from (values(m),(old_m)) dates(x) on conflict(cycle_year,cycle_month) do nothing;

 for r in select * from (values
   ('mario.ombajin',m,null::numeric,'Awaiting Admin amount'),
   ('ledesman.dormal',m,249.40::numeric,'Current payable OR cover on upcoming trip'),
   ('mercedita.gales',old_m,349.40::numeric,'Overdue: Pay at BOHECO'),
   ('virgilio.busalanan',old_m,449.40::numeric,'Overdue: Pay at BOHECO')
 ) cases(username,month,cooperative,scenario) loop
   select h.* into strict c from public.consumers h join public.profiles p on p.id=h.profile_id
   where p.username=r.username and p.account_status='active' and h.area_id=a and h.account_status='active';
   select id into strict cycle from public.billing_cycles where period_start=r.month
   and period_end=(r.month+interval '1 month'-interval '1 day')::date and not is_closed;
   insert into public.meter_readings(consumer_id,billing_cycle_id,previous_reading,current_reading,reading_date,recorded_by,client_uuid)
   values(c.id,cycle,c.opening_reading,c.opening_reading+100,r.month,reader_id,gen_random_uuid()) returning id into reading;
   insert into public.bills(bill_no,consumer_id,billing_cycle_id,meter_reading_id,consumption,generated_by)
   values('BETA-'||to_char(r.month,'YYYYMM')||'-'||replace(r.username,'.','-'),c.id,cycle,reading,100,reader_id)
   returning id into bill;
   if r.cooperative is not null then
     update public.bills set cooperative_amount=r.cooperative,total_amount=ceil(r.cooperative),
     due_date=case when r.month=old_m then (old_m+interval '1 month'-interval '1 day')::date else due end,
     priced_at=now(),priced_by=admin_id where id=bill;
   end if;
   insert into beta_seed_result values(r.username,r.scenario,bill);
 end loop;
 insert into public.pondo_ledger(area_id,amount,kind,actor_id,reason,client_uuid)
 values(a,2000,'opening',cashier_id,'[BETA SAMPLE] Fictional opening balance; no real cash received',gen_random_uuid());
 perform app.ensure_boheco_cutoffs(a);
 -- Fixtures must never send a real bill SMS. Only remove messages for these NEW bills.
 delete from public.notifications where bill_id in(select bill_id from beta_seed_result) and channel='sms';
 update public.notifications set message_content='[BETA SAMPLE] '||message_content
 where bill_id in(select bill_id from beta_seed_result) and channel='push';
 insert into public.account_events(area_id,actor_id,action,reason)
 values(a,admin_id,'beta_sample_seed','Four synthetic bills and PHP 2000 fictional reserve; not actual member debts or cash');
end $$;
select r.username,r.scenario,b.bill_no,b.due_date,b.cooperative_amount,b.total_amount,
 s.route,s.state from beta_seed_result r join public.bills b on b.id=r.bill_id
 left join public.bill_settlements s on s.bill_id=b.id order by r.username;
rollback;
