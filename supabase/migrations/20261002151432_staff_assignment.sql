-- REVIEW REQUIRED: apply after account_lifecycle and reader_boheco_waiver.
-- No accounts, household links or financial records are deleted or renamed.
begin;

-- Private, successful-operation receipts make an uncertain response safe to
-- reconcile. No client may insert or alter one, even if app becomes exposed.
create table app.staff_assignment_operations (
  id uuid primary key,
  actor_id uuid not null references public.profiles(id),
  area_id uuid not null references public.areas(id),
  request jsonb not null,
  completed_at timestamptz not null default clock_timestamp()
);
alter table app.staff_assignment_operations enable row level security;
revoke all on app.staff_assignment_operations from public, anon, authenticated;

create or replace function public.fn_account_workspace() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare a uuid := app.current_area();
begin
  if not app.active_staff(auth.uid(), 'admin') then
    raise exception 'Only the active Area President can manage accounts';
  end if;
  return jsonb_build_object(
    'people', coalesce((select jsonb_agg(jsonb_build_object(
      'id', p.id, 'username', p.username, 'first_name', p.first_name,
      'last_name', p.last_name, 'role', p.role, 'staff_enabled', p.staff_enabled,
      'account_status', p.account_status, 'area_id', p.area_id,
      'access_version', p.access_version) order by p.first_name, p.last_name)
      from public.profiles p where p.area_id = a or exists (
        select 1 from public.consumers c where c.profile_id = p.id and c.area_id = a)), '[]'),
    'households', coalesce((select jsonb_agg(jsonb_build_object(
      'id', c.id, 'consumer_no', c.consumer_no, 'first_name', c.first_name,
      'last_name', c.last_name, 'profile_id', c.profile_id,
      'meter_serial_no', c.meter_serial_no, 'account_status', c.account_status)
      order by c.consumer_no) from public.consumers c where c.area_id = a), '[]'),
    'transfers', coalesce((select jsonb_agg(to_jsonb(t) order by t.created_at desc)
      from public.president_transfers t where t.area_id = a), '[]'),
    'audit', coalesce((select jsonb_agg(to_jsonb(e) order by e.created_at desc)
      from (select id, actor_id, target_id, action, reason, details, created_at
        from public.account_events where area_id = a
        order by created_at desc limit 200) e), '[]'));
end $$;

create function public.fn_assign_staff(
  p_operation uuid,
  p_role public.user_role,
  p_replacement uuid,
  p_replacement_version bigint,
  p_outgoing uuid,
  p_outgoing_version bigint,
  p_reconciled boolean
) returns void language plpgsql security definer set search_path = '' as $$
declare
  a uuid;
  outgoing public.profiles%rowtype;
  incoming public.profiles%rowtype;
  prior app.staff_assignment_operations%rowtype;
  request_data jsonb;
begin
  -- Same lock ordering as existing financial writes and account handovers.
  perform app.lock_own_area();
  if not app.active_staff(auth.uid(), 'admin') then
    raise exception 'Only the active Area President can assign staff';
  end if;
  a := app.current_area();
  if a is null or p_role is null or p_role not in ('meter_reader', 'cashier') then
    raise exception 'Choose Meter Reader or Cashier';
  end if;
  if p_operation is null or p_replacement is null or p_replacement_version is null then
    raise exception 'Refresh and choose the replacement again';
  end if;
  if p_reconciled is distinct from true then
    raise exception 'Confirm that all affected devices are synced and cash handover is complete';
  end if;
  request_data := jsonb_build_object('role', p_role, 'replacement', p_replacement,
    'replacement_version', p_replacement_version, 'outgoing', p_outgoing,
    'outgoing_version', p_outgoing_version);
  select * into prior from app.staff_assignment_operations where id = p_operation;
  if found then
    if prior.actor_id is distinct from auth.uid() or prior.area_id is distinct from a
      or prior.request is distinct from request_data then
      raise exception 'This request belongs to a different staff change';
    end if;
    return; -- Already committed; never reapply an old appointment.
  end if;

  select * into outgoing from public.profiles
    where area_id = a and role = p_role and account_status = 'active' and staff_enabled
    for update;
  if outgoing.id is distinct from p_outgoing
    or outgoing.access_version is distinct from p_outgoing_version then
    raise exception 'The staff assignment changed. Refresh and review it again';
  end if;
  select * into incoming from public.profiles where id = p_replacement and area_id = a
    for update;
  if not found or incoming.account_status <> 'active'
    or incoming.role = 'admin' or incoming.id = outgoing.id
    or (incoming.role <> 'consumer' and incoming.staff_enabled) then
    raise exception 'Choose an active person in your area who is not already working in another position';
  end if;
  if incoming.access_version is distinct from p_replacement_version then
    raise exception 'The replacement account changed. Refresh and choose again';
  end if;

  -- Both changes commit together. Existing triggers increment access_version
  -- and end outgoing reader coverage; historic covered bills remain untouched.
  update public.profiles set staff_enabled = false where id = outgoing.id;
  update public.profiles set role = p_role, staff_enabled = true where id = incoming.id;
  insert into public.account_events(area_id, actor_id, target_id, action, reason, details)
    values(a, auth.uid(), incoming.id, 'staff_assigned', 'Reviewed staff handover',
      jsonb_build_object('role', p_role, 'outgoing_id', outgoing.id,
        'incoming_id', incoming.id, 'reconciled', true, 'operation_id', p_operation));
  insert into app.staff_assignment_operations(id, actor_id, area_id, request)
    values(p_operation, auth.uid(), a, request_data);
end $$;

revoke all on function public.fn_account_workspace(),
  public.fn_assign_staff(uuid,public.user_role,uuid,bigint,uuid,bigint,boolean)
  from public, anon;
grant execute on function public.fn_account_workspace(),
  public.fn_assign_staff(uuid,public.user_role,uuid,bigint,uuid,bigint,boolean)
  to authenticated;
commit;
