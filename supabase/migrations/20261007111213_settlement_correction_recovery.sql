-- Apply after regular_rounding_reserve_credit, then install the updated app.
begin;

-- Keep the old API compatible, but restore the actual reporting state.
do $$ declare d text; begin
 d:=pg_get_functiondef('public.fn_correct_settlement(uuid,text)'::regprocedure);
 if position('set state=''referred'',reference=null' in d)=0 then
  raise exception 'Unexpected settlement correction definition';
 end if;
 d:=replace(d,'set state=''referred'',reference=null',
  'set state=case when s.referred_at is null then ''awaiting_referral'' else ''referred'' end,reference=null');
 execute d;
end $$;

-- Repair impossible reporting states without inventing a report or sending a notice.
with repaired as (
 update public.bill_settlements set state='awaiting_referral',updated_at=clock_timestamp()
 where route='boheco' and state='referred' and referred_at is null
 returning area_id,bill_id
)
insert into public.settlement_audit(area_id,bill_id,action,detail)
select area_id,bill_id,'reporting_state_repaired',
 jsonb_build_object('reason','Missing reporting date; awaiting actual BOHECO report') from repaired;

-- Private retry receipts. No client can read or write this table directly.
create table app.settlement_corrections (
 client_uuid uuid primary key, area_id uuid not null references public.areas(id),
 actor_id uuid not null references public.profiles(id),
 bill_id uuid not null references public.bills(id), action text not null,
 expected_updated_at timestamptz not null, reason text not null
);
alter table app.settlement_corrections enable row level security;
revoke all on app.settlement_corrections from public,anon,authenticated;

create function public.fn_correct_settlement_checked(
 p_bill uuid,p_reason text,p_action text,p_expected_updated_at timestamptz,p_client_uuid uuid
) returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare a uuid:=app.settlement_actor(array['admin']::user_role[]);
 s bill_settlements; previous app.settlement_corrections; affected integer;
begin
 if nullif(trim(p_reason),'') is null or p_client_uuid is null or p_expected_updated_at is null
    or p_action is null or p_action not in ('return_funds','reverse_verification') then
  raise exception 'Refresh and provide the correction action and reason';
 end if;
 perform 1 from areas where id=a for update;
 select * into previous from app.settlement_corrections where client_uuid=p_client_uuid;
 if found then
  if previous.area_id=a and previous.actor_id=auth.uid() and previous.bill_id=p_bill
   and previous.action=p_action and previous.reason=trim(p_reason)
   and previous.expected_updated_at=p_expected_updated_at then return; end if;
  raise exception 'Correction request already used for different details';
 end if;
 select * into s from bill_settlements where bill_id=p_bill and area_id=a;
 if not found then raise exception 'Settlement unavailable in your area'; end if;
 perform 1 from consumers where id=s.consumer_id for update;
 perform 1 from bills where id=p_bill for update;
 if s.updated_at is distinct from p_expected_updated_at then
  raise exception 'Settlement changed. Refresh before correcting it';
 end if;
 if p_action='return_funds' then
  if s.route<>'pondo' or s.state<>'handed_over' then
   raise exception 'Only money still with the Meter Reader can be recorded as returned';
  end if;
  perform public.fn_correct_settlement(p_bill,p_reason);
 elsif s.route='boheco' and s.state='settled' then
  if not exists(select 1 from boheco_payment_evidence where bill_id=p_bill and reversed_at is null) then
   raise exception 'No active BOHECO verification to reverse';
  end if;
  perform public.fn_correct_settlement(p_bill,p_reason);
 elsif s.route='pondo' and s.state='awaiting_repayment' then
  if s.transaction_id is not null or exists(select 1 from payments p
    join payment_transactions t on t.id=p.transaction_id
    where p.bill_id=p_bill and t.collection_kind='pondo_repayment') then
   raise exception 'Cash repayment already exists. Reconcile that receipt before reversing verification';
  end if;
  update boheco_payment_evidence set reversed_at=now(),reversed_by=auth.uid(),reversal_reason=trim(p_reason)
   where bill_id=p_bill and reversed_at is null;
  get diagnostics affected=row_count;
  if affected=0 then raise exception 'No active BOHECO verification to reverse'; end if;
  -- No cash is credited: the handed-over money is still the Reader's responsibility.
  update bill_settlements set state='handed_over',reference=null,evidence=null,paid_at=null,
   verified_by=null,updated_at=clock_timestamp() where bill_id=p_bill;
  insert into settlement_audit(area_id,bill_id,actor_id,action,detail)
  values(a,p_bill,auth.uid(),'correction',jsonb_build_object(
   'previous_state',s.state,'reason',trim(p_reason),'cash_returned',false));
 else
  raise exception 'This bill cannot be reversed automatically. Reconcile any Cashier repayment first';
 end if;
 insert into app.settlement_corrections values(p_client_uuid,a,auth.uid(),p_bill,p_action,p_expected_updated_at,trim(p_reason));
end $$;
revoke all on function public.fn_correct_settlement_checked(uuid,text,text,timestamptz,uuid) from public,anon;
grant execute on function public.fn_correct_settlement_checked(uuid,text,text,timestamptz,uuid) to authenticated;

commit;
