-- Apply after monthly compensation. Preserves balances and handed-over funds.
begin;
alter table boheco_trips add column is_collection_closed boolean not null default true;
alter table boheco_trips add column completed_at timestamptz;
alter table boheco_trips add column completed_by uuid references profiles(id);

create function app.route_uncovered_overdue(p_area uuid) returns void
language plpgsql security definer set search_path=public,pg_temp as $$
begin
 perform 1 from areas where id=p_area for update;
 update bill_settlements s set state='settled',updated_at=now()
 from bills b where b.id=s.bill_id and s.area_id=p_area and s.state='review' and b.balance<=0;
 update bill_settlements s set route='boheco',state='awaiting_referral',updated_at=now()
 from bills b where b.id=s.bill_id and s.area_id=p_area and s.state='review'
 and b.balance>0 and b.waiver_amount=0 and b.due_date<fn_ph_today() and s.boheco_amount>0;
end $$;
revoke all on function app.route_uncovered_overdue(uuid) from public,anon,authenticated;

-- Routing tells the consumer where to pay, never claims BOHECO was informed.
create function app.notify_boheco_route() returns trigger
language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if new.route='boheco' and new.state='awaiting_referral' and
 (tg_op='INSERT' or old.route is distinct from 'boheco') then
  perform fn_queue_notification(new.consumer_id,'overdue','push',
   'Pay at BOHECO: Your bill is not covered by the reserve fund. Please pay at the BOHECO main office and give your receipt to the Meter Reader for verification.',new.bill_id);
 end if;
 return new;
end $$;
revoke all on function app.notify_boheco_route() from public,anon,authenticated;
create trigger notify_boheco_route after insert or update on bill_settlements
for each row execute function app.notify_boheco_route();

-- Update existing implementations without losing salary reservations or schedule rules.
do $$ declare d text; begin
 d:=pg_get_functiondef('app.close_boheco_trip(uuid,date,uuid)'::regprocedure);
 d:=replace(d,'on conflict(area_id,trip_month) do nothing;',
 'on conflict(area_id,trip_month) do update set is_collection_closed=true,closed_at=now(),closed_by=p_actor where not boheco_trips.is_collection_closed;');
 d:=replace(d,'return t;', 'perform app.route_uncovered_overdue(p_area); return t;');
 if position('app.route_uncovered_overdue(p_area)' in d)=0 then raise exception 'Close trip integration not found'; end if;
 execute d;
 d:=pg_get_functiondef('public.fn_allocate_boheco_trip(uuid,uuid[],numeric[],uuid)'::regprocedure);
 if position('app.compensation_reserved(a)' in d)=0 then raise exception 'Install monthly compensation first'; end if;
 d:=replace(d,'and balance=s.consumer_amount)', 'and balance=s.consumer_amount and balance>0 and waiver_amount=0 and due_date>=fn_ph_today())');
 if position('due_date>=fn_ph_today()' in d)=0 then raise exception 'Allocation eligibility integration not found'; end if;
 d:=replace(d,'Balance changed. Refresh the trip before allocation','Bill paid, overdue or changed. Refresh the trip before allocation');
 d:=replace(d,'select coalesce(sum(boheco_amount),0) into needed',
 'update bill_settlements st set state=''settled'',updated_at=now() from bills b where b.id=st.bill_id and st.trip_id=t.id and st.state=''review'' and b.balance<=0; select coalesce(sum(boheco_amount),0) into needed');
 execute d;
 d:=pg_get_functiondef('public.fn_confirm_boheco_payment(uuid,numeric,text,timestamptz,text,uuid)'::regprocedure);
 d:=replace(d,'''handed_over'',''referred''','''handed_over'',''awaiting_referral'',''referred''');
 execute d;
 d:=pg_get_functiondef('public.fn_correct_settlement(uuid,text)'::regprocedure);
 d:=replace(d,'set route=''review'',state=''review'',updated_at=now()', 'set route=''boheco'',state=''awaiting_referral'',updated_at=now()');
 execute d;
end $$;

create function public.fn_complete_boheco_trip(p_trip uuid,p_expected_bill_ids uuid[]) returns void
language plpgsql security definer set search_path=public,pg_temp as $$
declare a uuid:=app.settlement_actor(array['meter_reader']::user_role[]); t boheco_trips; ids uuid[]; s bill_settlements;
begin
 perform 1 from areas where id=a for update;
 select * into t from boheco_trips where id=p_trip and area_id=a for update;
 if not found then raise exception 'Trip unavailable in your area'; end if;
 perform app.ensure_boheco_cutoffs(a);
 if exists(select 1 from bill_settlements where trip_id=t.id and state in ('review','handed_over')) then
  raise exception 'Finish allocation and record reserve fund BOHECO payments before completing the trip';
 end if;
 select coalesce(array_agg(bill_id order by bill_id),'{}'::uuid[]) into ids
 from bill_settlements where trip_id=t.id and route='boheco' and state='awaiting_referral';
 if cardinality(ids)=0 and t.completed_at is not null then return; end if;
 if ids is distinct from (select coalesce(array_agg(x order by x),'{}'::uuid[]) from unnest(p_expected_bill_ids) x) then
  raise exception 'Trip changed. Refresh and review the households before completing';
 end if;
 for s in update bill_settlements set state='referred',referred_at=now(),updated_at=now()
 where trip_id=t.id and route='boheco' and state='awaiting_referral' returning * loop
  insert into settlement_audit(area_id,bill_id,actor_id,action)
  values(a,s.bill_id,auth.uid(),'referred');
 end loop;
 update boheco_trips set completed_at=now(),completed_by=auth.uid() where id=t.id;
 insert into settlement_audit(area_id,actor_id,action,detail)
 values(a,auth.uid(),'trip_completed',jsonb_build_object('trip_id',t.id,'reported_bills',ids));
end $$;
revoke all on function fn_complete_boheco_trip(uuid,uuid[]) from public,anon;
grant execute on function fn_complete_boheco_trip(uuid,uuid[]) to authenticated;
revoke execute on function fn_confirm_boheco_referral(uuid) from authenticated;

-- An overdue bill can precede the configured cutoff. A provisional trip must
-- not close collection for other households; only explicit/elapsed cutoff does.
create or replace function app.bill_collection_deadline(p_area uuid,p_due date) returns timestamptz
language sql stable set search_path=public,pg_temp as $$
 select least(app.trip_cutoff(p_area,app.bill_trip_month(p_area,p_due)),
 (select closed_at from boheco_trips where area_id=p_area and trip_month=app.bill_trip_month(p_area,p_due) and is_collection_closed))
$$;
create or replace function app.ensure_boheco_cutoffs(p_area uuid) returns void
language plpgsql security definer set search_path=public,pg_temp as $$
declare m date; t uuid;
begin
 perform 1 from areas where id=p_area for update;
 for m in select x.month from (
  select distinct app.bill_trip_month(p_area,b.due_date) as month from bills b join consumers c on c.id=b.consumer_id
  where c.area_id=p_area and b.balance>0 and b.waiver_amount=0
  union select trip_month from boheco_trips where area_id=p_area and is_collection_closed
 ) x where now()>=app.trip_cutoff(p_area,x.month) or exists(
 select 1 from boheco_trips bt where bt.area_id=p_area and bt.trip_month=x.month and bt.is_collection_closed)
 order by x.month loop perform app.close_boheco_trip(p_area,m,null); end loop;
 for m in select distinct app.bill_trip_month(p_area,b.due_date) from bills b join consumers c on c.id=b.consumer_id
 where c.area_id=p_area and c.account_status='active' and b.balance>0 and b.waiver_amount=0 and b.due_date<fn_ph_today()
 and not exists(select 1 from bill_settlements st where st.bill_id=b.id)
 order by 1 loop
  insert into boheco_trips(area_id,trip_month,scheduled_cutoff_at,is_collection_closed)
  values(p_area,m,app.trip_cutoff(p_area,m),false) on conflict(area_id,trip_month) do nothing;
  select id into t from boheco_trips where area_id=p_area and trip_month=m;
  insert into bill_settlements(bill_id,trip_id,area_id,consumer_id,consumer_amount,boheco_amount)
  select b.id,t,p_area,b.consumer_id,b.balance,greatest(0,coalesce(b.cooperative_amount,b.total_amount)-b.amount_paid)
  from bills b join consumers c on c.id=b.consumer_id where c.area_id=p_area and c.account_status='active'
  and b.balance>0 and b.waiver_amount=0 and b.due_date<fn_ph_today() and app.bill_trip_month(p_area,b.due_date)=m
  on conflict(bill_id) do nothing;
  update bill_settlements set route='pondo',state='awaiting_repayment' where trip_id=t and state='review' and boheco_amount=0;
 end loop;
 perform app.route_uncovered_overdue(p_area);
end $$;

create or replace function app.run_boheco_cutoffs() returns void
language plpgsql security definer set search_path=public,pg_temp as $$
declare a uuid;
begin
 for a in select distinct c.area_id from bills b join consumers c on c.id=b.consumer_id
 left join bill_settlements s on s.bill_id=b.id
 where c.account_status='active' and b.balance>0 and b.waiver_amount=0 and b.due_date is not null
 and (s.bill_id is null or s.state='review')
 and (b.due_date<fn_ph_today() or now()>=app.bill_collection_deadline(c.area_id,b.due_date))
 order by c.area_id
 loop perform app.ensure_boheco_cutoffs(a); end loop;
end $$;
revoke all on function app.run_boheco_cutoffs() from public,anon,authenticated;
-- Backfill only waiting bills; no money debited and no report to BOHECO fabricated.
select app.run_boheco_cutoffs();
do $$ begin
 if exists(select 1 from pg_extension where extname='pg_cron') then
  perform cron.schedule('billalert-billing-cutoffs','* * * * *','select app.run_boheco_cutoffs()');
 else
  raise warning 'Enable pg_cron and schedule app.run_boheco_cutoffs(): automatic routing requires the server job';
 end if;
end $$;
commit;
