-- Area billing defaults; historical bills and closed trips retain their dates.
begin;
create table public.billing_schedule_versions (
 id uuid primary key default gen_random_uuid(), area_id uuid not null references areas(id),
 due_day integer not null check(due_day between 1 and 31),
 cutoff_day integer not null check(cutoff_day between 1 and 31),
 cutoff_minutes integer not null check(cutoff_minutes between 0 and 1439),
 effective_month date not null check(effective_month=date_trunc('month',effective_month)::date),
 created_at timestamptz not null default clock_timestamp(), changed_by uuid references profiles(id), client_uuid uuid unique
);
create index billing_schedule_area_month on billing_schedule_versions(area_id,effective_month desc,created_at desc,id);
insert into billing_schedule_versions(area_id,due_day,cutoff_day,cutoff_minutes,effective_month)
 select id,28,28,720,date '0001-01-01' from areas;
alter table billing_schedule_versions enable row level security;
create policy billing_schedule_read on billing_schedule_versions for select to authenticated using (
 exists(select 1 from profiles p where p.id=auth.uid() and p.account_status='active') and
 (area_id=app.current_area() or exists(select 1 from consumers c where c.profile_id=auth.uid() and c.area_id=billing_schedule_versions.area_id))
);
revoke all on billing_schedule_versions from public,anon,authenticated;
grant select on billing_schedule_versions to authenticated;
alter table boheco_trips add column scheduled_cutoff_at timestamptz;
update boheco_trips set scheduled_cutoff_at=app.trip_cutoff(trip_month);
alter table boheco_trips alter column scheduled_cutoff_at set not null;

create function app.trip_cutoff(p_area uuid,p_month date) returns timestamptz
language plpgsql stable set search_path=public,pg_temp as $$
declare m date:=date_trunc('month',p_month)::date; d integer; minutes integer; frozen timestamptz;
begin
 if m is null then return null; end if;
 select scheduled_cutoff_at into frozen from boheco_trips where area_id=p_area and trip_month=m;
 if frozen is not null then return frozen; end if;
 select cutoff_day,cutoff_minutes into d,minutes from billing_schedule_versions
 where area_id=p_area and effective_month<=m order by effective_month desc,created_at desc,id desc limit 1;
 return (m+least(coalesce(d,28),extract(day from m+interval '1 month'-interval '1 day')::integer)-1
 + time '00:00'+make_interval(mins=>coalesce(minutes,720))) at time zone 'Asia/Manila';
end $$;
create function app.bill_trip_month(p_area uuid,p_due date) returns date
language sql stable set search_path=public,pg_temp as $$
 select (date_trunc('month',p_due)::date+case when
 (app.trip_cutoff(p_area,date_trunc('month',p_due)::date) at time zone 'Asia/Manila')::date<p_due
 then interval '1 month' else interval '0' end)::date
$$;
create function app.bill_collection_deadline(p_area uuid,p_due date) returns timestamptz
language sql stable set search_path=public,pg_temp as $$
 select least(app.trip_cutoff(p_area,app.bill_trip_month(p_area,p_due)),
 (select closed_at from boheco_trips where area_id=p_area and trip_month=app.bill_trip_month(p_area,p_due)))
$$;
revoke all on function app.trip_cutoff(uuid,date),app.bill_trip_month(uuid,date),app.bill_collection_deadline(uuid,date) from public,anon;
grant execute on function app.trip_cutoff(uuid,date),app.bill_trip_month(uuid,date),app.bill_collection_deadline(uuid,date) to authenticated;

create function app.billing_schedule_payload(p_area uuid) returns jsonb
language sql stable security definer set search_path=public,pg_temp as $$
 select jsonb_build_object('version',s.id,'due_day',coalesce(s.due_day,28),'cutoff_day',coalesce(s.cutoff_day,28),
 'cutoff_minutes',coalesce(s.cutoff_minutes,720),'effective_month',coalesce(s.effective_month,date '0001-01-01'),'timezone','Asia/Manila')
 from (select 1) x left join lateral (select * from billing_schedule_versions where area_id=p_area order by created_at desc,id desc limit 1) s on true
$$;
revoke all on function app.billing_schedule_payload(uuid) from public,anon,authenticated;
create function public.fn_get_billing_schedule() returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
declare a uuid:=app.settlement_actor(array['admin','cashier','meter_reader']::user_role[]);
begin return app.billing_schedule_payload(a); end $$;
create function public.fn_save_billing_schedule(p_due_day integer,p_cutoff_day integer,p_cutoff_minutes integer,p_expected_version uuid,p_client_uuid uuid) returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
declare a uuid:=app.settlement_actor(array['admin']::user_role[]); previous billing_schedule_versions; retry billing_schedule_versions;
 m date:=date_trunc('month',fn_ph_today())::date; effective date; proposed timestamptz;
begin
 if p_due_day is null or p_due_day not between 1 and 31 or p_cutoff_day is null or p_cutoff_day not between 1 and 31
 or p_cutoff_minutes is null or p_cutoff_minutes not between 0 and 1439 or p_client_uuid is null then raise exception 'Choose valid schedule days and time'; end if;
 select * into retry from billing_schedule_versions where client_uuid=p_client_uuid;
 if found then
 if retry.area_id<>a or retry.changed_by<>auth.uid() or retry.due_day<>p_due_day or retry.cutoff_day<>p_cutoff_day or retry.cutoff_minutes<>p_cutoff_minutes then raise exception 'Schedule request does not match its previous save'; end if;
 return jsonb_build_object('version',retry.id,'due_day',retry.due_day,'cutoff_day',retry.cutoff_day,
 'cutoff_minutes',retry.cutoff_minutes,'effective_month',retry.effective_month,'timezone','Asia/Manila');
 end if;
 select * into previous from billing_schedule_versions where area_id=a order by created_at desc,id desc limit 1;
 if previous.id is distinct from p_expected_version then raise exception 'Schedule changed. Reload the saved schedule before trying again'; end if;
 -- Close any elapsed trips using the old schedule before changing future rules.
 perform app.ensure_boheco_cutoffs(a);
 proposed:=(m+least(p_cutoff_day,extract(day from m+interval '1 month'-interval '1 day')::integer)-1+time '00:00'+make_interval(mins=>p_cutoff_minutes)) at time zone 'Asia/Manila';
 effective:=case when now()>=app.trip_cutoff(a,m) or now()>=proposed or exists(select 1 from boheco_trips where area_id=a and trip_month=m) then (m+interval '1 month')::date else m end;
 effective:=greatest(effective,previous.effective_month);
 insert into billing_schedule_versions(area_id,due_day,cutoff_day,cutoff_minutes,effective_month,changed_by,client_uuid)
 values(a,p_due_day,p_cutoff_day,p_cutoff_minutes,effective,auth.uid(),p_client_uuid);
 return app.billing_schedule_payload(a);
end $$;
revoke all on function fn_get_billing_schedule(),fn_save_billing_schedule(integer,integer,integer,uuid,uuid) from public,anon;
grant execute on function fn_get_billing_schedule(),fn_save_billing_schedule(integer,integer,integer,uuid,uuid) to authenticated;

create or replace function app.close_boheco_trip(p_area uuid,p_month date,p_actor uuid) returns uuid
language plpgsql security definer set search_path=public,pg_temp as $$
declare t uuid; added integer;
begin
 perform 1 from areas where id=p_area for update;
 insert into boheco_trips(area_id,trip_month,closed_by,scheduled_cutoff_at) values(p_area,p_month,p_actor,app.trip_cutoff(p_area,p_month))
  on conflict(area_id,trip_month) do nothing;
 select id into t from boheco_trips where area_id=p_area and trip_month=p_month;
 -- Late-priced bills are added to a new review rather than silently collected.
 insert into bill_settlements(bill_id,trip_id,area_id,consumer_id,consumer_amount,boheco_amount)
 select b.id,t,p_area,b.consumer_id,b.balance,
  greatest(0,coalesce(b.cooperative_amount,b.total_amount)-b.amount_paid)
 from bills b join consumers c on c.id=b.consumer_id join billing_cycles bc on bc.id=b.billing_cycle_id
 where c.area_id=p_area and c.account_status='active' and b.balance>0 and b.waiver_amount=0
  and bc.period_start<=p_month and b.due_date<=(app.trip_cutoff(p_area,p_month) at time zone 'Asia/Manila')::date
 on conflict(bill_id) do nothing;
 get diagnostics added = row_count;
 if added>0 then
  perform app.queue_staff_alert(p_area,'cashier', 'pondo-review:'||t::text||':'||(select count(*) from bill_settlements where trip_id=t)::text,
   'Reserve fund review ready','Collection is closed. Prepare the BOHECO trip and select bills within the available reserve fund.','/cashier/remit');
 end if;
 -- BOHECO may already have received its whole share through an earlier
 -- partial cash payment. Only rounding remains; no zero-peso referral.
 update bill_settlements set route='pondo',state='awaiting_repayment' where trip_id=t and state='review' and boheco_amount=0;
 return t;
end $$;

create or replace function app.ensure_boheco_cutoffs(p_area uuid) returns void
language plpgsql security definer set search_path=public,pg_temp as $$
declare m date;
begin
 perform 1 from areas where id=p_area for update;
 for m in select x.month from (
  select distinct app.bill_trip_month(p_area,b.due_date) as month
  from bills b join consumers c on c.id=b.consumer_id where c.area_id=p_area and b.balance>0 and b.waiver_amount=0
  union select trip_month from boheco_trips where area_id=p_area
 ) x where now()>=app.trip_cutoff(p_area,x.month) or exists(select 1 from boheco_trips t where t.area_id=p_area and t.trip_month=x.month)
 order by x.month
 loop perform app.close_boheco_trip(p_area,m,null); end loop;
end $$;

-- Append view columns to preserve callers' existing contracts.
do $$ declare d text; changed text; begin
 d:=pg_get_viewdef('public.v_bill_status'::regclass,true);
 changed:=regexp_replace(d,'COALESCE\(\( SELECT s.state.*?END\) AS settlement_state',
 'COALESCE((SELECT s.state FROM bill_settlements s WHERE s.bill_id=b.id),CASE WHEN b.balance>0 AND b.waiver_amount=0 AND b.due_date IS NOT NULL AND now()>=app.bill_collection_deadline(c.area_id,b.due_date) THEN ''review''::text ELSE NULL::text END) AS settlement_state');
 if changed=d then raise exception 'Could not locate settlement state in bill view'; end if;
 changed:=regexp_replace(changed,'\s+FROM (public\.)?bills b',', app.bill_collection_deadline(c.area_id,b.due_date) AS collection_cutoff_at FROM bills b');
 execute 'create or replace view public.v_bill_status with (security_invoker=true) as '||changed;
 d:=pg_get_viewdef('public.v_consumer_current_bill'::regclass,true);
 d:=regexp_replace(d,'\s+FROM (public\.)?v_bill_status vb',', vb.collection_cutoff_at FROM v_bill_status vb');
 execute 'create or replace view public.v_consumer_current_bill with (security_invoker=true) as '||d;
 d:=pg_get_functiondef('public.fn_settlement_snapshot()'::regprocedure);
 if position($needle$'available',coalesce$needle$ in d)=0 then raise exception 'Snapshot contract changed'; end if;
 d:=replace(d,$needle$'available',coalesce$needle$,$needle$'schedule',app.billing_schedule_payload(a),'available',coalesce$needle$);
 execute d;
end $$;
create or replace function app.run_boheco_cutoffs() returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare a uuid;
begin
 for a in select distinct c.area_id from bills b join consumers c on c.id=b.consumer_id
 where c.account_status='active' and b.balance>0 and b.waiver_amount=0 and b.due_date is not null
 and not exists(select 1 from bill_settlements s where s.bill_id=b.id)
 and now()>=app.bill_collection_deadline(c.area_id,b.due_date)
 loop perform app.ensure_boheco_cutoffs(a); end loop;
end $$;
-- Server tick supports any saved time; only elapsed, unsettled bills are processed.
do $$ begin
 if exists(select 1 from pg_extension where extname='pg_cron') then
  if exists(select 1 from cron.job where jobname='billalert-noon-boheco-cutoff') then perform cron.unschedule('billalert-noon-boheco-cutoff'); end if;
  perform cron.schedule('billalert-billing-cutoffs','* * * * *','select app.run_boheco_cutoffs()');
 end if;
end $$;
commit;
