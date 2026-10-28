-- REVIEW ONLY: apply after 19. Separate from consumer SMS/push delivery.
begin;
create table public.staff_alerts (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references public.profiles(id),
  area_id uuid not null references public.areas(id),
  recipient_role public.user_role not null,
  event_key text not null,
  title text not null,
  body text not null,
  destination text not null,
  is_read boolean not null default false,
  created_at timestamptz not null default now(),
  unique(recipient_id,event_key)
);
alter table public.staff_alerts enable row level security;
create policy staff_alert_recipient on public.staff_alerts for select to authenticated using (
  recipient_id=auth.uid() and area_id=app.current_area() and recipient_role=app.current_role()
  and exists(select 1 from public.profiles where id=auth.uid() and account_status='active')
);
revoke all on public.staff_alerts from public,anon,authenticated;
grant select on public.staff_alerts to authenticated;
create table app.staff_alert_deliveries (
  alert_id uuid not null references public.staff_alerts(id), device_id uuid not null,
  claimed_at timestamptz not null default now(), shown_at timestamptz,
  primary key(alert_id,device_id)
);
revoke all on app.staff_alert_deliveries from public,anon,authenticated;

create function app.queue_staff_alert(p_area uuid,p_role public.user_role,p_key text,p_title text,p_body text,p_destination text)
returns void language sql security definer set search_path=public,pg_temp as $$
  insert into staff_alerts(recipient_id,area_id,recipient_role,event_key,title,body,destination)
  select id,p_area,p_role,p_key,p_title,p_body,p_destination from profiles
  where area_id=p_area and role=p_role and account_status='active'
  on conflict(recipient_id,event_key) do nothing;
$$;
revoke all on function app.queue_staff_alert(uuid,public.user_role,text,text,text,text) from public,anon,authenticated;

create function app.staff_bill_events() returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
declare a uuid;
begin
  select area_id into a from consumers where id=new.consumer_id;
  if tg_op='INSERT' then
    perform app.queue_staff_alert(a,'admin','reading:'||new.id,'Reading received','A reading is ready for its cooperative amount.','/admin');
  elsif old.total_amount is null and new.total_amount is not null then
    perform app.queue_staff_alert(a,'cashier','priced:'||new.id,'Bill ready','A new bill is available. Check collection eligibility before accepting cash.','/cashier');
  end if;
  return new;
end $$;
create trigger staff_bill_events after insert or update of total_amount on public.bills for each row execute function app.staff_bill_events();

create function app.staff_household_events() returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
begin
  if tg_op='INSERT' or new.area_id is distinct from old.area_id then
    perform app.queue_staff_alert(new.area_id,'meter_reader','household:'||new.id||':'||new.area_id||':'||new.updated_at,
      'Household assigned','Refresh your roster to see the household assigned to your area.','/reader');
  end if;
  return new;
end $$;
create trigger staff_household_events after insert or update of area_id on public.consumers for each row execute function app.staff_household_events();

create function app.staff_approval_events() returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
begin
  if new.state='requested' then
    perform app.queue_staff_alert(new.area_id,'admin','approval-request:'||new.bill_id||':'||new.updated_at,
      'Overdue approval needed','Review the overdue balance before authorizing collection.','/admin/overdue');
  elsif new.state in ('approved','revoked') then
    perform app.queue_staff_alert(new.area_id,'cashier','approval:'||new.bill_id||':'||new.state||':'||new.updated_at,
      case when new.state='approved' then 'Overdue collection authorized' else 'Authorization revoked' end,
      'Open Overdue to check the latest collection decision.','/cashier/overdue');
  end if;
  return new;
end $$;
create trigger staff_approval_events after insert or update on public.overdue_collection_approvals for each row execute function app.staff_approval_events();

create function public.fn_claim_staff_alerts(p_device uuid) returns setof public.staff_alerts
language plpgsql security definer set search_path=public,pg_temp as $$
begin
  if p_device is null then raise exception 'Device identity required'; end if;
  return query with eligible as (
    select s.id from staff_alerts s join profiles p on p.id=s.recipient_id
    where p.id=auth.uid() and p.account_status='active' and p.area_id=s.area_id and p.role=s.recipient_role
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
create function public.fn_staff_alert_shown(p_alert uuid,p_device uuid) returns void
language sql security definer set search_path=public,pg_temp as $$
  update app.staff_alert_deliveries set shown_at=now() where alert_id=p_alert and device_id=p_device
    and exists(select 1 from staff_alerts s join profiles p on p.id=s.recipient_id where s.id=p_alert and p.id=auth.uid() and p.account_status='active' and p.area_id=s.area_id and p.role=s.recipient_role);
$$;
create function public.fn_read_staff_alert(p_alert uuid) returns void
language sql security definer set search_path=public,pg_temp as $$
  update staff_alerts s set is_read=true where s.id=p_alert and s.recipient_id=auth.uid()
    and s.area_id=app.current_area() and s.recipient_role=app.current_role();
$$;
revoke all on function public.fn_claim_staff_alerts(uuid), public.fn_staff_alert_shown(uuid,uuid), public.fn_read_staff_alert(uuid) from public,anon;
grant execute on function public.fn_claim_staff_alerts(uuid), public.fn_staff_alert_shown(uuid,uuid), public.fn_read_staff_alert(uuid) to authenticated;
revoke all on function app.staff_bill_events(),app.staff_household_events(),app.staff_approval_events() from public,anon,authenticated;
commit;
