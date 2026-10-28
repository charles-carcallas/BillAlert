-- READ ONLY. Run after installing the reserve-credit migration.
-- These receipts have rounding without a matching automatic credit. They may
-- already be included in opening cash, contributions or corrections. Do NOT
-- add this total to the fund without reconciling the physically held cash.
with regular_receipts as (
 select p.transaction_id, h.area_id, h.receipt_no,
        min(h.paid_at) as collected_at,
        sum(h.amount_paid-coalesce(h.boheco_share,h.amount_paid)) as rounding_received
 from public.v_payment_history h
 join public.payments p on p.id=h.payment_id
 where h.collection_kind='regular'
 group by p.transaction_id,h.area_id,h.receipt_no
), credited as (
 select transaction_id,sum(amount) as automatic_credit
 from public.pondo_ledger where kind='rounding'
 group by transaction_id
)
select r.area_id,r.receipt_no,r.collected_at,r.rounding_received,
       coalesce(c.automatic_credit,0) as automatic_credit,
       r.rounding_received-coalesce(c.automatic_credit,0) as amount_to_reconcile
from regular_receipts r left join credited c using(transaction_id)
where r.rounding_received>coalesce(c.automatic_credit,0)
order by r.area_id,r.collected_at,r.receipt_no;
