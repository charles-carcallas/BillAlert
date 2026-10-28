-- LEGACY QA reset. Use ../operations/20_reset_beta.sql for the current schema.
-- REVIEW ONLY: run after the pondo migration, in a TEST database.
-- Keep one overdue bill each for these two QA households. No accounts deleted.
-- Download a database backup and reconcile/clear phone outboxes first.
-- Default is ROLLBACK. Inspect results, then change the final line to COMMIT.
begin;
set local lock_timeout='5s';
set local statement_timeout='60s';
create temp table qa_pondo_keep(bill_id uuid primary key) on commit drop;
create temp table qa_pondo_remove(bill_id uuid primary key,reading_id uuid) on commit drop;
create temp table qa_pondo_notices(id uuid primary key) on commit drop;
create table if not exists app.qa_pondo_reset_backup (
 batch text not null,source_table text not null,row_id text not null,
 data jsonb not null,archived_at timestamptz not null default now(),
 primary key(batch,source_table,row_id)
);
revoke all on app.qa_pondo_reset_backup from public,anon,authenticated;
do $reset$
declare
 cashier_username text:='test.tset2';
 keep_accounts text[]:=array['QA02-202610-04','QA02-202610-07'];
 actor uuid; a uuid; wanted numeric; available numeric; credit numeric;
 v record;
begin
 select id,area_id into actor,a from profiles where username=cashier_username
  and role='cashier' and account_status='active' and staff_enabled;
 if actor is null then raise exception 'Choose the current active Cashier username'; end if;
 perform 1 from areas where id=a for update;
 if (select count(*) from consumers where area_id=a and consumer_no=any(keep_accounts) and account_status='active')<>2
 then raise exception 'Both configured QA households must exist in the Cashier area'; end if;
 insert into qa_pondo_keep
 select distinct on(c.id) b.id from bills b join consumers c on c.id=b.consumer_id
 where c.area_id=a and c.consumer_no=any(keep_accounts) and b.balance>0 and b.due_date<fn_ph_today()
 order by c.id,b.due_date,b.id;
 if (select count(*) from qa_pondo_keep)<>2 then raise exception 'Both QA households need an unpaid overdue bill'; end if;
 insert into qa_pondo_remove
 select b.id,b.meter_reading_id from bills b join consumers c on c.id=b.consumer_id
 where c.area_id=a and c.consumer_no ~ '^QA0[12]-' and b.balance>0 and b.due_date<fn_ph_today()
 and not exists(select 1 from qa_pondo_keep k where k.bill_id=b.id);
 perform 1 from bills b where b.id in(select bill_id from qa_pondo_remove) order by b.id for update;
 -- Never delete cash history, verified payments, fund movements or reader waivers.
 if exists(select 1 from payments where bill_id in(select bill_id from qa_pondo_remove))
 or exists(select 1 from bills where id in(select bill_id from qa_pondo_remove) and (amount_paid<>0 or external_paid<>0 or waiver_amount<>0))
 or exists(select 1 from bill_settlements where bill_id in(select bill_id from qa_pondo_remove) and state<>'review')
 or exists(select 1 from pondo_ledger where bill_id in(select bill_id from qa_pondo_remove))
 or exists(select 1 from boheco_payment_evidence where bill_id in(select bill_id from qa_pondo_remove))
 or exists(select 1 from settlement_audit where bill_id in(select bill_id from qa_pondo_remove))
 then raise exception 'Payment/settlement-linked QA records require reconciliation. Nothing was removed'; end if;
 insert into qa_pondo_notices
 select distinct notice_id from notice_bill_items where bill_id in(select bill_id from qa_pondo_remove);
 if exists(select 1 from notice_bill_items where notice_id in(select id from qa_pondo_notices)
  and bill_id not in(select bill_id from qa_pondo_remove))
 then raise exception 'A notice also covers a retained bill. Nothing was removed'; end if;
 -- Archive every row explicitly removed; cascade notification rows are archived too.
 for v in
  select 'bills' as tbl,b.id::text as id,to_jsonb(b) as data from bills b where b.id in(select bill_id from qa_pondo_remove)
  union all select 'meter_readings',r.id::text,to_jsonb(r) from meter_readings r where r.id in(select reading_id from qa_pondo_remove)
  union all select 'disconnection_notices',n.id::text,to_jsonb(n) from disconnection_notices n where n.id in(select id from qa_pondo_notices)
  union all select 'notice_bill_items',i.notice_id::text||':'||i.bill_id::text,to_jsonb(i) from notice_bill_items i where i.notice_id in(select id from qa_pondo_notices)
  union all select 'notifications',n.id::text,to_jsonb(n) from notifications n where n.bill_id in(select bill_id from qa_pondo_remove) or n.disconnection_id in(select id from qa_pondo_notices)
  union all select 'overdue_collection_approvals',x.bill_id::text,to_jsonb(x) from overdue_collection_approvals x where x.bill_id in(select bill_id from qa_pondo_remove)
  union all select 'overdue_collection_audit',x.id::text,to_jsonb(x) from overdue_collection_audit x where x.bill_id in(select bill_id from qa_pondo_remove)
  union all select 'app.post_amount_operations',x.client_uuid::text,to_jsonb(x) from app.post_amount_operations x where x.bill_id in(select bill_id from qa_pondo_remove)
  union all select 'bill_settlements',x.bill_id::text,to_jsonb(x) from bill_settlements x where x.bill_id in(select bill_id from qa_pondo_remove) and x.state='review'
 loop
  insert into app.qa_pondo_reset_backup(batch,source_table,row_id,data)
  values('pondo-test-202610',v.tbl,v.id,v.data) on conflict do nothing;
 end loop;
 delete from disconnection_notices where id in(select id from qa_pondo_notices);
 delete from overdue_collection_approvals where bill_id in(select bill_id from qa_pondo_remove);
 delete from overdue_collection_audit where bill_id in(select bill_id from qa_pondo_remove);
 delete from app.post_amount_operations where bill_id in(select bill_id from qa_pondo_remove);
 delete from bill_settlements where bill_id in(select bill_id from qa_pondo_remove) and state='review';
 delete from meter_readings where id in(select reading_id from qa_pondo_remove);
 -- Seed enough TEST cash for both retained cooperative amounts, with a floor of ₱1,000.
 select greatest(1000,coalesce(sum(greatest(0,coalesce(b.cooperative_amount,b.total_amount)-b.amount_paid)),0)) into wanted
 from bills b join qa_pondo_keep k on k.bill_id=b.id;
 select coalesce(sum(amount),0) into available from pondo_ledger where area_id=a;
 credit:=greatest(0,wanted-available);
 perform set_config('request.jwt.claim.sub',actor::text,true);
 if credit>0 and not exists(select 1 from pondo_ledger where client_uuid='dddddddd-2026-1004-0000-000000000001') then
  perform fn_pondo_entry(credit,case when exists(select 1 from pondo_ledger where area_id=a and kind='opening') then 'contribution' else 'opening' end,
   'TEST ONLY: two-household pondo rehearsal','dddddddd-2026-1004-0000-000000000001');
 end if;
end $reset$;
select c.consumer_no,b.bill_no,b.balance,coalesce(b.cooperative_amount,b.total_amount)-b.amount_paid as boheco_amount
from qa_pondo_keep k join bills b on b.id=k.bill_id join consumers c on c.id=b.consumer_id;
select count(*) as unpaid_test_bills_to_remove from qa_pondo_remove;
select coalesce(sum(amount),0) as available_test_pondo from pondo_ledger where area_id=app.current_area();
rollback;
