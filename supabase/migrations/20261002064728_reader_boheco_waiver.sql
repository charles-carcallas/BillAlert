begin;
-- Apply after 20261002064410_account_lifecycle.sql. Entirely noncash coverage.
alter type public.bill_status add value if not exists 'waived';
create table public.reader_waiver_assignments (
 id uuid primary key default gen_random_uuid(),
 reader_id uuid not null references public.profiles(id),
 consumer_id uuid not null references public.consumers(id),
 area_id uuid not null references public.areas(id),
 meter_serial_no text not null,
 start_month date not null check (extract(day from start_month)=1),
 assigned_by uuid not null references public.profiles(id),
 assigned_at timestamptz not null default clock_timestamp(),
 ended_at timestamptz, ended_by uuid references public.profiles(id), end_reason text,
 check ((ended_at is null and ended_by is null and end_reason is null)
     or (ended_at is not null and nullif(btrim(end_reason),'') is not null))
);
create unique index reader_waiver_one_reader on public.reader_waiver_assignments(reader_id) where ended_at is null;
create unique index reader_waiver_one_household on public.reader_waiver_assignments(consumer_id) where ended_at is null;
create index reader_waiver_area on public.reader_waiver_assignments(area_id);
create index reader_waiver_consumer_history on public.reader_waiver_assignments(consumer_id,assigned_at);
alter table public.reader_waiver_assignments enable row level security;
revoke all on public.reader_waiver_assignments from public,anon,authenticated;
grant select on public.reader_waiver_assignments to authenticated;
create policy reader_waiver_read on public.reader_waiver_assignments for select to authenticated using (
 (reader_id=(select auth.uid()) and exists(select 1 from profiles p where p.id=(select auth.uid()) and p.account_status='active')) or
 (area_id=(select app.current_area()) and (select app.current_role()) in ('admin','cashier'))
);

create function public.fn_assign_reader_waiver(p_reader_id uuid,p_consumer_id uuid,p_start_month date)
returns public.reader_waiver_assignments language plpgsql security definer set search_path=public,pg_temp as $$
declare r profiles%rowtype; c consumers%rowtype; w reader_waiver_assignments;
begin
 perform app.lock_own_area();
 if not exists(select 1 from profiles where id=auth.uid() and role='admin' and account_status='active' and staff_enabled) then
  raise exception 'Only an active Admin may assign coverage'; end if;
 if p_start_month is null or extract(day from p_start_month)<>1 or p_start_month<date_trunc('month',fn_ph_today())::date then
  raise exception 'Choose the first day of a current or future billing month'; end if;
 select * into r from profiles where id=p_reader_id for update;
 if not found or r.role<>'meter_reader' or r.account_status<>'active' or not r.staff_enabled or r.area_id is distinct from app.current_area() then
  raise exception 'Choose an active Meter Reader in your area'; end if;
 select * into c from consumers where id=p_consumer_id for update;
 if not found or c.profile_id is distinct from r.id or c.area_id is distinct from r.area_id or c.account_status<>'active' then
  raise exception 'Choose the active household linked to this Meter Reader in your area'; end if;
 if exists(select 1 from reader_waiver_assignments where ended_at is null and (reader_id=r.id or consumer_id=c.id)) then
  raise exception 'End the existing coverage before assigning another household'; end if;
 insert into reader_waiver_assignments(reader_id,consumer_id,area_id,meter_serial_no,start_month,assigned_by)
 values(r.id,c.id,c.area_id,c.meter_serial_no,p_start_month,auth.uid()) returning * into w;
 return w;
end $$;
create function public.fn_end_reader_waiver(p_assignment_id uuid,p_reason text)
returns public.reader_waiver_assignments language plpgsql security definer set search_path=public,pg_temp as $$
declare w reader_waiver_assignments;
begin
 perform app.lock_own_area();
 if not exists(select 1 from profiles where id=auth.uid() and role='admin' and account_status='active' and staff_enabled) then
  raise exception 'Only an active Admin may end coverage'; end if;
 if nullif(btrim(p_reason),'') is null then raise exception 'Give a reason for ending coverage'; end if;
 select * into w from reader_waiver_assignments where id=p_assignment_id and area_id=app.current_area();
 if not found then raise exception 'Coverage unavailable in your area'; end if;
 perform 1 from profiles where id=w.reader_id for update;
 perform 1 from consumers where id=w.consumer_id for update;
 update reader_waiver_assignments set ended_at=clock_timestamp(),ended_by=auth.uid(),end_reason=btrim(p_reason)
 where id=w.id and ended_at is null;
 select * into w from reader_waiver_assignments where id=w.id;
 return w;
end $$;
create function public.fn_reader_waiver_history(p_reader_id uuid)
returns setof public.reader_waiver_assignments language sql stable security invoker set search_path=public,pg_temp as $$
 select * from reader_waiver_assignments where reader_id=p_reader_id order by assigned_at desc,id;
$$;
revoke all on function public.fn_assign_reader_waiver(uuid,uuid,date),public.fn_end_reader_waiver(uuid,text),public.fn_reader_waiver_history(uuid) from public,anon;
grant execute on function public.fn_assign_reader_waiver(uuid,uuid,date),public.fn_end_reader_waiver(uuid,text),public.fn_reader_waiver_history(uuid) to authenticated;

create function app.end_invalid_reader_coverage() returns trigger
language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if tg_table_name='profiles' then
  if new.role is distinct from old.role or new.area_id is distinct from old.area_id or new.account_status<>'active' or not new.staff_enabled then
   update reader_waiver_assignments set ended_at=clock_timestamp(),ended_by=auth.uid(),end_reason='Reader eligibility changed'
    where reader_id=new.id and ended_at is null;
  end if;
 else
  if new.profile_id is distinct from old.profile_id or new.area_id is distinct from old.area_id
    or new.meter_serial_no is distinct from old.meter_serial_no or new.account_status<>'active' then
   update reader_waiver_assignments set ended_at=clock_timestamp(),ended_by=auth.uid(),end_reason='Household eligibility changed'
    where consumer_id=new.id and ended_at is null;
  end if;
 end if;
 return new;
end $$;
revoke all on function app.end_invalid_reader_coverage() from public,anon,authenticated;
create trigger end_reader_coverage after update of role,area_id,account_status,staff_enabled on public.profiles
 for each row execute function app.end_invalid_reader_coverage();
create trigger end_household_coverage after update of profile_id,area_id,meter_serial_no,account_status on public.consumers
 for each row execute function app.end_invalid_reader_coverage();

alter table public.bills add column waiver_amount numeric(12,2) not null default 0,
 add column waiver_assignment_id uuid references public.reader_waiver_assignments(id),add column waived_at timestamptz;
alter table public.bills add constraint bills_full_noncash_waiver check (
 (waiver_amount=0 and waiver_assignment_id is null and waived_at is null) or
 (waiver_amount>0 and total_amount is not null and waiver_amount=total_amount and amount_paid=0 and waiver_assignment_id is not null and waived_at is not null));
create index bills_waiver_assignment on public.bills(waiver_assignment_id) where waiver_assignment_id is not null;

-- Runs before the derived-fields trigger, only at the first pricing event.
create function app.apply_reader_coverage() returns trigger
language plpgsql security definer set search_path=public,pg_temp as $$
declare w reader_waiver_assignments; m date;
begin
 if tg_op='DELETE' then
  if old.waiver_amount>0 then raise exception 'Covered bills are immutable'; end if;
  return old;
 end if;
 if tg_op='UPDATE' and old.waiver_amount>0 then
  if new is distinct from old then raise exception 'Covered bills are immutable'; end if;
  return new;
 end if;
 if new.waiver_amount<>0 or new.waiver_assignment_id is not null or new.waived_at is not null then
  raise exception 'Coverage is assigned only by bill posting'; end if;
 if new.total_amount is null then return new; end if;
 if tg_op='UPDATE' and old.total_amount is not null then return new; end if;
 select make_date(cycle_year,cycle_month,1) into m from billing_cycles where id=new.billing_cycle_id;
 select a.* into w from reader_waiver_assignments a join profiles p on p.id=a.reader_id join consumers c on c.id=a.consumer_id
 where a.consumer_id=new.consumer_id and a.ended_at is null and m>=a.start_month
 and c.profile_id=p.id and c.area_id=a.area_id and c.meter_serial_no=a.meter_serial_no and c.account_status='active'
 and p.role='meter_reader' and p.account_status='active' and p.staff_enabled and p.area_id=a.area_id
 for update of a;
 if found then
  if new.amount_paid<>0 then raise exception 'A covered bill cannot have cash payments'; end if;
  new.waiver_amount:=new.total_amount; new.waiver_assignment_id:=w.id; new.waived_at:=clock_timestamp();
 end if;
 return new;
end $$;
revoke all on function app.apply_reader_coverage() from public,anon,authenticated;
create trigger bill_apply_reader_coverage before insert or update or delete on public.bills
 for each row execute function app.apply_reader_coverage();
create or replace function public.fn_bills_sync_derived() returns trigger language plpgsql as $$
begin
 if new.total_amount is null then new.balance:=null; new.status:='unpriced';
 elsif new.waiver_amount>0 then new.balance:=0; new.status:='waived';
 else
  new.balance:=new.total_amount-new.amount_paid;
  new.status:=case when new.amount_paid>=new.total_amount then 'paid'::bill_status
   when new.amount_paid>0 then 'partial'::bill_status else 'unpaid'::bill_status end;
 end if;
 return new;
end $$;

-- Maintain profile -> consumer -> assignment lock order before existing posting.
-- This makes a concurrent staff disable serialize with posting eligibility.
do $$ declare d text; begin
 d:=pg_get_functiondef('public.fn_post_bill_amount(uuid,numeric,date,timestamptz,uuid)'::regprocedure);
 d:=replace(d,'perform 1 from consumers where id = c and area_id = app.current_area() for update;',
 'perform 1 from profiles where id=(select profile_id from consumers where id=c) for update;
  perform 1 from consumers where id = c and area_id = app.current_area() for update;');
 if position('perform 1 from profiles where id=(select profile_id' in d)=0 then raise exception 'Posting lock integration requires review'; end if;
 execute d;
end $$;

-- Preserve every prior view column ordinal; append only. Do not expand b.*
-- after adding columns, which would shift the previously appended view columns.
do $$ declare d text; n text; begin
 d:=pg_get_viewdef('public.v_bill_status'::regclass,true);
 d:=regexp_replace(d,'(\s+FROM (public\.)?bills b)',E', b.waiver_amount, b.waiver_assignment_id, b.waived_at\\1');
 if position('b.waiver_assignment_id' in d)=0 then raise exception 'Bill view integration requires review'; end if;
 d:=regexp_replace(d,'\mb\.status <> ''paid''::bill_status','(b.status <> ''paid''::bill_status AND b.waiver_amount=0)','g');
 execute 'create or replace view public.v_bill_status with (security_invoker=true) as '||d;
 foreach n in array array['v_consumer_current_bill','v_consumer_outstanding','v_due_for_predue_reminder','v_due_for_overdue_notice'] loop
  d:=pg_get_viewdef(('public.'||n)::regclass,true);
  if n='v_consumer_outstanding' then d:=replace(d,'WHERE status <> ''paid''::bill_status','WHERE status <> ''paid''::bill_status AND waiver_amount=0'); end if;
  d:=replace(d,'vb.status <> ''paid''::bill_status','(vb.status <> ''paid''::bill_status AND vb.waiver_amount=0)');
  d:=regexp_replace(d,'\mb\.status <> ''paid''::bill_status','(b.status <> ''paid''::bill_status AND b.waiver_amount=0)','g');
  execute 'create or replace view public.'||quote_ident(n)||' with (security_invoker=true) as '||d;
 end loop;
 d:=pg_get_viewdef('public.v_cashier_collection_progress'::regclass,true);
 d:=replace(d,'b.consumer_id = c.id','b.consumer_id = c.id AND b.waiver_amount=0');
 execute 'create or replace view public.v_cashier_collection_progress with (security_invoker=true) as '||d;
 d:=pg_get_functiondef('public.fn_rounding_fund(uuid)'::regprocedure);
 d:=replace(d,'and b.total_amount is not null','and b.total_amount is not null and b.waiver_amount = 0');
 if position('b.waiver_amount = 0' in d)=0 then raise exception 'Rounding fund integration requires review'; end if;
 execute d;
end $$;

do $$ declare d text; begin
 d:=pg_get_functiondef('public.fn_record_remit_handover(date)'::regprocedure);
 d:=replace(d,'and account_status = ''active''','and account_status = ''active'' and staff_enabled');
 execute d;
end $$;

-- A covered notice item has verifiable noncash evidence, not a fake receipt.
do $$ declare d text; begin
 d:=pg_get_viewdef('public.v_notice_review_records'::regclass,true);
 d:=replace(d,'< b.total_amount','< (b.total_amount-b.waiver_amount)');
 execute 'create or replace view public.v_notice_review_records with (security_invoker=true) as '||d;
 d:=pg_get_functiondef('public.fn_notice_review(uuid)'::regprocedure);
 d:=replace(d,'''legacy'',i.legacy','''legacy'',i.legacy,''waiver_amount'',b.waiver_amount,''waiver_assignment_id'',b.waiver_assignment_id,''waived_at'',b.waived_at');
 execute d;
end $$;

-- Bill-ready notices must not demand payment for noncash coverage.
do $$ declare d text; begin
 d:=pg_get_functiondef('public.fn_render_bill_message(uuid)'::regprocedure);
 d:=replace(d,'msg := s.sms_template;',E'if r.waiver_amount>0 then\n return ''BOHECO coverage: '' || r.bill_no || '' ('' || r.cycle_label || ''). Full bill covered by BOHECO. No cash payment due for this bill.'';\n end if;\n msg := s.sms_template;');
 if position('Full bill covered by BOHECO' in d)=0 then raise exception 'Notification integration requires review'; end if;
 execute d;
end $$;
commit;





