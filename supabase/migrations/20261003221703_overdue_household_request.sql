-- REVIEW ONLY. Apply after account lifecycle and overdue collection migrations.
-- Preserves accounts, bills, notices and receipts. No automatic payment/SMS.
begin;

create function public.fn_request_overdue_household(
  p_consumer_id uuid,
  p_bill_ids uuid[],
  p_expected_amounts numeric[]
) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  b public.bills%rowtype;
  i integer;
begin
  -- Same lock order as staff changes and cash collection: area, household, bills.
  perform app.lock_own_area();
  if not app.active_staff(auth.uid(), 'cashier') then
    raise exception 'Only an active Cashier can request authorization';
  end if;
  if p_consumer_id is null or coalesce(cardinality(p_bill_ids),0)=0
     or array_ndims(p_bill_ids)<>1 or array_ndims(p_expected_amounts)<>1
     or array_lower(p_bill_ids,1)<>1 or array_lower(p_expected_amounts,1)<>1
     or cardinality(p_bill_ids) is distinct from cardinality(p_expected_amounts)
     or array_position(p_bill_ids,null) is not null
     or array_position(p_expected_amounts,null) is not null
     or (select count(distinct id) from unnest(p_bill_ids) id)<>cardinality(p_bill_ids) then
    raise exception 'Select distinct overdue bills and their reviewed balances';
  end if;
  perform 1 from public.consumers where id=p_consumer_id and area_id=app.current_area() for update;
  if not found then raise exception 'Household unavailable in your area'; end if;
  perform 1 from public.bills where consumer_id=p_consumer_id order by id for update;
  -- Validate the entire selection before requesting anything.
  for i in 1..cardinality(p_bill_ids) loop
    select * into b from public.bills where id=p_bill_ids[i];
    if not found or b.consumer_id<>p_consumer_id then
      raise exception 'Select bills for one household';
    end if;
    if b.total_amount is null or b.due_date is null or b.due_date>=public.fn_ph_today()
       or b.balance<=0 then raise exception 'A selected bill is no longer overdue. Refresh before authorizing'; end if;
    if p_expected_amounts[i]<=0 or p_expected_amounts[i]='NaN'::numeric
       or p_expected_amounts[i] is distinct from b.balance then
      raise exception 'Balance changed. Refresh and review the selected bills again';
    end if;
  end loop;
  for b in select * from public.bills where id=any(p_bill_ids) order by id loop
    -- A retry preserves unchanged requests/approvals and their audit/alerts.
    if not exists(select 1 from public.overdue_collection_approvals
      where bill_id=b.id and state in ('approved','requested') and amount=b.balance) then
      perform public.fn_overdue_decision(b.id,'requested');
    end if;
  end loop;
end $$;
revoke all on function public.fn_request_overdue_household(uuid,uuid[],numeric[]) from public, anon, authenticated;
grant execute on function public.fn_request_overdue_household(uuid,uuid[],numeric[]) to authenticated;
comment on function public.fn_request_overdue_household(uuid,uuid[],numeric[]) is
  'Active area Cashier requests reviewed overdue balances atomically; existing matching approvals and requests are preserved.';

notify pgrst, 'reload schema';
commit;

