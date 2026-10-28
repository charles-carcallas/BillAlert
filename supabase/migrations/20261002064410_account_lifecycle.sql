-- REVIEW REQUIRED. Apply after 20261002034514_disconnection_review.sql.
-- Preserves identities and all financial history. No fifth role.
begin;
alter table public.profiles add column staff_enabled boolean not null default true;
alter table public.profiles add column access_version bigint not null default 0;
-- Retain the registration area when a family changes its login holder later.
-- This does not give a Consumer any staff permission.
update public.profiles p set area_id=c.area_id from public.consumers c
where c.profile_id=p.id and p.role='consumer' and p.area_id is null;
alter table public.consumers add column opening_reading numeric(12,2) not null default 0 check(opening_reading>=0);
drop index public.uq_area_one_active_staff_per_role;
create unique index uq_area_one_active_staff_per_role on public.profiles(area_id,role)
where account_status='active' and staff_enabled and role in ('admin','meter_reader','cashier');
alter table app.post_amount_operations enable row level security;
alter table app.staff_alert_deliveries enable row level security;

create function app.active_staff(p_id uuid, p_role public.user_role default null) returns boolean
language sql stable security definer set search_path=public,pg_temp as $$
 select exists(select 1 from profiles where id=p_id and account_status='active' and staff_enabled
   and role in ('admin','meter_reader','cashier') and (p_role is null or role=p_role))
$$;
revoke all on function app.active_staff(uuid,public.user_role) from public,anon;
grant execute on function app.active_staff(uuid,public.user_role) to authenticated,service_role;
create or replace function app.current_role() returns public.user_role
language sql stable security definer set search_path=public,pg_temp as $$
 select case when role<>'consumer' and not staff_enabled then 'consumer'::user_role else role end
 from profiles where id=app.current_user_id() and account_status='active'
$$;
create or replace function app.current_area() returns uuid
language sql stable security definer set search_path=public,pg_temp as $$
 select area_id from profiles where id=app.current_user_id() and account_status='active' and staff_enabled and role<>'consumer'
$$;
create or replace function app.current_consumer_id() returns uuid
language sql stable security definer set search_path=public,pg_temp as $$
 select c.id from consumers c join profiles p on p.id=c.profile_id where p.id=app.current_user_id() and p.account_status='active'
$$;


-- Assignment changes and financial writes serialize per area before rechecking
-- the caller, so an in-flight upload cannot pass an old role check then write
-- after a completed handover. All follow area -> household -> bills ordering.
create function app.lock_own_area() returns void language plpgsql security definer set search_path=public,pg_temp as $$
begin
 perform 1 from areas where id=(select area_id from profiles where id=auth.uid()) for update;
end $$;
revoke all on function app.lock_own_area() from public,anon;
grant execute on function app.lock_own_area() to authenticated;

-- Field grants prevent role/status/membership escalation through direct requests.
drop policy if exists profiles_admin_write on public.profiles;
drop policy if exists profiles_update_self on public.profiles;
create policy profiles_update_self on public.profiles for update to authenticated
 using(id=auth.uid() and account_status='active') with check(id=auth.uid() and account_status='active');
revoke insert,update,delete on public.profiles from public,anon,authenticated;
grant update(theme_preference,must_change_password) on public.profiles to authenticated;
revoke update,delete,insert on public.consumers from public,anon,authenticated;
grant insert(consumer_no,first_name,last_name,contact_number,area_id,purok,meter_serial_no,created_by) on public.consumers to authenticated;
drop policy if exists consumers_admin_insert on public.consumers;
create policy consumers_admin_insert on public.consumers for insert to authenticated
 with check(app.is_admin() and area_id=app.current_area() and created_by=auth.uid() and profile_id is null);
drop policy if exists consumers_select_scoped on public.consumers;
create policy consumers_select_scoped on public.consumers for select to authenticated
 using(app.staff_in_area(area_id) or id=app.current_consumer_id());

create table public.account_events(
 id bigint generated always as identity primary key,
 area_id uuid not null references public.areas(id), actor_id uuid references public.profiles(id),
 target_id uuid references public.profiles(id), action text not null, reason text not null,
 details jsonb not null default '{}', created_at timestamptz not null default now()
);
create index account_events_area_time on public.account_events(area_id,created_at desc);
alter table public.account_events enable row level security;
revoke all on public.account_events from public,anon,authenticated;
grant select on public.account_events to authenticated;
create policy account_events_read on public.account_events for select to authenticated
 using(app.is_admin() and area_id=app.current_area());
create table public.president_transfers(
 id uuid primary key default gen_random_uuid(), area_id uuid not null references public.areas(id),
 outgoing_id uuid not null references public.profiles(id), successor_id uuid not null references public.profiles(id),
 status text not null default 'pending' check(status in ('pending','accepted','completed','cancelled')),
 reason text not null, created_at timestamptz not null default now(), accepted_at timestamptz, completed_at timestamptz,
 check(outgoing_id<>successor_id)
);
create unique index one_pending_president_transfer on public.president_transfers(area_id) where status in ('pending','accepted');
create index president_transfer_successor on public.president_transfers(successor_id);
alter table public.president_transfers enable row level security;
revoke all on public.president_transfers from public,anon,authenticated;
grant select on public.president_transfers to authenticated;
create policy president_transfer_read on public.president_transfers for select to authenticated
 using(exists(select 1 from public.profiles where id=auth.uid() and account_status='active')
   and (outgoing_id=auth.uid() or successor_id=auth.uid()));

create function app.profile_access_changed() returns trigger language plpgsql set search_path=public,pg_temp as $$
begin
 if (new.role,new.area_id,new.account_status,new.staff_enabled) is distinct from
    (old.role,old.area_id,old.account_status,old.staff_enabled) then
   new.access_version:=old.access_version+1;
 end if; return new;
end $$;
create trigger profile_access_changed before update on public.profiles for each row execute function app.profile_access_changed();
create function app.household_access_changed() returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if new.profile_id is distinct from old.profile_id then
   update profiles set access_version=access_version+1 where id=old.profile_id or id=new.profile_id;
 end if; return new;
end $$;
create trigger household_access_changed after update of profile_id on public.consumers for each row execute function app.household_access_changed();
revoke all on function app.profile_access_changed(),app.household_access_changed() from public,anon,authenticated;

create function public.fn_manage_account(p_target uuid,p_action text,p_reason text,p_reconciled boolean default false)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare p profiles%rowtype; a uuid:=app.current_area();
begin
  perform app.lock_own_area();
 if not app.active_staff(auth.uid(),'admin') then raise exception 'Only the active Area President can manage accounts'; end if;
 perform 1 from areas where id=a for update;
 select * into p from profiles where id=p_target for update;
 if not found or p.id=auth.uid() or p.role='admin' then raise exception 'Use Area President transfer for this account'; end if;
 if not (p.area_id=a or exists(select 1 from consumers where profile_id=p.id and area_id=a)) then raise exception 'Account unavailable in your area'; end if;
 if nullif(trim(p_reason),'') is null then raise exception 'Enter the reason for this change'; end if;
 if p_action='end_work' then
   if p.role='consumer' then raise exception 'This account has no work assignment'; end if;
   if not coalesce(p_reconciled,false) then raise exception 'Review pending uploads and cash handovers before ending the assignment'; end if;
   if p.staff_enabled then
     update profiles set staff_enabled=false where id=p.id;
   else return; end if;
 elsif p_action='restore_work' then
   if p.role='consumer' or p.account_status<>'active' then raise exception 'Only an active staff login can resume work'; end if;
   if exists(select 1 from profiles where area_id=a and role=p.role and staff_enabled and account_status='active' and id<>p.id) then raise exception 'This area already has an active person in that position'; end if;
   update profiles set staff_enabled=true where id=p.id;
 elsif p_action='disable_login' then
   if p.account_status='inactive' then return; end if;
   update profiles set account_status='inactive',staff_enabled=false where id=p.id;
 elsif p_action='enable_login' then
   if p.account_status='active' then return; end if;
   -- Re-enabling login deliberately does not restore staff powers.
   update profiles set account_status='active',staff_enabled=false where id=p.id;
 else raise exception 'Unknown account action'; end if;
 insert into account_events(area_id,actor_id,target_id,action,reason,details)
 values(a,auth.uid(),p.id,p_action,trim(p_reason),jsonb_build_object('reconciled',p_reconciled));
end $$;

create function public.fn_link_household(p_consumer uuid,p_profile uuid,p_kind text,p_reference text)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare c consumers%rowtype; p profiles%rowtype; a uuid:=app.current_area(); old_id uuid;
begin
  perform app.lock_own_area();
 if not app.active_staff(auth.uid(),'admin') then raise exception 'Only the active Area President can link a household'; end if;
 perform 1 from areas where id=a for update;
 select * into c from consumers where id=p_consumer and area_id=a for update;
 if not found or c.account_status<>'active' then raise exception 'Choose an active household in your area'; end if;
 select * into p from profiles where id=p_profile for update;
 if not found or p.account_status<>'active' or p.area_id is distinct from a then raise exception 'Choose an active account registered in this area'; end if;
 if nullif(trim(p_reference),'') is null then raise exception 'Record the household verification reference'; end if;
 if p_kind is null or p_kind not in ('staff_link','same_household') then raise exception 'Unrelated occupants require a reviewed new household handover'; end if;
 if p_kind='staff_link' and p.role='consumer' then raise exception 'Choose a staff account'; end if;
 if c.profile_id is not null and c.profile_id<>p.id and p_kind<>'same_household' then raise exception 'Review the existing household login before replacing it'; end if;
 if exists(select 1 from consumers where profile_id=p.id and id<>c.id) then raise exception 'This account is already linked to another household'; end if;
 if c.profile_id=p.id then return; end if;
 old_id:=c.profile_id;
 update consumers set profile_id=p.id where id=c.id;
 insert into account_events(area_id,actor_id,target_id,action,reason,details)
 values(a,auth.uid(),p.id,p_kind,trim(p_reference),jsonb_build_object('consumer_id',c.id,'previous_profile_id',old_id));
end $$;

create function public.fn_household_handover(p_old_consumer uuid,p_new_consumer_no text,p_first_name text,p_last_name text,
 p_profile uuid,p_reference text,p_opening_reading numeric) returns uuid
language plpgsql security definer set search_path=public,pg_temp as $$
declare c consumers%rowtype; p profiles%rowtype; a uuid:=app.current_area(); n uuid; prior numeric;
begin
  perform app.lock_own_area();
 if not app.active_staff(auth.uid(),'admin') then raise exception 'Only the active Area President can review an occupant handover'; end if;
 perform 1 from areas where id=a for update;
 select * into c from consumers where id=p_old_consumer and area_id=a for update;
 if not found or c.account_status<>'active' then raise exception 'Choose an active household in your area'; end if;
 select * into p from profiles where id=p_profile for update;
 if not found or p.account_status<>'active' or p.area_id is distinct from a then raise exception 'Choose an active replacement login in this area'; end if;
 if exists(select 1 from consumers where profile_id=p.id) then raise exception 'Replacement already has a household'; end if;
 if nullif(trim(p_reference),'') is null or nullif(trim(p_new_consumer_no),'') is null
  or nullif(trim(p_first_name),'') is null or nullif(trim(p_last_name),'') is null then raise exception 'Complete the new household and verification details'; end if;
 select current_reading into prior from meter_readings where consumer_id=c.id order by reading_date desc,captured_at desc limit 1;
 if p_opening_reading is null or p_opening_reading<>coalesce(prior,c.opening_reading) then raise exception 'Record the closing reading and post its bill first; the opening reading must match it'; end if;
 if exists(select 1 from bills where consumer_id=c.id and total_amount is null) then raise exception 'Post the outstanding reading amounts before handover'; end if;
 -- Keep the outgoing household and debt; the new occupant cannot see its ledger.
 update consumers set account_status='inactive',meter_serial_no=null where id=c.id;
 insert into consumers(consumer_no,profile_id,first_name,last_name,meter_serial_no,area_id,purok,created_by,opening_reading)
 values(trim(p_new_consumer_no),p.id,trim(p_first_name),trim(p_last_name),c.meter_serial_no,a,c.purok,auth.uid(),p_opening_reading) returning id into n;
 update profiles set access_version=access_version+1 where id=p.id;
 insert into account_events(area_id,actor_id,target_id,action,reason,details)
 values(a,auth.uid(),p.id,'unrelated_household_handover',trim(p_reference),
 jsonb_build_object('old_consumer_id',c.id,'new_consumer_id',n,'meter_serial_no',c.meter_serial_no,'opening_reading',p_opening_reading));
 return n;
end $$;

create function public.fn_prepare_consumer_identity(p_actor uuid,p_user uuid,p_username text,p_first_name text,p_last_name text,p_reason text)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare a uuid;
begin
  perform 1 from areas where id=(select area_id from profiles where id=p_actor) for update;
 if not app.active_staff(p_actor,'admin') then raise exception 'Only the active Area President can create accounts'; end if;
 select area_id into a from profiles where id=p_actor;
 if p_username !~ '^[a-z][a-z0-9._-]{2,49}$' or nullif(trim(p_first_name),'') is null or nullif(trim(p_last_name),'') is null or nullif(trim(p_reason),'') is null then raise exception 'Complete the account details and reason'; end if;
 insert into profiles(id,user_code,username,first_name,last_name,role,area_id,account_status,must_change_password,staff_enabled)
 values(p_user,'CON-'||p_user::text,p_username,trim(p_first_name),trim(p_last_name),'consumer',a,'active',true,false);
 insert into account_events(area_id,actor_id,target_id,action,reason) values(a,p_actor,p_user,'consumer_login_created',trim(p_reason));
 return p_user;
end $$;

create function public.fn_prepare_president_transfer(p_actor uuid,p_successor uuid,p_username text,p_first_name text,p_last_name text,p_reason text)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare a uuid; n uuid;
begin
  perform 1 from areas where id=(select area_id from profiles where id=p_actor) for update;
 if not app.active_staff(p_actor,'admin') then raise exception 'Only the active Area President may start a transfer'; end if;
 select area_id into a from profiles where id=p_actor;
 perform 1 from areas where id=a for update;
 if p_username !~ '^[a-z][a-z0-9._-]{2,49}$' or nullif(trim(p_first_name),'') is null or nullif(trim(p_last_name),'') is null or nullif(trim(p_reason),'') is null then raise exception 'Complete the successor details and handover reason'; end if;
 insert into profiles(id,user_code,username,first_name,last_name,role,area_id,account_status,must_change_password,staff_enabled)
 values(p_successor,'ADM-'||p_successor::text,p_username,trim(p_first_name),trim(p_last_name),'admin',a,'active',true,false);
 insert into president_transfers(area_id,outgoing_id,successor_id,reason) values(a,p_actor,p_successor,trim(p_reason)) returning id into n;
 insert into account_events(area_id,actor_id,target_id,action,reason,details)
 values(a,p_actor,p_successor,'president_transfer_prepared',trim(p_reason),jsonb_build_object('transfer_id',n));
 return n;
end $$;

create function public.fn_my_president_transfers() returns jsonb language sql stable security definer set search_path=public,pg_temp as $$
 select coalesce(jsonb_agg(to_jsonb(t) || jsonb_build_object(
   'outgoing_name',concat_ws(' ',o.first_name,o.last_name),
   'successor_name',concat_ws(' ',s.first_name,s.last_name),
   'area_name',a.name) order by t.created_at desc),'[]')
 from president_transfers t
 join profiles o on o.id=t.outgoing_id
 join profiles s on s.id=t.successor_id
 join areas a on a.id=t.area_id
 where (t.outgoing_id=auth.uid() or t.successor_id=auth.uid()) and exists(select 1 from profiles where id=auth.uid() and account_status='active')
$$;
create function public.fn_accept_president_transfer(p_transfer uuid) returns void
language plpgsql security definer set search_path=public,pg_temp as $$
declare t president_transfers%rowtype;
begin
 select * into t from president_transfers where id=p_transfer for update;
 if not found or t.successor_id<>auth.uid() then raise exception 'This transfer is not addressed to you'; end if;
 if not exists(select 1 from profiles where id=auth.uid() and account_status='active' and not must_change_password and not staff_enabled and role='admin' and area_id=t.area_id) then raise exception 'Sign in and change your temporary password first'; end if;
 if t.status='accepted' then return; end if;
 if t.status<>'pending' then raise exception 'This transfer is no longer pending'; end if;
 update president_transfers set status='accepted',accepted_at=now() where id=t.id;
 insert into account_events(area_id,actor_id,target_id,action,reason,details) values(t.area_id,auth.uid(),auth.uid(),'president_transfer_accepted',t.reason,jsonb_build_object('transfer_id',t.id));
end $$;
create function public.fn_complete_president_transfer(p_transfer uuid,p_reconciled boolean default false) returns void
language plpgsql security definer set search_path=public,pg_temp as $$
declare t president_transfers%rowtype; a uuid:=app.current_area();
begin
  perform app.lock_own_area();
 if not app.active_staff(auth.uid(),'admin') then raise exception 'Only the outgoing active Area President can complete a transfer'; end if;
 perform 1 from areas where id=a for update;
 select * into t from president_transfers where id=p_transfer and area_id=a for update;
 if not found or t.outgoing_id<>auth.uid() or t.status<>'accepted' then raise exception 'The successor must accept this transfer first'; end if;
 if not coalesce(p_reconciled,false) then raise exception 'Reconcile pending uploads, approvals, notices and handovers first'; end if;
 perform 1 from profiles where id in (t.outgoing_id,t.successor_id) order by id for update;
 if not exists(select 1 from profiles where id=t.successor_id and account_status='active' and not staff_enabled and not must_change_password and role='admin' and area_id=a) then raise exception 'Successor is not ready'; end if;
 update profiles set staff_enabled=false where id=t.outgoing_id;
 update profiles set staff_enabled=true where id=t.successor_id;
 update president_transfers set status='completed',completed_at=now() where id=t.id;
 insert into account_events(area_id,actor_id,target_id,action,reason,details)
 values(a,auth.uid(),t.successor_id,'president_transfer_completed',t.reason,jsonb_build_object('transfer_id',t.id,'previous_president',t.outgoing_id));
end $$;
create function public.fn_cancel_president_transfer(p_transfer uuid) returns void
language plpgsql security definer set search_path=public,pg_temp as $$
declare t president_transfers%rowtype;
begin
  perform app.lock_own_area();
 if not app.active_staff(auth.uid(),'admin') then raise exception 'Only the outgoing Area President can cancel this transfer'; end if;
 select * into t from president_transfers where id=p_transfer and outgoing_id=auth.uid() for update;
 if not found or t.status not in ('pending','accepted') then raise exception 'Transfer is not pending'; end if;
 update president_transfers set status='cancelled' where id=t.id;
 insert into account_events(area_id,actor_id,target_id,action,reason,details)
 values(t.area_id,auth.uid(),t.successor_id,'president_transfer_cancelled',t.reason,jsonb_build_object('transfer_id',t.id));
end $$;

-- Maintainer-only recovery. The app receives no permission to invoke it.
create function public.fn_prepare_president_recovery(p_area uuid,p_successor uuid,p_username text,p_first_name text,p_last_name text,p_reference text)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if nullif(trim(p_reference),'') is null or p_username !~ '^[a-z][a-z0-9._-]{2,49}$'
   or nullif(trim(p_first_name),'') is null or nullif(trim(p_last_name),'') is null then raise exception 'Complete the independently verified successor details'; end if;
 perform 1 from areas where id=p_area for update;
 if not found then raise exception 'Unknown service area'; end if;
 insert into profiles(id,user_code,username,first_name,last_name,role,area_id,account_status,must_change_password,staff_enabled)
 values(p_successor,'ADM-'||p_successor::text,p_username,trim(p_first_name),trim(p_last_name),'admin',p_area,'active',true,false);
 insert into account_events(area_id,target_id,action,reason) values(p_area,p_successor,'maintainer_successor_prepared',trim(p_reference));
 return p_successor;
end $$;
create function public.fn_recover_president(p_area uuid,p_successor uuid,p_reference text) returns void
language plpgsql security definer set search_path=public,pg_temp as $$
declare prior uuid;
begin
 if nullif(trim(p_reference),'') is null then raise exception 'Record the independently verified appointment reference'; end if;
 perform 1 from areas where id=p_area for update;
 perform 1 from profiles where area_id=p_area and role='admin' order by id for update;
 if not exists(select 1 from profiles where id=p_successor and area_id=p_area and role='admin' and account_status='active' and not must_change_password) then raise exception 'Prepare and verify the separate successor account first'; end if;
 select id into prior from profiles where area_id=p_area and role='admin' and staff_enabled and account_status='active';
 update profiles set staff_enabled=false where area_id=p_area and role='admin' and id<>p_successor and staff_enabled;
 update profiles set staff_enabled=true where id=p_successor;
 update president_transfers set status='cancelled' where area_id=p_area and status in ('pending','accepted');
 insert into account_events(area_id,target_id,action,reason,details) values(p_area,p_successor,'maintainer_president_recovery',trim(p_reference),jsonb_build_object('previous_president',prior));
end $$;

create function public.fn_account_workspace() returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare a uuid:=app.current_area();
begin
 if not app.active_staff(auth.uid(),'admin') then raise exception 'Only the active Area President can manage accounts'; end if;
 return jsonb_build_object(
 'people',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'username',p.username,'first_name',p.first_name,'last_name',p.last_name,'role',p.role,'staff_enabled',p.staff_enabled,'account_status',p.account_status) order by p.first_name,p.last_name) from profiles p where p.area_id=a or exists(select 1 from consumers c where c.profile_id=p.id and c.area_id=a)),'[]'),
 'households',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'consumer_no',c.consumer_no,'first_name',c.first_name,'last_name',c.last_name,'profile_id',c.profile_id,'meter_serial_no',c.meter_serial_no,'account_status',c.account_status) order by c.consumer_no) from consumers c where c.area_id=a),'[]'),
 'transfers',coalesce((select jsonb_agg(to_jsonb(t) order by t.created_at desc) from president_transfers t where t.area_id=a),'[]'),
 'audit',coalesce((select jsonb_agg(to_jsonb(e) order by e.created_at desc) from (select id,actor_id,target_id,action,reason,details,created_at from account_events where area_id=a order by created_at desc limit 200) e),'[]'));
end $$;

revoke all on function public.fn_manage_account(uuid,text,text,boolean),public.fn_link_household(uuid,uuid,text,text),
 public.fn_household_handover(uuid,text,text,text,uuid,text,numeric),public.fn_my_president_transfers(),
 public.fn_accept_president_transfer(uuid),public.fn_complete_president_transfer(uuid,boolean),
 public.fn_cancel_president_transfer(uuid),public.fn_account_workspace() from public,anon;
grant execute on function public.fn_manage_account(uuid,text,text,boolean),public.fn_link_household(uuid,uuid,text,text),
 public.fn_household_handover(uuid,text,text,text,uuid,text,numeric),public.fn_my_president_transfers(),
 public.fn_accept_president_transfer(uuid),public.fn_complete_president_transfer(uuid,boolean),
 public.fn_cancel_president_transfer(uuid),public.fn_account_workspace() to authenticated;
revoke all on function public.fn_prepare_president_transfer(uuid,uuid,text,text,text,text),
 public.fn_prepare_consumer_identity(uuid,uuid,text,text,text,text),public.fn_recover_president(uuid,uuid,text),
 public.fn_prepare_president_recovery(uuid,uuid,text,text,text,text) from public,anon,authenticated;
grant execute on function public.fn_prepare_president_transfer(uuid,uuid,text,text,text,text),
 public.fn_prepare_consumer_identity(uuid,uuid,text,text,text,text),public.fn_recover_president(uuid,uuid,text),
 public.fn_prepare_president_recovery(uuid,uuid,text,text,text,text) to service_role;

-- Update existing guarded RPCs to respect ended assignments as well as login status.
create or replace function fn_create_staff_profile(
  p_admin_id      uuid,
  p_user_id       uuid,
  p_username      text,
  p_first_name    text,
  p_last_name     text,
  p_role          user_role,
  p_contact_number text default null
) returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_area          uuid;
  v_username      text := lower(trim(p_username));
  v_prefix        text;
  v_seq           integer;
  v_code          text;
  v_role_label    text;
  v_existing_name text;
begin
  perform 1 from areas where id=(select area_id from profiles where id=p_admin_id) for update;
  -- The Edge Function gets this id from the verified user JWT. Looking the
  -- profile up again here makes the database enforce the same boundary.
  select area_id
    into v_area
    from profiles
   where id = p_admin_id
     and role = 'admin'
     and account_status = 'active' and staff_enabled;

  if v_area is null then
    raise exception 'Only an active Area President can create a staff account';
  end if;

  if p_role is null
     or p_role not in ('meter_reader'::user_role, 'cashier'::user_role) then
    raise exception 'A staff account must be a Meter Reader or Cashier';
  end if;

  if v_username !~ '^[a-z][a-z0-9._-]{2,49}$' then
    raise exception
      'A username is 3 to 50 characters, starts with a letter, and holds '
      'only letters, numbers, dot, underscore or hyphen';
  end if;

  if nullif(trim(coalesce(p_first_name, '')), '') is null then
    raise exception 'Enter the staff member''s first name';
  end if;

  if nullif(trim(coalesce(p_last_name, '')), '') is null then
    raise exception 'Enter the staff member''s last name';
  end if;

  if exists (select 1 from profiles where username = v_username) then
    raise exception 'Username % is already taken', v_username;
  end if;

  v_role_label := case p_role
                    when 'meter_reader'::user_role then 'Meter Reader'
                    else 'Cashier'
                  end;

  select first_name || ' ' || last_name
    into v_existing_name
    from profiles
   where area_id = v_area
     and role = p_role
     and account_status = 'active' and staff_enabled
   limit 1;

  if v_existing_name is not null then
    raise exception
      'Assignment blocked — % is already the active % for this service area',
      v_existing_name, v_role_label;
  end if;

  v_prefix := case p_role
                when 'meter_reader'::user_role then 'MTR'
                else 'CSH'
              end;

  -- Serialises code allocation so two Area Presidents cannot receive the
  -- same MTR/CSH number when requests arrive together.
  perform pg_advisory_xact_lock(hashtext('billalert.staff.' || v_prefix));

  select coalesce(
           max((regexp_replace(user_code, '^[A-Z]+-', ''))::integer),
           0
         ) + 1
    into v_seq
    from profiles
   where user_code ~ ('^' || v_prefix || '-[0-9]+$');

  v_code := v_prefix || '-' || lpad(v_seq::text, 4, '0');

  insert into profiles (
    id, user_code, username, first_name, last_name, role,
    contact_number, area_id, account_status, must_change_password
  ) values (
    p_user_id, v_code, v_username, trim(p_first_name), trim(p_last_name),
    p_role, nullif(trim(coalesce(p_contact_number, '')), ''), v_area,
    'active', true
  );

  return v_code;
exception
  when unique_violation then
    raise exception
      'That username or staff assignment is already in use. Refresh and try again.';
end $$;

create or replace function fn_authorize_password_reset(
  p_admin_id  uuid,
  p_target_id uuid
) returns table (
  target_first_name text,
  target_last_name  text,
  target_kind       text
)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_area   uuid;
  v_target profiles%rowtype;
begin
  perform 1 from areas where id=(select area_id from profiles where id=p_admin_id) for update;
  -- The Edge Function takes this id from the verified JWT. It is looked up
  -- again here so the database, not the function, is where the rule lives.
  select area_id
    into v_area
    from profiles
   where id = p_admin_id
     and role = 'admin'
     and account_status = 'active' and staff_enabled;

  if v_area is null then
    raise exception 'Only an active Area President can reset a password';
  end if;

  if p_target_id = p_admin_id then
    raise exception
      'Use Change password on your Profile to change your own password';
  end if;

  select * into v_target from profiles where id = p_target_id;

  if not found then
    raise exception 'That account was not found';
  end if;

  if v_target.account_status <> 'active' then
    raise exception
      'That account is not active, so its password cannot be reset';
  end if;

  if v_target.role in ('meter_reader'::user_role, 'cashier'::user_role) then
    if v_target.area_id is distinct from v_area then
      raise exception 'That account is not in your service area';
    end if;
  elsif v_target.role = 'consumer'::user_role then
    -- A consumer's login profile carries no area. Their household does.
    if not exists (
      select 1
        from consumers c
       where c.profile_id = p_target_id
         and c.area_id = v_area
    ) then
      raise exception 'That account is not in your service area';
    end if;
  else
    -- An Area President's password is reset by the cooperative, never by a
    -- peer: otherwise one Area President could take over another's account.
    raise exception
      'An Area President''s password cannot be reset from this screen';
  end if;

  return query
    select v_target.first_name, v_target.last_name, v_target.role::text;
end $$;

create or replace function fn_check_household_login(
  p_admin_id     uuid,
  p_consumer_id  uuid,
  p_username     text
) returns table (
  household_first_name text,
  household_last_name  text,
  household_no         text
)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_area      uuid;
  v_username  text := lower(trim(coalesce(p_username, '')));
  v_household consumers%rowtype;
begin
  perform 1 from areas where id=(select area_id from profiles where id=p_admin_id) for update;
  -- The Edge Function takes this id from the verified JWT. It is looked up
  -- again here so the database, not the function, is where the rule lives.
  select area_id
    into v_area
    from profiles
   where id = p_admin_id
     and role = 'admin'
     and account_status = 'active' and staff_enabled;

  if v_area is null then
    raise exception 'Only an active Area President can give a household a sign-in';
  end if;

  select * into v_household from consumers where id = p_consumer_id;

  if not found then
    raise exception 'That household was not found';
  end if;

  if v_household.area_id is distinct from v_area then
    raise exception 'That household is not in your service area';
  end if;

  if v_household.account_status <> 'active' then
    raise exception 'That household is not active, so it cannot be given a sign-in';
  end if;

  if v_household.profile_id is not null then
    raise exception
      'This household already has a sign-in. Use Reset a forgotten password '
      'if they cannot get in';
  end if;

  if v_username !~ '^[a-z][a-z0-9._-]{2,49}$' then
    raise exception
      'Use a username of 3 to 50 characters that starts with a letter and '
      'uses only letters, numbers, dot, underscore or hyphen';
  end if;

  if exists (select 1 from profiles where username = v_username) then
    raise exception 'Username % is already taken', v_username;
  end if;

  return query
    select v_household.first_name, v_household.last_name, v_household.consumer_no;
end $$;

create or replace function public.fn_overdue_decision(p_bill_id uuid, p_action text) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare b bills%rowtype; a uuid; r user_role;
begin
  perform app.lock_own_area();
  select role into r from profiles where id = auth.uid() and account_status = 'active' and staff_enabled;
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

create or replace function public.fn_record_payment(
  p_bill_ids uuid[], p_amounts numeric[], p_cash_tendered numeric default null,
  p_paid_at timestamptz default now(), p_client_uuid uuid default null
) returns uuid language plpgsql security definer set search_path = public, pg_temp as $$
declare c uuid; a uuid; tx payment_transactions%rowtype; b bills%rowtype;
  v_id uuid; v_overdue boolean; i integer;
begin
  perform app.lock_own_area();
  if not exists (select 1 from profiles where id = auth.uid() and role = 'cashier' and account_status = 'active' and staff_enabled) then
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

create or replace function public.fn_post_bill_amount(p_bill_id uuid,p_amount numeric,p_due_date date,p_posted_at timestamptz default now(),p_client_uuid uuid default null)
returns uuid language plpgsql security definer set search_path = public, pg_temp as $$
declare prior app.post_amount_operations%rowtype; n uuid; c uuid;
begin
  perform app.lock_own_area();
  if not exists(select 1 from profiles where id = auth.uid() and role = 'admin' and account_status = 'active' and staff_enabled) then raise exception 'Only an active Admin may post amounts'; end if;
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

create or replace function public.fn_check_collection(p_bill_ids uuid[],p_amounts numeric[]) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare b bills%rowtype; c uuid; i integer;
begin
  perform app.lock_own_area();
  if not exists(select 1 from profiles where id=auth.uid() and role='cashier' and account_status='active' and staff_enabled) then raise exception 'Only an active Cashier can collect'; end if;
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

create or replace function app.queue_staff_alert(p_area uuid,p_role public.user_role,p_key text,p_title text,p_body text,p_destination text)
returns void language sql security definer set search_path=public,pg_temp as $$
  insert into staff_alerts(recipient_id,area_id,recipient_role,event_key,title,body,destination)
  select id,p_area,p_role,p_key,p_title,p_body,p_destination from profiles
  where area_id=p_area and role=p_role and account_status='active' and staff_enabled
  on conflict(recipient_id,event_key) do nothing;
$$;

create or replace function public.fn_claim_staff_alerts(p_device uuid) returns setof public.staff_alerts
language plpgsql security definer set search_path=public,pg_temp as $$
begin
  if p_device is null then raise exception 'Device identity required'; end if;
  return query with eligible as (
    select s.id from staff_alerts s join profiles p on p.id=s.recipient_id
    where p.id=auth.uid() and p.account_status='active' and p.staff_enabled and p.area_id=s.area_id and p.role=s.recipient_role
      and not s.is_read and s.created_at > now()-interval '30 days'
      and not exists (select 1 from app.staff_alert_deliveries d
        where d.alert_id=s.id and d.device_id=p_device
          and (d.shown_at is not null or d.claimed_at >= now()-interval '2 minutes'))
    order by s.created_at limit 50
  ), claimed as (
    insert into app.staff_alert_deliveries as d(alert_id,device_id)
    select id,p_device from eligible
    on conflict(alert_id,device_id) do update set claimed_at=now()
      where d.shown_at is null and d.claimed_at < now()-interval '2 minutes'
    returning alert_id
  ) select s.* from staff_alerts s join claimed c on c.alert_id=s.id;
end $$;

create or replace function public.fn_staff_alert_shown(p_alert uuid,p_device uuid) returns void
language sql security definer set search_path=public,pg_temp as $$
  update app.staff_alert_deliveries set shown_at=now() where alert_id=p_alert and device_id=p_device
    and exists(select 1 from staff_alerts s join profiles p on p.id=s.recipient_id where s.id=p_alert and p.id=auth.uid() and p.account_status='active' and p.staff_enabled and p.area_id=s.area_id and p.role=s.recipient_role);
$$;

create or replace function public.fn_notice_review(p_notice_id uuid) returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
declare r v_notice_review_records%rowtype; result jsonb;
begin
  if not exists(select 1 from profiles where id=auth.uid() and role='admin' and account_status='active' and staff_enabled) then
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

create or replace function public.fn_close_disconnection_notice(p_notice_id uuid,p_outcome notice_status,p_notes text default null)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare n disconnection_notices%rowtype; c uuid; clean text:=nullif(trim(p_notes),'');
begin
  perform app.lock_own_area();
  if not exists(select 1 from profiles where id=auth.uid() and role='admin' and account_status='active' and staff_enabled) then
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

create or replace function fn_record_meter_reading(
  p_consumer_id     uuid,
  p_current_reading numeric,
  p_captured_at     timestamptz default now(),
  p_client_uuid     uuid default gen_random_uuid()
) returns uuid
language plpgsql as $$
declare
  v_consumer     consumers%rowtype;
  v_cycle        billing_cycles%rowtype;
  v_prev         numeric(12,2);
  v_reading      meter_readings%rowtype;
  v_existing     uuid;
  v_reading_date date;
  v_bill_id      uuid;
begin
  perform app.lock_own_area();
  if not app.active_staff(auth.uid(),'meter_reader') then raise exception 'Only the assigned active Meter Reader can upload readings'; end if;
  -- MTR-12: idempotent sync. A retried upload returns the original bill.
  select b.id into v_existing
    from meter_readings mr join bills b on b.meter_reading_id = mr.id
   where mr.client_uuid = p_client_uuid;
  if v_existing is not null then
    return v_existing;
  end if;

  -- Deliberately NOT `for update`, and it must stay that way.
  --
  -- Under RLS, `select ... for update` also checks the UPDATE policy's USING
  -- clause, because locking a row requires permission to update it.
  -- `consumers_admin_update` is admin-only, so a lock here makes this whole
  -- function fail for the Meter Reader - the one role allowed to call it.
  -- The symptom is baffling: the reader can select the household one moment
  -- and be told 'not found or not visible to you' the next.
  --
  -- Nothing below updates the consumer, so there is nothing to lock.
  -- The locks in fn_post_bill_amount and fn_record_payment are different and
  -- must stay: they are on `bills`, whose update policy covers admin and
  -- cashier, and the one in fn_record_payment guards against two cashiers
  -- settling the same bill at once.
  select * into v_consumer from consumers where id = p_consumer_id;
  if not found then
    raise exception 'Consumer % not found or not visible to you', p_consumer_id
      using errcode = 'no_data_found';
  end if;
  if v_consumer.account_status <> 'active' then
    raise exception 'Consumer % is not active', v_consumer.consumer_no;
  end if;

  v_reading_date := fn_ph_today(p_captured_at);          -- SYS-07
  v_cycle := fn_ensure_billing_cycle(v_reading_date);    -- DOM-01

  -- FR-23: reject a second READING in the same cycle, with a message the
  -- Meter Reader can act on. The unique constraint is the real guarantee;
  -- this is the friendly error.
  if exists (select 1 from meter_readings
              where consumer_id = p_consumer_id and billing_cycle_id = v_cycle.id) then
    raise exception 'Consumer % has already been read for % %',
      v_consumer.consumer_no,
      to_char(v_cycle.period_start, 'FMMonth'), v_cycle.cycle_year
      using errcode = 'unique_violation';
  end if;

  -- MTR-08 / DOM-02: previous reading, or zero when there is no history.
  select mr.current_reading into v_prev
    from meter_readings mr
    join billing_cycles bc on bc.id = mr.billing_cycle_id
   where mr.consumer_id = p_consumer_id
   order by bc.period_start desc
   limit 1;
  v_prev := coalesce(v_prev, v_consumer.opening_reading);

  if p_current_reading < v_prev then
    raise exception 'Present reading (%) is lower than the previous reading (%) for consumer %',
      p_current_reading, v_prev, v_consumer.consumer_no;
  end if;

  insert into meter_readings (
    consumer_id, billing_cycle_id, previous_reading, current_reading,
    reading_date, captured_at, recorded_by, client_uuid
  ) values (
    p_consumer_id, v_cycle.id, v_prev, p_current_reading,
    v_reading_date, p_captured_at, app.current_user_id(), p_client_uuid
  ) returning * into v_reading;

  -- The bill is born UNPRICED: total_amount, due_date and priced_at all NULL.
  insert into bills (
    bill_no, consumer_id, billing_cycle_id, meter_reading_id, consumption,
    generated_at, generated_by
  ) values (
    'BA-' || to_char(v_cycle.period_start, 'YYYYMM') || '-'
          || lpad(nextval('bill_no_seq')::text, 6, '0'),
    p_consumer_id, v_cycle.id, v_reading.id, v_reading.consumption,
    p_captured_at, app.current_user_id()
  ) returning id into v_bill_id;

  return v_bill_id;
end $$;
create or replace function fn_update_own_contact_number(
  p_contact_number text
) returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_saved text;
begin
  if app.current_user_id() is null or app.current_consumer_id() is null then
    raise exception using
      errcode = '42501',
      message = 'Only a signed-in consumer may change a household SMS number';
  end if;

  if nullif(trim(coalesce(p_contact_number, '')), '') is null then
    raise exception 'Enter the mobile number that should receive SMS alerts';
  end if;

  -- Raw text on purpose. trg_consumers_normalize_contact normalizes it before
  -- the CHECK and unique index validate the stored value.
  update consumers
     set contact_number = p_contact_number
   where id = app.current_consumer_id() and account_status='active'
   returning contact_number into v_saved;

  if not found then
    raise no_data_found;
  end if;

  return v_saved;
exception
  when check_violation then
    raise exception
      'Enter a Philippine mobile number such as 0917 555 0142';
  when unique_violation then
    raise exception using
      errcode = '23505',
      message = 'That mobile number is already used by another household';
end $$;
create or replace function fn_issue_disconnection_notice(
  p_consumer_id uuid,
  p_reason      text default null,
  p_served_at   timestamptz default now(),
  p_client_uuid uuid default gen_random_uuid()
) returns uuid
language plpgsql as $$
declare
  v_existing  uuid;
  v_notice_id uuid;
  v_lawful    timestamptz;
  v_consumer  consumers%rowtype;
  v_reason    text;
  v_msg       text;
  v_notice_no text;
begin
  perform app.lock_own_area();
  select id into v_existing from disconnection_notices where client_uuid = p_client_uuid;
  if v_existing is not null then
    return v_existing;                                     -- MTR-12 idempotent
  end if;

  select * into v_consumer from consumers where id = p_consumer_id;
  if not found then
    raise exception 'Consumer % not found or not visible to you', p_consumer_id;
  end if;

  -- A notice is only lawful against an account that is actually overdue.
  -- An unpriced bill has no due date and can never be overdue, so the
  -- threshold is computable only over payable bills.
  if not exists (
    select 1 from bills
     where consumer_id = p_consumer_id
       and total_amount is not null
       and status <> 'paid'
       and due_date < fn_ph_today(p_served_at)
  ) then
    raise exception 'Consumer % has no overdue bill; a disconnection notice cannot be issued',
      v_consumer.consumer_no;
  end if;

  v_lawful := fn_earliest_lawful_disconnection(p_served_at);
  v_reason := coalesce(nullif(trim(p_reason), ''), 'Unpaid electricity bill');

  -- "DN-2026-0819-0033"
  v_notice_no := 'DN-' || to_char(p_served_at at time zone 'Asia/Manila', 'YYYY-MMDD')
                 || '-' || lpad(nextval('notice_no_seq')::text, 4, '0');

  insert into disconnection_notices (
    notice_no, consumer_id, reason, served_at, earliest_lawful_at, issued_by, client_uuid
  ) values (
    v_notice_no, p_consumer_id, v_reason, p_served_at, v_lawful,
    app.current_user_id(), p_client_uuid
  ) returning id into v_notice_id;

  v_msg := format(
    'NOTICE %s: %s %s, your BillAlert account %s has an unpaid balance. Reason: %s. '
    || 'Please settle before %s to avoid disconnection.',
    v_notice_no, v_consumer.first_name, v_consumer.last_name, v_consumer.consumer_no, v_reason,
    to_char(v_lawful at time zone 'Asia/Manila', 'FMMon DD, YYYY HH12:MI AM')
  );

  -- Objective 3: disconnection notices go by SMS, so they reach a consumer
  -- who does not open the app.
  perform fn_queue_notification(
    p_consumer_id, 'disconnection', 'sms', v_msg, null, v_notice_id, null
  );

  return v_notice_id;
end $$;
create or replace function fn_record_remit_handover(p_month date)
returns remit_handovers
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_area   uuid := app.current_area();
  v_month  date := date_trunc('month', p_month)::date;
  f        record;
  v_reader profiles%rowtype;
  v_row    remit_handovers;
begin
  perform app.lock_own_area();
  if app.current_role() is distinct from 'cashier'::user_role then
    raise exception 'Only the Cashier can record a handover';
  end if;
  if exists (select 1 from remit_handovers
              where area_id = v_area and remit_month = v_month) then
    raise exception 'The handover for % is already recorded',
      to_char(v_month, 'FMMonth YYYY');
  end if;

  select * into f from fn_rounding_fund(v_area) r where r.remit_month = v_month;
  if not found then
    raise exception 'Nothing was collected for % yet',
      to_char(v_month, 'FMMonth YYYY');
  end if;

  select * into v_reader from profiles
   where role = 'meter_reader' and area_id = v_area and account_status = 'active' and staff_enabled
   order by created_at desc limit 1;

  insert into remit_handovers (
    area_id, remit_month, to_boheco, reader_pay, gap,
    handed_by, handed_to, handed_to_name
  ) values (
    v_area, v_month, f.to_boheco, f.reader_pay, f.gap,
    app.current_user_id(), v_reader.id,
    nullif(trim(coalesce(v_reader.first_name, '') || ' ' || coalesce(v_reader.last_name, '')), '')
  )
  returning * into v_row;

  return v_row;
end $$;

-- Keep newly created household logins manageable after later membership changes.
create or replace function fn_create_household_login(
  p_admin_id     uuid,
  p_user_id      uuid,
  p_consumer_id  uuid,
  p_username     text
) returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_username  text := lower(trim(coalesce(p_username, '')));
  v_household consumers%rowtype;
  v_seq       integer;
  v_code      text;
begin
  perform 1 from areas where id=(select area_id from profiles where id=p_admin_id) for update;
  -- Held until commit, so two taps on Create — or two Area Presidents'
  -- phones — cannot both link a sign-in to the same household.
  perform 1 from consumers where id = p_consumer_id for update;

  -- Checked again rather than trusted from the earlier call: the household
  -- may have been given a sign-in in between.
  perform 1 from fn_check_household_login(p_admin_id, p_consumer_id, v_username);

  select * into v_household from consumers where id = p_consumer_id;

  -- CON-0008. Serialised so two requests cannot receive the same number.
  perform pg_advisory_xact_lock(hashtext('billalert.staff.CON'));

  select coalesce(
           max((regexp_replace(user_code, '^[A-Z]+-', ''))::integer),
           0
         ) + 1
    into v_seq
    from profiles
   where user_code ~ '^CON-[0-9]+$';

  v_code := 'CON-' || lpad(v_seq::text, 4, '0');

  -- Retain the registration area for account management. Consumer profiles
  -- still receive no work permission; current_area() returns null for them.
  -- GEN-04: the temporary password must be replaced at first sign-in.
  insert into profiles (
    id, user_code, username, first_name, last_name, role,
    area_id, account_status, must_change_password
  ) values (
    p_user_id, v_code, v_username, v_household.first_name,
    v_household.last_name, 'consumer', v_household.area_id, 'active', true
  );

  update consumers
     set profile_id = p_user_id,
         updated_at = now()
   where id = p_consumer_id;

  return v_code;
exception
  when unique_violation then
    raise exception
      'That username or household sign-in is already in use. Refresh and try again.';
end $$;

commit;
