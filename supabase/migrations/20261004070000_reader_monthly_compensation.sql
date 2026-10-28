-- Apply after reserve fund, billing schedule and referred-notice migrations.
begin;
create table public.reader_compensation (
 id uuid primary key default gen_random_uuid(), area_id uuid not null references areas(id),
 month date not null check(month>=date '2026-10-01' and extract(day from month)=1),
 reader_id uuid not null references profiles(id), paid_by uuid not null references profiles(id),
 paid_at timestamptz not null default now(), ledger_id uuid not null references pondo_ledger(id),
 reversed_at timestamptz, reversed_by uuid references profiles(id), reversal_reason text,
 reversal_ledger_id uuid references pondo_ledger(id)
);
create unique index reader_compensation_month on reader_compensation(area_id,month) where reversed_at is null;
alter table reader_compensation enable row level security;
revoke all on reader_compensation from public,anon,authenticated;
grant select on reader_compensation to authenticated;
create policy compensation_area_read on reader_compensation for select to authenticated
 using(area_id=app.current_area() and app.current_role() in ('admin','cashier','meter_reader'));
create function app.compensation_reserved(a uuid) returns numeric language sql stable set search_path=public,pg_temp as $$
 select count(*)*500 from generate_series(date '2026-10-01',date_trunc('month',fn_ph_today())::date,interval '1 month') m
 where not exists(select 1 from reader_compensation p where p.area_id=a and p.month=m::date and p.reversed_at is null)
$$;
revoke all on function app.compensation_reserved(uuid) from public,anon,authenticated;
create function public.fn_pay_reader_compensation(p_month date,p_reader uuid) returns uuid
language plpgsql security definer set search_path=public,pg_temp as $$
declare a uuid:=app.settlement_actor(array['cashier']::user_role[]); v uuid; l uuid;
begin
 perform 1 from areas where id=a for update;
 if p_month is null or p_month<date '2026-10-01' or extract(day from p_month)<>1 or p_month>date_trunc('month',fn_ph_today())::date then raise exception 'Choose a compensation month from October 2026 through this month'; end if;
 select id into v from reader_compensation where area_id=a and month=p_month and reversed_at is null;
 if found then return v; end if;
 if not exists(select 1 from profiles where id=p_reader and area_id=a and role='meter_reader' and staff_enabled and account_status='active') then raise exception 'Choose an active Meter Reader in your area'; end if;
 if coalesce((select sum(amount) from pondo_ledger where area_id=a),0)<500 then raise exception 'Compensation pending: insufficient reserve fund'; end if;
 insert into pondo_ledger(area_id,amount,kind,actor_id,reason,client_uuid)
 values(a,-500,'withdrawal',auth.uid(),'Meter Reader compensation '||to_char(p_month,'YYYY-MM')||' (salary PHP 200 + transport PHP 300)',gen_random_uuid()) returning id into l;
 insert into reader_compensation(area_id,month,reader_id,paid_by,ledger_id) values(a,p_month,p_reader,auth.uid(),l) returning id into v;
 return v;
end $$;
create function public.fn_reverse_reader_compensation(p_id uuid,p_reason text) returns void
language plpgsql security definer set search_path=public,pg_temp as $$
declare a uuid:=app.settlement_actor(array['admin']::user_role[]); p reader_compensation; l uuid;
begin
 perform 1 from areas where id=a for update;
 if nullif(trim(p_reason),'') is null then raise exception 'Explain why cash was not handed over or was returned'; end if;
 select * into p from reader_compensation where id=p_id and area_id=a for update;
 if not found then raise exception 'Payout unavailable in your area'; end if;
 if p.reversed_at is not null then return; end if;
 insert into pondo_ledger(area_id,amount,kind,actor_id,reason,client_uuid)
 values(a,500,'correction',auth.uid(),'Compensation reversal: '||trim(p_reason),gen_random_uuid()) returning id into l;
 update reader_compensation set reversed_at=now(),reversed_by=auth.uid(),reversal_reason=trim(p_reason),reversal_ledger_id=l where id=p.id;
end $$;
revoke all on function fn_pay_reader_compensation(date,uuid),fn_reverse_reader_compensation(uuid,text) from public,anon;
grant execute on function fn_pay_reader_compensation(date,uuid),fn_reverse_reader_compensation(uuid,text) to authenticated;
-- Reserve all unpaid months before allocating household coverage or withdrawing funds.
do $$ declare d text; begin
 d:=pg_get_functiondef('public.fn_allocate_boheco_trip(uuid,uuid[],numeric[],uuid)'::regprocedure);
 d:=replace(d,'if needed>coalesce((select sum(amount) from pondo_ledger where area_id=a),0)', 'if needed>greatest(0,coalesce((select sum(amount) from pondo_ledger where area_id=a),0)-app.compensation_reserved(a))');
 if position('app.compensation_reserved(a)' in d)=0 then raise exception 'Allocation integration not found'; end if;
 execute d;
 d:=pg_get_functiondef('public.fn_pondo_entry(numeric,text,text,uuid)'::regprocedure);
 d:=replace(d,'if p_amount<0 and coalesce((select sum(amount) from pondo_ledger where area_id=a),0)+p_amount<0', 'if p_amount<0 and coalesce((select sum(amount) from pondo_ledger where area_id=a),0)+p_amount<app.compensation_reserved(a)');
 if position('app.compensation_reserved(a)' in d)=0 then raise exception 'Withdrawal integration not found'; end if;
 execute d;
end $$;
-- Keep historical waivers immutable; never waive newly priced bills.
create or replace function app.apply_reader_coverage() returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if tg_op='DELETE' then
  if old.waiver_amount>0 then raise exception 'Covered bills are immutable'; end if;
  return old;
 end if;
 if tg_op='UPDATE' and old.waiver_amount>0 then
  if new is distinct from old then raise exception 'Historical waived bills require review'; end if;
  return new;
 end if;
 if new.waiver_amount<>0 or new.waiver_assignment_id is not null or new.waived_at is not null then raise exception 'Automatic Meter Reader bill coverage has ended'; end if;
 return new;
end $$;
revoke execute on function fn_assign_reader_waiver(uuid,uuid,date) from authenticated;
-- Extend the established, role-checked snapshot without changing its existing fields.
alter function public.fn_settlement_snapshot() set schema app;
alter function app.fn_settlement_snapshot() rename to settlement_before_compensation;
revoke all on function app.settlement_before_compensation() from public,anon,authenticated;
create function public.fn_settlement_snapshot() returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare a uuid:=app.settlement_actor(array['admin','cashier','meter_reader']::user_role[]); result jsonb; reserved numeric;
begin
 result:=app.settlement_before_compensation(); reserved:=app.compensation_reserved(a);
 return result||jsonb_build_object(
 'compensation_reserved',reserved,
 'coverage_available',greatest(0,(result->>'available')::numeric-reserved),
 'compensation_months',coalesce((select jsonb_agg(jsonb_build_object('month',m::date,'id',p.id,'reader_id',p.reader_id,'reader_name',r.first_name||' '||r.last_name,'paid_at',p.paid_at) order by m)
 from generate_series(date '2026-10-01',date_trunc('month',fn_ph_today())::date,interval '1 month') m
 left join reader_compensation p on p.area_id=a and p.month=m::date and p.reversed_at is null left join profiles r on r.id=p.reader_id),'[]'::jsonb),
 'compensation_history',coalesce((select jsonb_agg(to_jsonb(p) order by paid_at desc) from reader_compensation p where area_id=a),'[]'::jsonb),
 'waiver_review',case when app.current_role()='admin' then coalesce((select jsonb_agg(jsonb_build_object('bill_no',b.bill_no,'consumer_name',c.first_name||' '||c.last_name,'amount',b.waiver_amount)) from bills b join consumers c on c.id=b.consumer_id where c.area_id=a and b.waiver_amount>0),'[]'::jsonb) else '[]'::jsonb end);
end $$;
revoke all on function fn_settlement_snapshot() from public,anon;
grant execute on function fn_settlement_snapshot() to authenticated;
commit;
