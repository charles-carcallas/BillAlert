-- REVIEW ONLY: apply after 18. No data is deleted or repriced.
-- Deploy together with the new app after reconciling pre-upgrade queued cash.
begin;

create table public.overdue_collection_approvals (
  bill_id uuid primary key references public.bills(id),
  consumer_id uuid not null references public.consumers(id),
  area_id uuid not null references public.areas(id),
  amount numeric(12,2) not null check (amount > 0),
  state text not null check (state in ('requested','approved','revoked','consumed')),
  requested_by uuid not null references public.profiles(id),
  approved_by uuid references public.profiles(id),
  updated_at timestamptz not null default now(),
  transaction_id uuid references public.payment_transactions(id)
);
create table public.overdue_collection_audit (
  id bigint generated always as identity primary key,
  bill_id uuid not null references public.bills(id),
  actor_id uuid not null references public.profiles(id),
  action text not null,
  amount numeric(12,2) not null,
  occurred_at timestamptz not null default now()
);
alter table public.overdue_collection_approvals enable row level security;
alter table public.overdue_collection_audit enable row level security;
create policy approval_read on public.overdue_collection_approvals for select to authenticated
  using (area_id = app.current_area() and app.current_role() in ('admin','cashier'));
create policy approval_audit_read on public.overdue_collection_audit for select to authenticated
  using (exists (select 1 from public.overdue_collection_approvals a where a.bill_id = overdue_collection_audit.bill_id));
revoke all on public.overdue_collection_approvals, public.overdue_collection_audit from public, anon, authenticated;
grant select on public.overdue_collection_approvals, public.overdue_collection_audit to authenticated;

create function public.fn_overdue_decision(p_bill_id uuid, p_action text) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare b bills%rowtype; a uuid; r user_role;
begin
  select role into r from profiles where id = auth.uid() and account_status = 'active';
  if r is null or r not in ('admin','cashier') then raise exception 'Only active Admin or Cashier accounts may use overdue collection'; end if;
  if p_action not in ('requested','approved','revoked') or p_action is null then raise exception 'Invalid decision'; end if;
  if p_action <> 'requested' and r <> 'admin' then raise exception 'Only the Admin can authorize or revoke collection'; end if;
  select * into b from bills where id = p_bill_id;
  if not found then raise exception 'Bill unavailable'; end if;
  -- Serialize all collection/approval decisions for this household.
  perform 1 from consumers where id = b.consumer_id for update;
  select * into b from bills where id = p_bill_id for update;
  select area_id into a from consumers where id = b.consumer_id;
  if a is distinct from app.current_area() then raise exception 'Bill unavailable in your area'; end if;
  if b.due_date is null or b.due_date >= fn_ph_today() or b.balance <= 0 then raise exception 'This bill has no overdue balance'; end if;
  -- Repeated requests do not revoke an existing approval or produce more alerts.
  if p_action = 'requested' and exists (select 1 from overdue_collection_approvals where bill_id = p_bill_id and state in ('requested','approved') and amount = b.balance) then return; end if;
  insert into overdue_collection_approvals(bill_id, consumer_id, area_id, amount, state, requested_by, approved_by)
    values (b.id,b.consumer_id,a,b.balance,p_action,auth.uid(),case when p_action = 'approved' then auth.uid() end)
  on conflict (bill_id) do update set amount = excluded.amount, state = excluded.state,
    approved_by = excluded.approved_by, updated_at = now(), transaction_id = null;
  insert into overdue_collection_audit(bill_id,actor_id,action,amount) values(b.id,auth.uid(),p_action,b.balance);
end $$;
revoke all on function public.fn_overdue_decision(uuid,text) from public, anon;
grant execute on function public.fn_overdue_decision(uuid,text) to authenticated;

-- Keep the proven allocation/receipt implementation private; only the guarded
-- entry point below can call it. No old APK or direct table write bypass.
alter function public.fn_record_payment(uuid[],numeric[],numeric,timestamptz,uuid) set schema app;
alter function app.fn_record_payment(uuid[],numeric[],numeric,timestamptz,uuid) rename to record_payment_core_v18;
revoke all on function app.record_payment_core_v18(uuid[],numeric[],numeric,timestamptz,uuid) from public, anon, authenticated;

create function public.fn_record_payment(
  p_bill_ids uuid[], p_amounts numeric[], p_cash_tendered numeric default null,
  p_paid_at timestamptz default now(), p_client_uuid uuid default null
) returns uuid language plpgsql security definer set search_path = public, pg_temp as $$
declare c uuid; a uuid; tx payment_transactions%rowtype; b bills%rowtype;
  v_id uuid; v_overdue boolean; i integer;
begin
  if not exists (select 1 from profiles where id = auth.uid() and role = 'cashier' and account_status = 'active') then
    raise exception 'Only an active Cashier may record cash';
  end if;
  if p_client_uuid is null then raise exception 'A payment reference is required. Update BillAlert before collecting.'; end if;
  if coalesce(cardinality(p_bill_ids),0) = 0 or cardinality(p_bill_ids) is distinct from cardinality(p_amounts)
     or array_position(p_bill_ids,null) is not null or array_position(p_amounts,null) is not null
     or (select count(distinct x) from unnest(p_bill_ids) x) <> cardinality(p_bill_ids) then raise exception 'Invalid payment allocation'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_client_uuid::text,0));
  select * into tx from payment_transactions where client_uuid = p_client_uuid;
  if found then
    if tx.cashier_id <> auth.uid() or tx.cash_tendered is distinct from p_cash_tendered
       or (select count(*) from payments where transaction_id = tx.id) <> cardinality(p_bill_ids) then raise exception 'Payment reference conflicts with another handover'; end if;
    for i in 1..cardinality(p_bill_ids) loop
      if not exists (select 1 from payments where transaction_id = tx.id and bill_id = p_bill_ids[i] and amount_paid = round(p_amounts[i],2)) then raise exception 'Payment reference conflicts with another allocation'; end if;
    end loop;
    return tx.id;
  end if;
  select consumer_id into c from bills where id = p_bill_ids[1];
  select area_id into a from consumers where id = c for update;
  if a is null or a is distinct from app.current_area() then raise exception 'Household unavailable in your area'; end if;
  perform 1 from bills where consumer_id = c order by id for update;
  select exists(select 1 from bills where consumer_id = c and due_date < fn_ph_today() and balance > 0) into v_overdue;
  for i in 1..cardinality(p_bill_ids) loop
    select * into b from bills where id = p_bill_ids[i];
    if not found or b.consumer_id <> c then raise exception 'Select bills for one household'; end if;
    if b.total_amount is null or b.balance <= 0 or p_amounts[i] <> b.balance then raise exception 'Balance changed. Refresh before collecting the full balance.'; end if;
    if v_overdue then
      if b.due_date >= fn_ph_today() then raise exception 'Settle all overdue bills with Admin authorization before paying a current bill'; end if;
      if not exists (select 1 from overdue_collection_approvals where bill_id = b.id and consumer_id = c and area_id = a and state = 'approved' and amount = b.balance) then
        raise exception 'Admin authorization is required for this overdue balance';
      end if;
    end if;
  end loop;
  -- Server time prevents an old device date from changing the collection day.
  v_id := app.record_payment_core_v18(p_bill_ids,p_amounts,p_cash_tendered,now(),p_client_uuid);
  update overdue_collection_approvals set state = 'consumed', transaction_id = v_id, updated_at = now()
    where bill_id = any(p_bill_ids) and state = 'approved';
  insert into overdue_collection_audit(bill_id,actor_id,action,amount)
    select bill_id,auth.uid(),'consumed',amount from overdue_collection_approvals where transaction_id = v_id;
  return v_id;
end $$;
revoke all on function public.fn_record_payment(uuid[],numeric[],numeric,timestamptz,uuid) from public, anon;
grant execute on function public.fn_record_payment(uuid[],numeric[],numeric,timestamptz,uuid) to authenticated;
revoke insert, update, delete on public.payments, public.payment_transactions from public, anon, authenticated;
revoke update on public.bills from public, anon, authenticated;

-- Post amounts atomically and replay only the same actor/input/reference.
create table app.post_amount_operations (
  client_uuid uuid primary key, actor_id uuid not null references public.profiles(id),
  bill_id uuid not null references public.bills(id), amount numeric(12,2) not null,
  due_date date not null, notification_id uuid
);
revoke all on app.post_amount_operations from public, anon, authenticated;
alter function public.fn_post_bill_amount(uuid,numeric,date,timestamptz) set schema app;
alter function app.fn_post_bill_amount(uuid,numeric,date,timestamptz) rename to post_amount_core_v18;
revoke all on function app.post_amount_core_v18(uuid,numeric,date,timestamptz) from public, anon, authenticated;
create function public.fn_post_bill_amount(p_bill_id uuid,p_amount numeric,p_due_date date,p_posted_at timestamptz default now(),p_client_uuid uuid default null)
returns uuid language plpgsql security definer set search_path = public, pg_temp as $$
declare prior app.post_amount_operations%rowtype; n uuid; c uuid;
begin
  if not exists(select 1 from profiles where id = auth.uid() and role = 'admin' and account_status = 'active') then raise exception 'Only an active Admin may post amounts'; end if;
  if p_client_uuid is not null then
    perform pg_advisory_xact_lock(hashtextextended(p_client_uuid::text,1));
    select * into prior from app.post_amount_operations where client_uuid = p_client_uuid;
    if found then
      if prior.actor_id <> auth.uid() or prior.bill_id <> p_bill_id or prior.amount is distinct from p_amount or prior.due_date is distinct from p_due_date then raise exception 'Posting reference conflicts with another amount'; end if;
      return prior.notification_id;
    end if;
  end if;
  select consumer_id into c from bills where id = p_bill_id;
  perform 1 from consumers where id = c and area_id = app.current_area() for update;
  if not found then raise exception 'Bill unavailable in your area'; end if;
  if p_due_date < fn_ph_today() then raise exception 'Choose a due date that has not passed'; end if;
  n := app.post_amount_core_v18(p_bill_id,p_amount,p_due_date,now());
  if p_client_uuid is not null then insert into app.post_amount_operations values(p_client_uuid,auth.uid(),p_bill_id,p_amount,p_due_date,n); end if;
  return n;
end $$;
revoke all on function public.fn_post_bill_amount(uuid,numeric,date,timestamptz,uuid) from public, anon;
grant execute on function public.fn_post_bill_amount(uuid,numeric,date,timestamptz,uuid) to authenticated;
-- Read-only preflight. Collection rechecks under locks, so this is not a token
-- that can be reused after another device changes a balance or approval.
create function public.fn_check_collection(p_bill_ids uuid[],p_amounts numeric[]) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare b bills%rowtype; c uuid; i integer;
begin
  if not exists(select 1 from profiles where id=auth.uid() and role='cashier' and account_status='active') then raise exception 'Only an active Cashier can collect'; end if;
  if coalesce(cardinality(p_bill_ids),0)=0 or cardinality(p_bill_ids) is distinct from cardinality(p_amounts) then raise exception 'Choose bills and amounts'; end if;
  for i in 1..cardinality(p_bill_ids) loop
    select * into b from bills where id=p_bill_ids[i];
    if not found or not exists(select 1 from consumers where id=b.consumer_id and area_id=app.current_area()) then raise exception 'Bill unavailable in your area'; end if;
    if c is not null and c <> b.consumer_id then raise exception 'Choose one household'; end if;
    c := b.consumer_id;
    if b.total_amount is null or b.balance <= 0 or p_amounts[i] is distinct from b.balance then raise exception 'Balance changed. Refresh before collecting.'; end if;
    if b.due_date < fn_ph_today() then
      if not exists(select 1 from overdue_collection_approvals where bill_id=b.id and state='approved' and amount=b.balance) then raise exception 'Admin authorization required'; end if;
    elsif exists(select 1 from bills where consumer_id=c and balance>0 and due_date<fn_ph_today()) then
      raise exception 'Settle every overdue balance with Admin authorization before current payment';
    end if;
  end loop;
end $$;
revoke all on function public.fn_check_collection(uuid[],numeric[]) from public, anon;
grant execute on function public.fn_check_collection(uuid[],numeric[]) to authenticated;

create view public.v_overdue_collection with (security_invoker=true) as
select v.*, a.state as approval_state, a.amount as approved_amount
from public.v_bill_status v left join public.overdue_collection_approvals a on a.bill_id=v.id
where v.is_overdue and v.balance>0 and app.current_role() in ('admin','cashier');
grant select on public.v_overdue_collection to authenticated;
commit;
