-- REVIEW ONLY. Apply once after migrations 19 and 20; no live execution here.
begin;

create table public.notice_bill_items (
  notice_id uuid not null references public.disconnection_notices(id) on delete cascade,
  bill_id uuid not null references public.bills(id),
  amount_at_issue numeric(12,2),
  legacy boolean not null default false,
  primary key(notice_id,bill_id)
);
create index notice_bill_items_bill_idx on public.notice_bill_items(bill_id);
alter table public.notice_bill_items enable row level security;
revoke all on public.notice_bill_items from public,anon,authenticated;
grant select on public.notice_bill_items to authenticated;
create policy notice_bill_items_read on public.notice_bill_items for select to authenticated
using (exists(select 1 from public.disconnection_notices n join public.consumers c on c.id=n.consumer_id
  where n.id=notice_id and c.area_id=app.current_area() and app.current_role()='admin'));

-- Historical association is reconstructed; never invent an original balance.
insert into public.notice_bill_items(notice_id,bill_id,legacy)
select n.id,b.id,true from public.disconnection_notices n join public.bills b on b.consumer_id=n.consumer_id
where b.total_amount is not null and b.due_date < public.fn_ph_today(n.served_at)
  and b.generated_at <= n.created_at and b.priced_at <= n.created_at
  and (b.balance > 0 or exists(select 1 from public.payments p where p.bill_id=b.id and p.paid_at >= n.served_at));

create function app.capture_notice_bills() returns trigger language plpgsql security definer
set search_path=public,pg_temp as $$
begin
  insert into notice_bill_items(notice_id,bill_id,amount_at_issue)
  select new.id,b.id,b.balance from bills b where b.consumer_id=new.consumer_id
    and b.total_amount is not null and b.balance>0 and b.due_date<fn_ph_today(new.served_at);
  return new;
end $$;
revoke all on function app.capture_notice_bills() from public,anon,authenticated;
create trigger capture_notice_bills after insert on public.disconnection_notices
for each row execute function app.capture_notice_bills();

-- Ready means no overdue debt AND every covered bill has full receipt-backed
-- payment. A changed due date or direct accounting adjustment is not payment.
create view public.v_notice_review_records with (security_invoker=true) as
select n.id as notice_id,n.notice_no,n.consumer_id,c.consumer_no,
  c.first_name||' '||c.last_name as consumer_name,c.area_id,c.purok,c.meter_serial_no,
  n.reason,n.served_at,n.earliest_lawful_at,
  now()>=n.earliest_lawful_at as notice_period_elapsed,
  coalesce((select sum(b.balance) from bills b where b.consumer_id=c.id and b.total_amount is not null
    and b.balance>0 and b.due_date<fn_ph_today()),0) as amount_overdue,
  issuer.first_name||' '||issuer.last_name as issued_by_name,
  n.status,n.closed_at,n.outcome_notes,closer.first_name||' '||closer.last_name as closed_by_name,
  (n.status='active' and exists(select 1 from notice_bill_items i where i.notice_id=n.id)
   and not exists(select 1 from bills b where b.consumer_id=c.id and b.balance>0 and b.due_date<fn_ph_today())
   and not exists(select 1 from notice_bill_items i join bills b on b.id=i.bill_id where i.notice_id=n.id
     and (b.balance>0 or coalesce((select sum(p.amount_paid) from payments p where p.bill_id=b.id),0)<b.total_amount))) as ready_to_close
from disconnection_notices n join consumers c on c.id=n.consumer_id
left join profiles issuer on issuer.id=n.issued_by left join profiles closer on closer.id=n.closed_by
where app.current_role()='admin' and c.area_id=app.current_area();
revoke all on public.v_notice_review_records from public,anon,authenticated;
grant select on public.v_notice_review_records to authenticated;
create view public.v_disconnection_history with (security_invoker=true) as
select * from public.v_notice_review_records where status<>'active';
revoke all on public.v_disconnection_history from public,anon,authenticated;
grant select on public.v_disconnection_history to authenticated;

-- Append a readiness flag without changing existing Consumer/Meter Reader columns.
create or replace view public.v_active_disconnection_warnings with (security_invoker=true) as
select n.id as notice_id,n.notice_no,n.consumer_id,c.consumer_no,
 c.first_name||' '||c.last_name as consumer_name,c.area_id,n.reason,n.served_at,n.earliest_lawful_at,
 n.served_at at time zone 'Asia/Manila' as served_at_ph,
 n.earliest_lawful_at at time zone 'Asia/Manila' as earliest_lawful_at_ph,
 now()>=n.earliest_lawful_at as notice_period_elapsed,
 coalesce((select sum(b.balance) from bills b where b.consumer_id=n.consumer_id and b.total_amount is not null
   and b.status<>'paid' and b.due_date<fn_ph_today()),0) as amount_overdue,
 c.purok,c.meter_serial_no,n.issued_by,p.first_name||' '||p.last_name as issued_by_name,
 coalesce((select r.ready_to_close from v_notice_review_records r where r.notice_id=n.id),false) as ready_to_close
from disconnection_notices n join consumers c on c.id=n.consumer_id
left join profiles p on p.id=n.issued_by where n.status='active';

create function public.fn_notice_review(p_notice_id uuid) returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
declare r v_notice_review_records%rowtype; result jsonb;
begin
  if not exists(select 1 from profiles where id=auth.uid() and role='admin' and account_status='active') then
    raise exception 'Only an active Admin can review notice outcomes'; end if;
  select * into r from v_notice_review_records where notice_id=p_notice_id;
  if not found then return null; end if;
  result := to_jsonb(r)||jsonb_build_object('checked_at',now(),
    'covered_bills',coalesce((select jsonb_agg(jsonb_build_object('bill_no',b.bill_no,'cycle_label',to_char(bc.period_start,'FMMonth YYYY'),
      'due_date',b.due_date,'balance',b.balance,'amount_at_issue',i.amount_at_issue,'legacy',i.legacy) order by bc.period_start)
      from notice_bill_items i join bills b on b.id=i.bill_id join billing_cycles bc on bc.id=b.billing_cycle_id where i.notice_id=p_notice_id),'[]'::jsonb),
    'overdue_bills',coalesce((select jsonb_agg(jsonb_build_object('bill_no',b.bill_no,'cycle_label',to_char(bc.period_start,'FMMonth YYYY'),
      'due_date',b.due_date,'balance',b.balance) order by bc.period_start) from bills b join billing_cycles bc on bc.id=b.billing_cycle_id
      where b.consumer_id=r.consumer_id and b.balance>0 and b.due_date<fn_ph_today()),'[]'::jsonb),
    'receipts',coalesce((select jsonb_agg(jsonb_build_object('receipt_no',t.receipt_no,'bill_no',b.bill_no,'amount_paid',p.amount_paid,'paid_at',p.paid_at) order by p.paid_at desc)
      from payments p join payment_transactions t on t.id=p.transaction_id join bills b on b.id=p.bill_id
      join notice_bill_items i on i.bill_id=p.bill_id where i.notice_id=p_notice_id),'[]'::jsonb),
    'sms',coalesce((select jsonb_agg(jsonb_build_object('status',n.status,'dispatch_state',n.dispatch_state,'sent_at',n.sent_at) order by n.created_at desc)
      from notifications n where n.disconnection_id=p_notice_id and n.channel='sms'),'[]'::jsonb));
  return result;
end $$;
revoke all on function public.fn_notice_review(uuid) from public,anon;
grant execute on function public.fn_notice_review(uuid) to authenticated;

create or replace function public.fn_close_disconnection_notice(p_notice_id uuid,p_outcome notice_status,p_notes text default null)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare n disconnection_notices%rowtype; c uuid; clean text:=nullif(trim(p_notes),'');
begin
  if not exists(select 1 from profiles where id=auth.uid() and role='admin' and account_status='active') then
    raise exception 'Only an active Admin can close notices'; end if;
  if p_outcome is null or p_outcome not in ('settled','cancelled','referred') then raise exception 'Choose a valid notice outcome'; end if;
  select consumer_id into c from disconnection_notices where id=p_notice_id;
  perform 1 from consumers where id=c and area_id=app.current_area() for update;
  if not found then raise exception 'Notice unavailable in your area'; end if;
  -- Same order as payment collection: household, bills, then notice.
  perform 1 from bills where consumer_id=c order by id for update;
  select * into n from disconnection_notices where id=p_notice_id for update;
  if n.status<>'active' then
    if n.status=p_outcome and n.closed_by=auth.uid() and n.outcome_notes is not distinct from clean then return; end if;
    raise exception 'Notice already closed. Refresh to review its recorded outcome';
  end if;
  if p_outcome in ('cancelled','referred') and clean is null then raise exception 'Enter a cancellation reason or referral details'; end if;
  if p_outcome='settled' and not exists(select 1 from v_notice_review_records where notice_id=p_notice_id and ready_to_close) then
    raise exception 'Payment is not confirmed. Settle all overdue balances and verify receipts before marking Settled'; end if;
  update disconnection_notices set status=p_outcome,closed_at=now(),closed_by=auth.uid(),outcome_notes=clean where id=p_notice_id;
end $$;
revoke all on function public.fn_close_disconnection_notice(uuid,notice_status,text) from public,anon;
grant execute on function public.fn_close_disconnection_notice(uuid,notice_status,text) to authenticated;
revoke update,delete on public.disconnection_notices from public,anon,authenticated;

-- Alert only after actual payment completes the notice's receipt-backed debt.
create function app.notice_payment_ready_alert() returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
declare n record; a uuid;
begin
  if new.balance=0 and old.balance>0 then
    select area_id into a from consumers where id=new.consumer_id;
    for n in select dn.id from disconnection_notices dn where dn.consumer_id=new.consumer_id and dn.status='active'
      and exists(select 1 from notice_bill_items i where i.notice_id=dn.id)
      and not exists(select 1 from bills b where b.consumer_id=new.consumer_id and b.balance>0 and b.due_date<fn_ph_today())
      and not exists(select 1 from notice_bill_items i join bills b on b.id=i.bill_id where i.notice_id=dn.id
        and (b.balance>0 or coalesce((select sum(p.amount_paid) from payments p where p.bill_id=b.id),0)<b.total_amount))
    loop
      perform app.queue_staff_alert(a,'admin','notice-paid:'||n.id,'Notice payment confirmed',
        'Review the receipts and close the settled notice.','/admin/disconnections');
    end loop;
  end if;
  return new;
end $$;
revoke all on function app.notice_payment_ready_alert() from public,anon,authenticated;
create trigger notice_payment_ready_alert after update of amount_paid on public.bills
for each row execute function app.notice_payment_ready_alert();
commit;
