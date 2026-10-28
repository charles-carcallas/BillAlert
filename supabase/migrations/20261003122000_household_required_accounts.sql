-- Review before applying. Requires staff_assignment and account_lifecycle.
-- Existing profiles are not backfilled, deleted or disabled by this migration.
begin;

-- Legacy normalization called an unqualified helper; secure callers use an
-- empty search_path, so qualify that helper inside the trigger itself.
create or replace function public.fn_normalize_contact() returns trigger
language plpgsql set search_path='' as $$
begin
 new.contact_number := public.fn_normalize_ph_mobile(new.contact_number);
 return new;
end $$;

create function public.fn_create_linked_account(
 p_actor uuid,p_user uuid,p_username text,p_first_name text,p_last_name text,
 p_reason text,p_role text,p_household jsonb
) returns uuid language plpgsql security definer set search_path='' as $$
declare
 a uuid; c public.consumers%rowtype; cid uuid; result_id uuid;
 mode text:=p_household->>'mode'; prior numeric;
begin
 perform 1 from public.areas where id=(select area_id from public.profiles where id=p_actor) for update;
 if not app.active_staff(p_actor,'admin') then raise exception 'Only the active Area President can create accounts'; end if;
 select area_id into a from public.profiles where id=p_actor;
 if p_role is null or p_role not in ('consumer','meter_reader','cashier','successor')
   or mode is null or mode not in ('new','existing','same_household','handover')
   or (p_household->>'confirmed') is distinct from 'true' then
   raise exception 'Choose and confirm the account owner household';
 end if;
 if mode <> 'new' then
   select * into c from public.consumers where id=(p_household->>'id')::uuid and area_id=a for update;
   if not found or c.account_status<>'active' then raise exception 'Choose an active household in your area'; end if;
   if mode='existing' and c.profile_id is not null then raise exception 'This household already has a login. Use its existing account'; end if;
   if mode in ('same_household','handover') and nullif(trim(p_household->>'reference'),'') is null then
     raise exception 'A reviewed handover reference is required';
   end if;
   if mode='same_household' and exists(select 1 from public.profiles where id=c.profile_id and account_status='active') then
     raise exception 'Disable the previous household login before replacing it';
   end if;
 end if;
 if mode in ('new','handover') and nullif(trim(p_household->>'consumer_no'),'') is null then
   raise exception 'Enter the household consumer number';
 end if;
 if mode='handover' then
   select current_reading into prior from public.meter_readings where consumer_id=c.id order by reading_date desc,captured_at desc limit 1;
   if nullif(p_household->>'opening_reading','') is null or (p_household->>'opening_reading')::numeric<>coalesce(prior,c.opening_reading) then
     raise exception 'Opening reading must match the previous household closing reading';
   end if;
   if exists(select 1 from public.bills where consumer_id=c.id and total_amount is null) then
     raise exception 'Post outstanding reading amounts before handover';
   end if;
 end if;
 if p_role='successor' then
   result_id:=public.fn_prepare_president_transfer(p_actor,p_user,p_username,p_first_name,p_last_name,p_reason);
 elsif p_role in ('meter_reader','cashier') then
   perform public.fn_create_staff_profile(p_actor,p_user,p_username,p_first_name,p_last_name,p_role::public.user_role,p_household->>'contact');
   result_id:=p_user;
 else
   result_id:=public.fn_prepare_consumer_identity(p_actor,p_user,p_username,p_first_name,p_last_name,p_reason);
 end if;
 if mode in ('existing','same_household') then
   update public.consumers set profile_id=p_user where id=c.id;
   cid:=c.id;
 else
   if mode='handover' then
     update public.consumers set account_status='inactive',meter_serial_no=null where id=c.id;
   end if;
   insert into public.consumers(consumer_no,profile_id,first_name,last_name,contact_number,meter_serial_no,area_id,purok,created_by,opening_reading)
   values(trim(p_household->>'consumer_no'),p_user,trim(p_first_name),trim(p_last_name),
     nullif(trim(p_household->>'contact'),''),
     case when mode='handover' then c.meter_serial_no else nullif(trim(p_household->>'meter'),'') end,a,
     case when mode='handover' then c.purok else nullif(trim(p_household->>'purok'),'') end,p_actor,
     case when mode='handover' then (p_household->>'opening_reading')::numeric else 0 end) returning id into cid;
 end if;
 insert into public.account_events(area_id,actor_id,target_id,action,reason,details)
 values(a,p_actor,p_user,'linked_account_created',p_reason,jsonb_build_object('consumer_id',cid,'mode',mode,'previous_consumer_id',c.id,'previous_profile_id',c.profile_id));
 return result_id;
end $$;
revoke all on function public.fn_create_linked_account(uuid,uuid,text,text,text,text,text,jsonb) from public,anon,authenticated;
grant execute on function public.fn_create_linked_account(uuid,uuid,text,text,text,text,text,jsonb) to service_role;

-- Deferred until transaction end, so profile + household can be created atomically.
-- INSERT-only: legacy accounts remain usable while the Admin reviews their links.
create function app.require_new_account_household() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if exists(select 1 from public.profiles where id=new.id) and
    not exists(select 1 from public.consumers where profile_id=new.id) then
   raise exception 'New accounts require a household. Update the app and use linked account creation';
 end if;
 return null;
end $$;
revoke all on function app.require_new_account_household() from public,anon,authenticated;
create constraint trigger require_new_account_household after insert on public.profiles
 deferrable initially deferred for each row execute function app.require_new_account_household();

-- Keep the established atomic assignment, version and idempotency checks.
alter function public.fn_assign_staff(uuid,public.user_role,uuid,bigint,uuid,bigint,boolean) set schema app;
alter function app.fn_assign_staff(uuid,public.user_role,uuid,bigint,uuid,bigint,boolean) rename to assign_staff_before_household_rule;
revoke all on function app.assign_staff_before_household_rule(uuid,public.user_role,uuid,bigint,uuid,bigint,boolean) from public,anon,authenticated;
create function public.fn_assign_staff(p_operation uuid,p_role public.user_role,p_replacement uuid,p_replacement_version bigint,p_outgoing uuid,p_outgoing_version bigint,p_reconciled boolean)
returns void language plpgsql security definer set search_path='' as $$
begin
 perform app.lock_own_area();
 if not app.active_staff(auth.uid(),'admin') then raise exception 'Only the active Area President can assign staff'; end if;
 if not exists(select 1 from app.staff_assignment_operations where id=p_operation) then
   if not exists(select 1 from public.consumers where profile_id=p_replacement and area_id=app.current_area() and account_status='active') then
     raise exception 'Set up the replacement household before assigning staff';
   end if;
   if p_outgoing is not null and not exists(select 1 from public.consumers where profile_id=p_outgoing) then
     raise exception 'Link the outgoing staff household or disable their login, then refresh this handover';
   end if;
 end if;
 perform app.assign_staff_before_household_rule(p_operation,p_role,p_replacement,p_replacement_version,p_outgoing,p_outgoing_version,p_reconciled);
end $$;
revoke all on function public.fn_assign_staff(uuid,public.user_role,uuid,bigint,uuid,bigint,boolean) from public,anon;
grant execute on function public.fn_assign_staff(uuid,public.user_role,uuid,bigint,uuid,bigint,boolean) to authenticated;
commit;
