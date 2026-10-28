-- Apply after automatic BOHECO routing and monthly compensation.
-- Credits only new regular receipts. Existing receipts/opening cash are not
-- backfilled: historical rounding may already be included in recorded cash.
begin;

alter table public.pondo_ledger drop constraint pondo_ledger_kind_check;
alter table public.pondo_ledger add constraint pondo_ledger_kind_check check (
 kind in ('opening','contribution','handover','repayment','returned','correction','withdrawal','rounding')
);
create unique index pondo_one_regular_rounding on public.pondo_ledger(transaction_id)
 where kind='rounding';

-- Keep the role, area lock, full-repayment rules and UUID retry validation.
-- The old-receipt return occurs before crediting, so retries of receipts
-- recorded before installation do not silently import historical money.
create or replace function public.fn_record_payment(p_bill_ids uuid[],p_amounts numeric[],p_cash_tendered numeric default null,
 p_paid_at timestamptz default now(),p_client_uuid uuid default null) returns uuid
language plpgsql security definer set search_path=public,pg_temp as $$
declare a uuid:=app.settlement_actor(array['cashier']::user_role[]); old payment_transactions; v uuid; i integer; repayment boolean; collected_rounding numeric;
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
 else
  -- The payment view allocates actual cash to BOHECO first, then rounding.
  -- Partial payments below the cooperative amount contribute zero here.
  select coalesce(sum(h.amount_paid-coalesce(h.boheco_share,h.amount_paid)),0)
   into collected_rounding
   from public.v_payment_history h join public.payments p on p.id=h.payment_id
   where p.transaction_id=v;
  if collected_rounding>0 then
   insert into public.pondo_ledger(area_id,amount,kind,transaction_id,actor_id,reason,client_uuid)
   values(a,collected_rounding,'rounding',v,auth.uid(),'Rounding from regular collection',p_client_uuid);
  end if;
 end if; return v;
end $$;

revoke all on function public.fn_record_payment(uuid[],numeric[],numeric,timestamptz,uuid) from public,anon;
grant execute on function public.fn_record_payment(uuid[],numeric[],numeric,timestamptz,uuid) to authenticated;

-- A correction records counted cash; it is not permission to spend salary.
-- Cashier withdrawals/coverage still reserve all unpaid compensation. Admin
-- corrections may go below that reservation, but never below zero cash.
do $$
declare definition text; previous_guard text; corrected_guard text;
begin
 definition:=pg_get_functiondef('public.fn_pondo_entry(numeric,text,text,uuid)'::regprocedure);
 previous_guard:='if p_amount<0 and coalesce((select sum(amount) from pondo_ledger where area_id=a),0)+p_amount<app.compensation_reserved(a)';
 corrected_guard:='if p_amount<0 and coalesce((select sum(amount) from pondo_ledger where area_id=a),0)+p_amount<(case when p_kind=''correction'' then 0 else app.compensation_reserved(a) end)';
 if position(previous_guard in definition)=0 then
  raise exception 'Reserve entry implementation changed; review compensation protection before applying';
 end if;
 execute replace(definition,previous_guard,corrected_guard);
end $$;
commit;
