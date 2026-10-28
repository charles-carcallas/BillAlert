-- Combined reserve-fund settlement and billing schedule update.
-- Run ONCE in Supabase SQL Editor after the earlier account/notice updates.
-- This does not reset data or create a sample reserve balance.
-- If any statement fails, the entire update rolls back.
begin;
do $$ begin
 if to_regclass('public.boheco_trips') is not null or to_regclass('public.billing_schedule_versions') is not null then
  raise exception 'Part of this update is already installed. Do not run the combined script again';
 end if;
 if to_regprocedure('public.fn_notice_review(uuid)') is null then
  raise exception 'Apply the earlier account and notice migrations before this update';
 end if;
end $$;
-- REVIEW ONLY. Apply with the updated APK after reconciling queued cash.
-- Existing approval records are retained as audit history, not converted to payments.
create table public.boheco_trips (
 id uuid primary key default gen_random_uuid(), area_id uuid not null references public.areas(id),
 trip_month date not null check(extract(day from trip_month)=1),
 closed_at timestamptz not null default now(), closed_by uuid references public.profiles(id),
 allocated_at timestamptz, allocated_by uuid references public.profiles(id),
 reader_id uuid references public.profiles(id), unique(area_id,trip_month)
);
create table public.bill_settlements (
 bill_id uuid primary key references public.bills(id), trip_id uuid not null references public.boheco_trips(id),
 area_id uuid not null references public.areas(id), consumer_id uuid not null references public.consumers(id),
 route text not null default 'review' check(route in ('review','pondo','boheco')),
 state text not null default 'review' check(state in ('review','handed_over','awaiting_referral','referred','awaiting_repayment','settled')),
 consumer_amount numeric(12,2) not null check(consumer_amount>0),
 boheco_amount numeric(12,2) not null check(boheco_amount>=0),
 reference text, evidence text, paid_at timestamptz, verified_by uuid references public.profiles(id),
 referred_at timestamptz, transaction_id uuid references public.payment_transactions(id),
 supply_status text not null default 'unknown' check(supply_status in ('unknown','disconnected','reconnected')),
 supply_evidence text,
 updated_at timestamptz not null default now()
);
create table public.pondo_ledger (
 id uuid primary key default gen_random_uuid(), area_id uuid not null references public.areas(id),
 amount numeric(12,2) not null check(amount<>0),
 kind text not null check(kind in ('opening','contribution','handover','repayment','returned','correction','withdrawal')),
 bill_id uuid references public.bills(id), transaction_id uuid references public.payment_transactions(id),
 actor_id uuid not null references public.profiles(id), reason text not null check(length(trim(reason))>0),
 client_uuid uuid not null unique, occurred_at timestamptz not null default now()
);
create unique index pondo_one_opening on public.pondo_ledger(area_id) where kind='opening';
create unique index pondo_one_repayment on public.pondo_ledger(transaction_id) where kind='repayment';
create index pondo_area_time on public.pondo_ledger(area_id,occurred_at desc);
create index settlement_area_state on public.bill_settlements(area_id,state);
create index settlement_trip on public.bill_settlements(trip_id);
create table public.boheco_payment_evidence (
 id uuid primary key default gen_random_uuid(), bill_id uuid not null references public.bills(id),
 area_id uuid not null references public.areas(id), reference text not null check(length(trim(reference))>0),
 amount numeric(12,2) not null check(amount>0), paid_at timestamptz not null,
 evidence text not null check(length(trim(evidence))>0), verified_by uuid not null references public.profiles(id),
 verified_at timestamptz not null default now(), client_uuid uuid not null unique,
 reversed_at timestamptz, reversed_by uuid references public.profiles(id), reversal_reason text
);
-- One reference can cover several bills on one official receipt, but each line
-- is unique and the confirmation below verifies the expected household/amount.
create unique index boheco_evidence_line on public.boheco_payment_evidence(area_id,lower(trim(reference)),bill_id) where reversed_at is null;
create table public.settlement_audit (
 id bigint generated always as identity primary key, area_id uuid not null references public.areas(id),
 bill_id uuid references public.bills(id), actor_id uuid references public.profiles(id),
 action text not null, detail jsonb not null default '{}', occurred_at timestamptz not null default now()
);
alter table public.bills add column external_paid numeric(12,2) not null default 0 check(external_paid>=0);
alter table public.bills add constraint bill_payment_sources_valid check(
 external_paid=0 or (total_amount is not null and waiver_amount=0 and external_paid+amount_paid<=total_amount));
alter table public.payment_transactions add column collection_kind text not null default 'regular' check(collection_kind in ('regular','pondo_repayment'));

do $$ declare t text; begin
 foreach t in array array['boheco_trips','bill_settlements','pondo_ledger','boheco_payment_evidence','settlement_audit'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('revoke all on public.%I from public,anon,authenticated',t);
  execute format('grant select on public.%I to authenticated',t);
  execute format('create policy staff_area_read on public.%I for select to authenticated using (area_id=app.current_area() and app.current_role() in (''admin'',''cashier'',''meter_reader''))',t);
 end loop;
end $$;
create policy own_settlement_read on public.bill_settlements for select to authenticated using(
 exists(select 1 from public.consumers c where c.id=consumer_id and c.profile_id=auth.uid()));
create policy own_trip_read on public.boheco_trips for select to authenticated using(
 exists(select 1 from public.bill_settlements s join public.consumers c on c.id=s.consumer_id where s.trip_id=boheco_trips.id and c.profile_id=auth.uid()));
create policy own_boheco_evidence_read on public.boheco_payment_evidence for select to authenticated using(
 exists(select 1 from public.bills b join public.consumers c on c.id=b.consumer_id where b.id=bill_id and c.profile_id=auth.uid()));

create or replace function public.fn_bills_sync_derived() returns trigger language plpgsql as $$
begin
 if new.total_amount is null then new.balance:=null; new.status:='unpriced';
 elsif new.waiver_amount>0 then new.balance:=0; new.status:='waived';
 else
  new.balance:=new.total_amount-new.amount_paid-new.external_paid;
  new.status:=case when new.balance<=0 then 'paid'::bill_status
   when new.amount_paid+new.external_paid>0 then 'partial'::bill_status else 'unpaid'::bill_status end;
 end if; return new;
end $$;
drop trigger trg_bills_sync_derived on public.bills;
create trigger trg_bills_sync_derived before insert or update of amount_paid,total_amount,external_paid on public.bills
 for each row execute function public.fn_bills_sync_derived();

create function app.settlement_actor(p_roles user_role[]) returns uuid
language plpgsql security definer set search_path=public,pg_temp as $$
declare a uuid; checked_area uuid;
begin
 select area_id into a from profiles where id=auth.uid() and account_status='active'
  and staff_enabled and role=any(p_roles);
 if a is null then raise exception 'An active staff account with the required role is needed'; end if;
 -- Match account-management lock order: area, then profile, then household/bill.
 -- Recheck permissions after waiting for a concurrent role/access change.
 perform 1 from areas where id=a for update;
 select area_id into checked_area from profiles where id=auth.uid() and area_id=a
  and account_status='active' and staff_enabled and role=any(p_roles) for share;
 if checked_area is null then raise exception 'An active staff account with the required role is needed'; end if;
 return a;
end $$;
create function app.trip_cutoff(p_month date) returns timestamptz
language sql immutable set search_path=public,pg_temp as $$
 select (date_trunc('month',p_month)::date+27+time '12:00') at time zone 'Asia/Manila'
$$;
create function app.close_boheco_trip(p_area uuid,p_month date,p_actor uuid) returns uuid
language plpgsql security definer set search_path=public,pg_temp as $$
declare t uuid; added integer;
begin
 perform 1 from areas where id=p_area for update;
 insert into boheco_trips(area_id,trip_month,closed_by) values(p_area,p_month,p_actor)
  on conflict(area_id,trip_month) do nothing;
 select id into t from boheco_trips where area_id=p_area and trip_month=p_month;
 -- Late-priced bills are added to a new review rather than silently collected.
 insert into bill_settlements(bill_id,trip_id,area_id,consumer_id,consumer_amount,boheco_amount)
 select b.id,t,p_area,b.consumer_id,b.balance,
  greatest(0,coalesce(b.cooperative_amount,b.total_amount)-b.amount_paid)
 from bills b join consumers c on c.id=b.consumer_id join billing_cycles bc on bc.id=b.billing_cycle_id
 where c.area_id=p_area and c.account_status='active' and b.balance>0 and b.waiver_amount=0
  and bc.period_start<=p_month and b.due_date<=(app.trip_cutoff(p_month) at time zone 'Asia/Manila')::date
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
create function app.ensure_boheco_cutoffs(p_area uuid) returns void
language plpgsql security definer set search_path=public,pg_temp as $$
declare m date;
begin
 perform 1 from areas where id=p_area for update;
 for m in select x.month from (
  select distinct (date_trunc('month',b.due_date)::date + case when extract(day from b.due_date)>28 then interval '1 month' else interval '0' end)::date as month
  from bills b join consumers c on c.id=b.consumer_id where c.area_id=p_area and b.balance>0 and b.waiver_amount=0
  union select trip_month from boheco_trips where area_id=p_area
 ) x where now()>=app.trip_cutoff(x.month) or exists(select 1 from boheco_trips t where t.area_id=p_area and t.trip_month=x.month)
 order by x.month
 loop perform app.close_boheco_trip(p_area,m,null); end loop;
end $$;
create function public.fn_close_boheco_trip(p_month date) returns uuid
language plpgsql security definer set search_path=public,pg_temp as $$
declare a uuid:=app.settlement_actor(array['meter_reader']::user_role[]); m date:=date_trunc('month',p_month)::date;
begin
 if m is null or m>date_trunc('month',fn_ph_today())::date then raise exception 'Choose the current or an earlier billing month'; end if;
 return app.close_boheco_trip(a,m,auth.uid());
end $$;

create function public.fn_pondo_entry(p_amount numeric,p_kind text,p_reason text,p_client_uuid uuid) returns uuid
language plpgsql security definer set search_path=public,pg_temp as $$
declare a uuid:=app.settlement_actor(array['cashier','admin']::user_role[]); old pondo_ledger; v uuid;
begin
 perform 1 from areas where id=a for update;
 if p_client_uuid is null or p_amount is null or p_amount=0 or p_amount<>round(p_amount,2) or nullif(trim(p_reason),'') is null then raise exception 'Enter an amount and reason'; end if;
 select * into old from pondo_ledger where client_uuid=p_client_uuid;
 if found then
  if old.area_id<>a or old.actor_id<>auth.uid() or old.amount<>p_amount or old.kind<>p_kind or old.reason<>trim(p_reason) then raise exception 'Reference conflicts with a different reserve fund entry'; end if;
  return old.id;
 end if;
 if p_kind not in ('opening','contribution','withdrawal','correction') or p_kind is null then raise exception 'Invalid reserve fund entry'; end if;
 if p_kind in ('opening','contribution') and p_amount<=0 then raise exception 'Opening balance and contributions must be positive'; end if;
 if p_kind='withdrawal' and p_amount>=0 then raise exception 'Withdrawals must be negative'; end if;
 if p_kind='correction' and app.current_role()<>'admin' then raise exception 'Only Admin may correct reserve fund'; end if;
 if p_amount<0 and coalesce((select sum(amount) from pondo_ledger where area_id=a),0)+p_amount<0 then raise exception 'Insufficient available reserve fund'; end if;
 insert into pondo_ledger(area_id,amount,kind,reason,actor_id,client_uuid)
 values(a,p_amount,p_kind,trim(p_reason),auth.uid(),p_client_uuid) returning id into v;
 return v;
end $$;

create function public.fn_allocate_boheco_trip(p_trip uuid,p_bill_ids uuid[],p_expected_amounts numeric[],p_reader uuid) returns void
language plpgsql security definer set search_path=public,pg_temp as $$
declare a uuid:=app.settlement_actor(array['cashier']::user_role[]); t boheco_trips; s bill_settlements; needed numeric; i integer;
begin
 perform 1 from areas where id=a for update;
 select * into t from boheco_trips where id=p_trip and area_id=a for update;
 if not found then raise exception 'Trip unavailable in your area'; end if;
 if coalesce(cardinality(p_bill_ids),0)<>coalesce(cardinality(p_expected_amounts),0) or array_position(p_bill_ids,null) is not null
  or array_position(p_expected_amounts,null) is not null or (select count(distinct x) from unnest(p_bill_ids) x)<>coalesce(cardinality(p_bill_ids),0) then raise exception 'Invalid allocation'; end if;
 if not exists(select 1 from profiles where id=p_reader and area_id=a and role='meter_reader' and account_status='active' and staff_enabled) then raise exception 'Choose an active Meter Reader'; end if;
 -- All selected balances are checked under the same area/household/bill locks as collection.
 perform 1 from consumers where id in(select consumer_id from bill_settlements where trip_id=t.id) order by id for update;
 perform 1 from bills where id in(select bill_id from bill_settlements where trip_id=t.id) order by id for update;
 for i in 1..coalesce(cardinality(p_bill_ids),0) loop
  select * into s from bill_settlements where bill_id=p_bill_ids[i] and trip_id=t.id and state='review';
  if not found or s.consumer_amount is distinct from p_expected_amounts[i]
   or not exists(select 1 from bills where id=s.bill_id and balance=s.consumer_amount) then raise exception 'Balance changed. Refresh the trip before allocation'; end if;
 end loop;
 select coalesce(sum(boheco_amount),0) into needed from bill_settlements where bill_id=any(p_bill_ids) and trip_id=t.id and state='review';
 if needed>coalesce((select sum(amount) from pondo_ledger where area_id=a),0) then raise exception 'Insufficient available reserve fund'; end if;
 if not exists(select 1 from bill_settlements where trip_id=t.id and state='review') then raise exception 'This allocation is already confirmed. Refresh to see its status'; end if;
 insert into pondo_ledger(area_id,amount,kind,bill_id,actor_id,reason,client_uuid)
 select a,-boheco_amount,'handover',bill_id,auth.uid(),'Reserve fund handed to Meter Reader',gen_random_uuid()
 from bill_settlements where trip_id=t.id and state='review' and bill_id=any(p_bill_ids) and boheco_amount>0;
 update bill_settlements set route=case when bill_id=any(p_bill_ids) then 'pondo' else 'boheco' end,
 state=case when bill_id=any(p_bill_ids) then case when boheco_amount=0 then 'awaiting_repayment' else 'handed_over' end else 'awaiting_referral' end,updated_at=now()
 where trip_id=t.id and state='review';
 update boheco_trips set allocated_at=now(),allocated_by=auth.uid(),reader_id=p_reader where id=t.id;
 insert into settlement_audit(area_id,actor_id,action,detail) values(a,auth.uid(),'allocation',jsonb_build_object('trip_id',t.id,'selected',p_bill_ids,'handed_over',needed,'reader_id',p_reader));
 perform app.queue_staff_alert(a,'meter_reader','pondo-trip:'||t.id::text||':'||now()::text,'BOHECO trip prepared','Cashier confirmed the allocation. Review the handed-over money and households to report.','/reader/remittance');
end $$;

create function public.fn_record_supply_status(p_bill uuid,p_status text,p_evidence text) returns void
language plpgsql security definer set search_path=public,pg_temp as $$
declare a uuid:=app.settlement_actor(array['meter_reader']::user_role[]);
begin
 if p_status is null or p_status not in ('disconnected','reconnected') or nullif(trim(p_evidence),'') is null then raise exception 'Select the confirmed supply status and BOHECO evidence'; end if;
 perform 1 from areas where id=a for update;
 update bill_settlements set supply_status=p_status,supply_evidence=trim(p_evidence),updated_at=now() where bill_id=p_bill and area_id=a;
 if not found then raise exception 'Household settlement unavailable in your area'; end if;
 insert into settlement_audit(area_id,bill_id,actor_id,action,detail) values(a,p_bill,auth.uid(),'supply_status',jsonb_build_object('status',p_status,'evidence',trim(p_evidence)));
end $$;

create function public.fn_confirm_boheco_referral(p_bill uuid) returns void
language plpgsql security definer set search_path=public,pg_temp as $$
declare a uuid:=app.settlement_actor(array['meter_reader']::user_role[]);
begin
 perform 1 from areas where id=a for update;
 update bill_settlements set state='referred',referred_at=now(),updated_at=now()
 where bill_id=p_bill and area_id=a and route='boheco' and state='awaiting_referral';
 if not found then
  if exists(select 1 from bill_settlements where bill_id=p_bill and area_id=a and state='referred') then return; end if;
  raise exception 'This bill is not awaiting referral';
 end if;
 insert into settlement_audit(area_id,bill_id,actor_id,action) values(a,p_bill,auth.uid(),'referred');
end $$;

create function public.fn_confirm_boheco_payment(p_bill uuid,p_amount numeric,p_reference text,p_paid_at timestamptz,p_evidence text,p_client_uuid uuid) returns uuid
language plpgsql security definer set search_path=public,pg_temp as $$
declare a uuid:=app.settlement_actor(array['meter_reader']::user_role[]); s bill_settlements; b bills; e boheco_payment_evidence; v uuid;
begin
 perform 1 from areas where id=a for update;
 if p_client_uuid is null or nullif(trim(p_reference),'') is null or nullif(trim(p_evidence),'') is null
  or p_paid_at is null or p_paid_at>now() or p_amount is null or p_amount<=0 then raise exception 'Enter the receipt reference, full BOHECO amount, payment date and verification evidence'; end if;
 select * into e from boheco_payment_evidence where client_uuid=p_client_uuid;
 if found then
  if e.bill_id<>p_bill or e.area_id<>a or e.verified_by<>auth.uid() or e.amount<>p_amount or e.reference<>trim(p_reference)
   or e.paid_at<>p_paid_at or e.evidence<>trim(p_evidence) then raise exception 'Payment reference conflicts with another confirmation'; end if;
  if e.reversed_at is not null then raise exception 'This confirmation was reversed by Admin'; end if;
  return e.id;
 end if;
 select * into s from bill_settlements where bill_id=p_bill and area_id=a;
 if not found or s.state not in ('handed_over','referred') then raise exception 'Confirm the handover or referral first'; end if;
 perform 1 from consumers where id=s.consumer_id for update;
 select * into b from bills where id=p_bill for update;
 if b.balance<>s.consumer_amount or p_amount<>s.boheco_amount then raise exception 'Receipt amount or bill balance changed. Verify the full BOHECO amount'; end if;
 -- A reused receipt on a different household is rejected. Multi-month receipts
 -- for the same household are allowed, with one exact full-balance line per bill.
 if exists(select 1 from boheco_payment_evidence x join bills bx on bx.id=x.bill_id
  where x.area_id=a and lower(trim(x.reference))=lower(trim(p_reference)) and x.reversed_at is null
   and bx.consumer_id<>s.consumer_id) then raise exception 'This BOHECO reference is already recorded for another household'; end if;
 insert into boheco_payment_evidence(bill_id,area_id,reference,amount,paid_at,evidence,verified_by,client_uuid)
 values(p_bill,a,trim(p_reference),p_amount,p_paid_at,trim(p_evidence),auth.uid(),p_client_uuid) returning id into v;
 update bill_settlements set state=case when route='pondo' then 'awaiting_repayment' else 'settled' end,
 reference=trim(p_reference),evidence=trim(p_evidence),paid_at=p_paid_at,verified_by=auth.uid(),updated_at=now() where bill_id=p_bill;
 -- Direct BOHECO payment clears the local rounded bill in full; it never
 -- becomes a cashier receipt. Reserve fund payment leaves the consumer debt intact.
 if s.route='boheco' then update bills set external_paid=s.consumer_amount where id=p_bill; end if;
 insert into settlement_audit(area_id,bill_id,actor_id,action,detail)
 values(a,p_bill,auth.uid(),'boheco_paid',jsonb_build_object('evidence_id',v,'amount',p_amount,'route',s.route));
 return v;
end $$;

create function public.fn_correct_settlement(p_bill uuid,p_reason text) returns void
language plpgsql security definer set search_path=public,pg_temp as $$
declare a uuid:=app.settlement_actor(array['admin']::user_role[]); s bill_settlements;
begin
 if nullif(trim(p_reason),'') is null then raise exception 'A correction reason is required'; end if;
 perform 1 from areas where id=a for update;
 select * into s from bill_settlements where bill_id=p_bill and area_id=a;
 if not found then raise exception 'Settlement unavailable'; end if;
 perform 1 from consumers where id=s.consumer_id for update;
 perform 1 from bills where id=p_bill for update;
 if s.route='boheco' and s.state='settled' then
  update boheco_payment_evidence set reversed_at=now(),reversed_by=auth.uid(),reversal_reason=trim(p_reason) where bill_id=p_bill and reversed_at is null;
  update bills set external_paid=0 where id=p_bill;
  update bill_settlements set state='referred',reference=null,evidence=null,paid_at=null,verified_by=null,updated_at=now() where bill_id=p_bill;
 elsif s.route='pondo' and s.state='handed_over' then
  -- Admin confirms the full handed-over cash has physically been returned.
  if s.boheco_amount>0 then
   insert into pondo_ledger(area_id,amount,kind,bill_id,actor_id,reason,client_uuid)
   values(a,s.boheco_amount,'returned',p_bill,auth.uid(),trim(p_reason),gen_random_uuid());
  end if;
  update bill_settlements set route='review',state='review',updated_at=now() where bill_id=p_bill;
 else raise exception 'This state requires reconciliation; it cannot be automatically reversed'; end if;
 insert into settlement_audit(area_id,bill_id,actor_id,action,detail) values(a,p_bill,auth.uid(),'correction',jsonb_build_object('previous_state',s.state,'reason',trim(p_reason)));
end $$;

-- Guards replace the old approval requirement. Reserve fund requires a full repayment;
-- regular collections retain their amount rules and earlier-debt ordering.
create function app.check_settlement_collection(p_bill_ids uuid[],p_amounts numeric[]) returns void
language plpgsql security definer set search_path=public,pg_temp as $$
declare a uuid:=app.settlement_actor(array['cashier']::user_role[]); c uuid; b bills; s bill_settlements; i integer;
begin
 perform 1 from areas where id=a for update;
 perform app.ensure_boheco_cutoffs(a);
 if coalesce(cardinality(p_bill_ids),0)=0 or cardinality(p_bill_ids) is distinct from cardinality(p_amounts)
  or array_position(p_bill_ids,null) is not null or array_position(p_amounts,null) is not null
  or (select count(distinct x) from unnest(p_bill_ids) x)<>cardinality(p_bill_ids) then raise exception 'Choose bills and full amounts'; end if;
 select consumer_id into c from bills where id=p_bill_ids[1];
 perform 1 from consumers where id=c and area_id=a and account_status='active' for update;
 if not found then raise exception 'Household unavailable in your area'; end if;
 perform 1 from bills where consumer_id=c order by id for update;
 for i in 1..cardinality(p_bill_ids) loop
  select * into b from bills where id=p_bill_ids[i];
  if not found or b.consumer_id<>c then raise exception 'Choose bills for one household'; end if;
  if b.total_amount is null or b.balance<=0 or p_amounts[i]<=0 or p_amounts[i]>b.balance then raise exception 'Refresh and enter an amount within the remaining balance'; end if;
  select * into s from bill_settlements where bill_id=b.id;
  if found and s.state<>'awaiting_repayment' then raise exception 'Collection is closed. Follow the assigned reserve fund or BOHECO route'; end if;
  if s.state='awaiting_repayment' and b.balance is distinct from p_amounts[i] then raise exception 'Collect the entire remaining balance. Refresh before collecting'; end if;
  if exists(select 1 from bills x join billing_cycles xc on xc.id=x.billing_cycle_id join billing_cycles bc on bc.id=b.billing_cycle_id
   where x.consumer_id=c and x.id<>b.id and x.balance>0 and (x.due_date<b.due_date or xc.period_start<bc.period_start)
    and x.id<>all(p_bill_ids)) then raise exception 'Settle earlier unpaid bills before the current bill'; end if;
 end loop;
 if exists(select 1 from bill_settlements where bill_id=any(p_bill_ids) and route='pondo')
  and exists(select 1 from unnest(p_bill_ids) id where not exists(select 1 from bill_settlements ss where ss.bill_id=id and ss.route='pondo')) then raise exception 'Record reserve fund repayment separately from normal bill collection'; end if;
end $$;
create or replace function public.fn_check_collection(p_bill_ids uuid[],p_amounts numeric[]) returns void
language plpgsql security definer set search_path=public,pg_temp as $$
begin perform app.check_settlement_collection(p_bill_ids,p_amounts); end $$;
create or replace function public.fn_record_payment(p_bill_ids uuid[],p_amounts numeric[],p_cash_tendered numeric default null,
 p_paid_at timestamptz default now(),p_client_uuid uuid default null) returns uuid
language plpgsql security definer set search_path=public,pg_temp as $$
declare a uuid:=app.settlement_actor(array['cashier']::user_role[]); old payment_transactions; v uuid; i integer; repayment boolean;
begin
 if p_client_uuid is null then raise exception 'A payment reference is required'; end if;
 perform 1 from areas where id=a for update;
 select * into old from payment_transactions where client_uuid=p_client_uuid;
 if found then
  if old.cashier_id<>auth.uid() or old.area_id<>a or old.cash_tendered is distinct from p_cash_tendered
   or cardinality(p_bill_ids) is distinct from cardinality(p_amounts)
   or (select count(*) from payments where transaction_id=old.id) is distinct from cardinality(p_bill_ids)
   or (select count(distinct x) from unnest(p_bill_ids) x) is distinct from cardinality(p_bill_ids) then raise exception 'Payment reference conflicts with another handover'; end if;
  for i in 1..cardinality(p_bill_ids) loop
   if not exists(select 1 from payments where transaction_id=old.id and bill_id=p_bill_ids[i] and amount_paid=p_amounts[i]) then raise exception 'Payment reference conflicts with another allocation'; end if;
  end loop; return old.id;
 end if;
 perform app.check_settlement_collection(p_bill_ids,p_amounts);
 select exists(select 1 from bill_settlements where bill_id=any(p_bill_ids) and route='pondo') into repayment;
 v:=app.record_payment_core_v18(p_bill_ids,p_amounts,p_cash_tendered,now(),p_client_uuid);
 if repayment then
  update payment_transactions set collection_kind='pondo_repayment' where id=v;
  insert into pondo_ledger(area_id,amount,kind,transaction_id,actor_id,reason,client_uuid)
  select a,sum(amount_paid),'repayment',v,auth.uid(),'Full reserve fund repayment',p_client_uuid from payments where transaction_id=v;
  update bill_settlements set state='settled',transaction_id=v,updated_at=now() where bill_id=any(p_bill_ids);
 end if; return v;
end $$;

-- Append view fields without shifting existing consumers of these views.
do $$ declare d text; begin
 d:=pg_get_viewdef('public.v_bill_status'::regclass,true);
 d:=regexp_replace(d,'(\s+FROM (public\.)?bills b)',E', b.external_paid, coalesce((select s.state from public.bill_settlements s where s.bill_id=b.id), case when b.balance>0 and b.due_date is not null and now() >= (((date_trunc(''month'',b.due_date)::date + case when extract(day from b.due_date)>28 then interval ''1 month'' else interval ''0'' end)::date+27+time ''12:00'') at time zone ''Asia/Manila'') then ''review'' end) as settlement_state\\1');
 if position('b.external_paid' in d)=0 then raise exception 'Review bill view integration'; end if;
 execute 'create or replace view public.v_bill_status with (security_invoker=true) as '||d;
 d:=pg_get_viewdef('public.v_payment_history'::regclass,true);
 d:=regexp_replace(d,'(\s+FROM (public\.)?payments pay)',E', pt.collection_kind\\1');
 execute 'create or replace view public.v_payment_history with (security_invoker=true) as '||d;
end $$;
do $$ declare d text; begin
 d:=pg_get_viewdef('public.v_consumer_current_bill'::regclass,true);
 d:=regexp_replace(d,'(\s+FROM (public\.)?v_bill_status vb)',E', vb.external_paid, vb.settlement_state\\1');
 if position('vb.external_paid' in d)=0 then raise exception 'Review consumer bill integration'; end if;
 execute 'create or replace view public.v_consumer_current_bill with (security_invoker=true) as '||d;
end $$;

-- Reserve fund repayments are cash receipts, but never money to remit to BOHECO again.
-- These fields describe regular collections; reserve fund itself is the actual ledger.
create or replace function public.fn_rounding_fund(p_area uuid) returns table(
 remit_month date,collected numeric(12,2),to_boheco numeric(12,2),rounding numeric(12,2),gap numeric(12,2),
 fund_before numeric(12,2),kept_for_gap numeric(12,2),reader_pay numeric(12,2),fund_after numeric(12,2))
language plpgsql stable security definer set search_path=public,pg_temp as $$
begin
 if p_area is distinct from app.current_area() or app.current_role() not in ('cashier','admin') then raise exception 'Reserve fund unavailable in your area'; end if;
 return query with monthly as (
 select date_trunc('month',(h.paid_at at time zone 'Asia/Manila')::date+case when extract(day from h.paid_at at time zone 'Asia/Manila')>28 then interval '1 month' else interval '0' end)::date as m,
 sum(h.amount_paid)::numeric(12,2) as cash,sum(coalesce(h.boheco_share,h.amount_paid))::numeric(12,2) as boheco
 from v_payment_history h where h.area_id=p_area and h.collection_kind='regular' group by 1)
 select m.m,m.cash,m.boheco,(m.cash-m.boheco)::numeric(12,2),0::numeric(12,2),
 coalesce((select sum(l.amount) from pondo_ledger l where l.area_id=p_area and l.occurred_at<((m.m)::timestamp at time zone 'Asia/Manila')),0)::numeric(12,2),
 0::numeric(12,2),0::numeric(12,2),coalesce((select sum(l.amount) from pondo_ledger l where l.area_id=p_area and l.occurred_at<((m.m+interval '1 month')::timestamp at time zone 'Asia/Manila')),0)::numeric(12,2)
 from monthly m order by m.m;
end $$;
create view public.v_bill_settlement with (security_invoker=true) as
 select s.*,b.bill_no,b.balance,bc.cycle_year,bc.cycle_month,c.consumer_no,
 c.first_name||' '||c.last_name as consumer_name,t.trip_month,t.reader_id
 from bill_settlements s join bills b on b.id=s.bill_id join billing_cycles bc on bc.id=b.billing_cycle_id
 join consumers c on c.id=s.consumer_id join boheco_trips t on t.id=s.trip_id;
grant select on public.v_bill_settlement to authenticated;
-- The existing overdue picker now includes closed, still-owed settlement bills
-- on the cutoff day itself. Historical approvals no longer control collection.
do $$ declare cols text; begin
 select string_agg(case column_name when 'approval_state' then 'a.state as approval_state'
  when 'approved_amount' then 'a.amount as approved_amount' else 'v.'||quote_ident(column_name) end,', ' order by ordinal_position)
 into cols from information_schema.columns where table_schema='public' and table_name='v_overdue_collection';
 execute 'create or replace view public.v_overdue_collection with (security_invoker=true) as select '||cols||', v.external_paid
 from public.v_bill_status v left join public.overdue_collection_approvals a on a.bill_id=v.id
 where v.balance>0 and (v.is_overdue or (v.settlement_state is not null and v.settlement_state<>''settled''))
 and app.current_role() in (''admin'',''cashier'',''meter_reader'')';
end $$;

create function public.fn_settlement_snapshot() returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
declare a uuid:=app.settlement_actor(array['admin','cashier','meter_reader']::user_role[]);
begin
 perform app.ensure_boheco_cutoffs(a);
 return jsonb_build_object(
 'available',coalesce((select sum(amount) from pondo_ledger where area_id=a),0),
 'in_transit',coalesce((select sum(boheco_amount) from bill_settlements where area_id=a and route='pondo' and state='handed_over'),0),
 'owed_to_pondo',coalesce((select sum(b.balance) from bill_settlements s join bills b on b.id=s.bill_id where s.area_id=a and s.route='pondo' and s.state='awaiting_repayment'),0),
 'trips',coalesce((select jsonb_agg(to_jsonb(t) order by trip_month desc) from boheco_trips t where area_id=a),'[]'),
 'bills',coalesce((select jsonb_agg(to_jsonb(s) order by consumer_amount,bill_no) from v_bill_settlement s where area_id=a),'[]'),
 'readers',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',first_name||' '||last_name)) from profiles where area_id=a and role='meter_reader' and account_status='active' and staff_enabled),'[]'),
 'ledger',case when app.current_role()='meter_reader' then '[]'::jsonb else coalesce((select jsonb_agg(to_jsonb(x)) from (select * from pondo_ledger where area_id=a order by occurred_at desc limit 100) x),'[]') end,
 'audit',coalesce((select jsonb_agg(to_jsonb(x)) from (select * from settlement_audit where area_id=a order by occurred_at desc limit 100) x),'[]'));
end $$;

-- Verified external payment is accepted as evidence for settling a notice.
-- It is displayed as a BOHECO receipt, never fabricated as Cashier cash.
do $$ declare d text; begin
 d:=pg_get_viewdef('public.v_notice_review_records'::regclass,true);
 d:=replace(d,'(b.total_amount - b.waiver_amount)','(b.total_amount - b.waiver_amount - b.external_paid)');
 execute 'create or replace view public.v_notice_review_records with (security_invoker=true) as '||d;
end $$;
alter function public.fn_notice_review(uuid) set schema app;
alter function app.fn_notice_review(uuid) rename to notice_review_before_external;
revoke all on function app.notice_review_before_external(uuid) from public,anon,authenticated;
create function public.fn_notice_review(p_notice_id uuid) returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
declare result jsonb; extra jsonb;
begin
 result:=app.notice_review_before_external(p_notice_id);
 if result is null then return null; end if;
 select coalesce(jsonb_agg(jsonb_build_object('receipt_no','BOHECO · '||e.reference,'bill_no',b.bill_no,'amount_paid',e.amount,'paid_at',e.paid_at)),'[]') into extra
 from boheco_payment_evidence e join bills b on b.id=e.bill_id join notice_bill_items i on i.bill_id=b.id
 where i.notice_id=p_notice_id and e.reversed_at is null;
 return jsonb_set(result,'{receipts}',coalesce(result->'receipts','[]'::jsonb)||extra);
end $$;
revoke all on function public.fn_notice_review(uuid) from public,anon;
grant execute on function public.fn_notice_review(uuid) to authenticated;

-- Freeze old entry points so older clients cannot route around the cutoff.
create or replace function public.fn_overdue_decision(p_bill_id uuid,p_action text) returns void
language plpgsql as $$ begin raise exception 'Update BillAlert: use reserve fund allocation and BOHECO settlement'; end $$;
-- Some installations predate these retired approval APIs.
do $$ declare name text; f regprocedure; begin
 foreach name in array array['public.fn_request_overdue_household(uuid,uuid[],numeric[])','public.fn_authorize_overdue_batch(uuid,uuid[],numeric[])'] loop
  f:=to_regprocedure(name);
  if f is not null then execute format('revoke all on function %s from public,anon,authenticated',f); end if;
 end loop;
end $$;

-- Privileged helpers are private and have no client execute grants.
revoke all on function app.settlement_actor(user_role[]),app.trip_cutoff(date),app.close_boheco_trip(uuid,date,uuid),app.ensure_boheco_cutoffs(uuid),app.check_settlement_collection(uuid[],numeric[]) from public,anon,authenticated;
do $$ declare f regprocedure; begin
 foreach f in array array[
 'public.fn_close_boheco_trip(date)'::regprocedure,'public.fn_pondo_entry(numeric,text,text,uuid)'::regprocedure,
 'public.fn_allocate_boheco_trip(uuid,uuid[],numeric[],uuid)'::regprocedure,'public.fn_confirm_boheco_referral(uuid)'::regprocedure,
 'public.fn_confirm_boheco_payment(uuid,numeric,text,timestamptz,text,uuid)'::regprocedure,
 'public.fn_correct_settlement(uuid,text)'::regprocedure,'public.fn_settlement_snapshot()'::regprocedure] loop
 execute format('revoke all on function %s from public,anon',f);
 execute format('grant execute on function %s to authenticated',f);
 end loop;
end $$;
revoke all on function public.fn_record_supply_status(uuid,text,text) from public,anon;
grant execute on function public.fn_record_supply_status(uuid,text,text) to authenticated;

-- The scheduler is optional infrastructure: collection RPCs enforce the same
-- cutoff even without Cron. A cron job makes review visible with nobody online.
create function app.run_boheco_cutoffs() returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare a uuid; begin for a in select id from areas order by id loop perform app.ensure_boheco_cutoffs(a); end loop; end $$;
revoke all on function app.run_boheco_cutoffs() from public,anon,authenticated;
do $$ begin
 if exists(select 1 from pg_extension where extname='pg_cron') then
  perform cron.schedule('billalert-noon-boheco-cutoff','0 4 28 * *','select app.run_boheco_cutoffs()');
 end if;
end $$;

-- Area billing defaults; historical bills and closed trips retain their dates.
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
