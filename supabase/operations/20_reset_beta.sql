-- Save as "BA 20 - Reset beta PREVIEW". READ README BEFORE APPLYING.
-- All transactional data in Mario's area is removed; accounts/links remain.
-- Defaults to ROLLBACK. Change ONLY the final ROLLBACK to COMMIT after review.
begin;
set local lock_timeout='5s';
set local statement_timeout='90s';

create temp table beta_scope on commit drop as
 select p.id as admin_id,p.area_id from public.profiles p join auth.users u on u.id=p.id
 where p.username='mario.ombajin' and lower(u.email)='mario.ombajin@billalert.local'
 and p.role='admin' and p.account_status='active' and p.staff_enabled;
do $$ begin
 if (select count(*) from beta_scope)<>1 then raise exception 'Expected Mario as active Admin.'; end if;
 if exists(select 1 from public.profiles where area_id=(select area_id from beta_scope)
   and role='admin' and account_status='active' and id<>(select admin_id from beta_scope)) then
   raise exception 'Another Admin exists in this area. Inspect before resetting.';
 end if;
 if to_regclass('app.beta_job_pause') is null then raise exception 'Run 10_pause_jobs first.'; end if;
 if (select count(*) from app.beta_job_pause)<>2 or exists(select 1 from cron.job
   where jobname in ('invoke-send-sms','billalert-billing-cutoffs') and active) then
   raise exception 'Both jobs must be paused.';
 end if;
 if exists(select 1 from cron.job_run_details d join cron.job j using(jobid)
   where j.jobname in ('invoke-send-sms','billalert-billing-cutoffs') and d.status='running') then
   raise exception 'A job is still running. Wait for completion.';
 end if;
 if exists(select 1 from public.president_transfers where area_id=(select area_id from beta_scope)
   and status in ('pending','accepted')) then raise exception 'Finish/cancel the pending President transfer first.'; end if;
 if exists(select 1 from public.notifications n join public.consumers c on c.id=n.consumer_id
   where c.area_id=(select area_id from beta_scope) and n.channel='sms'
   and (n.dispatch_state in('claimed','uncertain') or (n.dispatch_state='accepted' and n.status='pending'))) then
   raise exception 'An SMS is in flight or has an uncertain outcome. Reconcile delivery before resetting.';
 end if;
end $$;

-- Serialize with app operations. Other areas are not reset.
select 1 from public.areas where id=(select area_id from beta_scope) for update;
lock table public.profiles, public.consumers in share row exclusive mode;
create temp table beta_households on commit drop as
 select id from public.consumers where area_id=(select area_id from beta_scope);
create temp table beta_bills on commit drop as
 select id from public.bills where consumer_id in(select id from beta_households);
create temp table beta_notices on commit drop as
 select id from public.disconnection_notices where consumer_id in(select id from beta_households);

-- Private row archive (not a replacement for a full database backup).
create table if not exists app.beta_reset_archive (
 run_id uuid not null, archived_at timestamptz not null default now(),
 area_id uuid not null, source_table text not null, row_data jsonb not null
);
alter table app.beta_reset_archive enable row level security;
revoke all on app.beta_reset_archive from public,anon,authenticated,service_role;
create temp table beta_run on commit drop as select gen_random_uuid() as id;
create temp table beta_targets(seq int,table_name text,predicate text) on commit drop;
insert into beta_targets values
 (1,'app.settlement_corrections','area_id=(select area_id from beta_scope)'),
 (2,'public.reader_compensation','area_id=(select area_id from beta_scope)'),
 (3,'public.boheco_payment_evidence','area_id=(select area_id from beta_scope)'),
 (4,'public.settlement_audit','area_id=(select area_id from beta_scope)'),
 (5,'public.bill_settlements','area_id=(select area_id from beta_scope)'),
 (6,'public.pondo_ledger','area_id=(select area_id from beta_scope)'),
 (7,'public.boheco_trips','area_id=(select area_id from beta_scope)'),
 (8,'public.overdue_collection_approvals','bill_id in(select id from beta_bills)'),
 (9,'public.overdue_collection_audit','bill_id in(select id from beta_bills)'),
 (10,'app.post_amount_operations','bill_id in(select id from beta_bills)'),
 (11,'public.notifications','consumer_id in(select id from beta_households)'),
 (12,'public.notice_bill_items','notice_id in(select id from beta_notices)'),
 (13,'public.disconnection_notices','id in(select id from beta_notices)'),
 (14,'public.payments','consumer_id in(select id from beta_households)'),
 (15,'public.payment_transactions','area_id=(select area_id from beta_scope)'),
 (16,'public.remit_handovers','area_id=(select area_id from beta_scope)'),
 (17,'public.bills','id in(select id from beta_bills)'),
 (18,'public.meter_readings','consumer_id in(select id from beta_households)'),
 (19,'public.reader_waiver_assignments','area_id=(select area_id from beta_scope)'),
 (20,'app.staff_alert_deliveries','alert_id in(select id from public.staff_alerts where area_id=(select area_id from beta_scope))'),
 (21,'public.staff_alerts','area_id=(select area_id from beta_scope)');

do $$ declare t record; fk record; join_sql text; outside_scope boolean; begin
 for t in select * from beta_targets order by seq loop
   execute format('lock table %s in share row exclusive mode',t.table_name::regclass);
 end loop;
 -- Fail closed if a future migration introduces another dependent table.
 if exists(select 1 from pg_constraint c where c.contype='f'
   and c.confrelid in(select table_name::regclass from beta_targets)
   and c.conrelid not in(select table_name::regclass from beta_targets)) then
   raise exception 'Schema has new dependent tables; update this reset before using it.';
 end if;
 -- A corrupt cross-area relationship must not be cascaded away unnoticed.
 for fk in select k.conname,k.conkey,k.confkey,k.conrelid,k.confrelid,
   parent.predicate as parent_predicate,child.predicate as child_predicate
   from pg_constraint k join beta_targets parent on parent.table_name::regclass=k.confrelid
   join beta_targets child on child.table_name::regclass=k.conrelid where k.contype='f' loop
   select string_agg(format('q.%I=p.%I',ca.attname,pa.attname),' and ') into join_sql
   from unnest(fk.conkey,fk.confkey) cols(child_col,parent_col)
   join pg_attribute ca on ca.attrelid=fk.conrelid and ca.attnum=cols.child_col
   join pg_attribute pa on pa.attrelid=fk.confrelid and pa.attnum=cols.parent_col;
   execute format('select exists(select 1 from %s q join (select * from %s where %s) p on %s
     where q.ctid not in(select ctid from %s where %s))',fk.conrelid::regclass,
     fk.confrelid::regclass,fk.parent_predicate,join_sql,fk.conrelid::regclass,fk.child_predicate)
     into outside_scope;
   if outside_scope then raise exception 'Cross-area/dependency mismatch at %. Nothing reset.',fk.conname; end if;
 end loop;
 for t in select * from beta_targets order by seq loop
   execute format('insert into app.beta_reset_archive(run_id,area_id,source_table,row_data)
     select (select id from beta_run),(select area_id from beta_scope),%L,to_jsonb(x)
     from %s x where %s',t.table_name,t.table_name::regclass,t.predicate);
 end loop;
 -- Archive retained accounts too, before activation/deactivation changes.
 insert into app.beta_reset_archive(run_id,area_id,source_table,row_data)
 select (select id from beta_run),p.area_id,'public.profiles',to_jsonb(p)
 from public.profiles p where p.area_id=(select area_id from beta_scope);
 insert into app.beta_reset_archive(run_id,area_id,source_table,row_data)
 select (select id from beta_run),c.area_id,'public.consumers',to_jsonb(c)
 from public.consumers c where c.id in(select id from beta_households);
end $$;

-- Historical waived test bills are immutable in normal app use.
-- Temporarily bypass ONLY that named trigger under the transaction's table lock.
-- Rollback restores trigger state as well as data if any statement fails.
do $$ begin
 if not exists(select 1 from pg_trigger where tgrelid='public.bills'::regclass
   and tgname='bill_apply_reader_coverage' and tgenabled='O') then
   raise exception 'Unexpected coverage trigger state. Inspect before resetting.';
 end if;
end $$;
alter table public.bills disable trigger bill_apply_reader_coverage;
do $$ declare t record; begin
 for t in select * from beta_targets order by seq loop
   execute format('delete from %s where %s',t.table_name::regclass,t.predicate);
 end loop;
end $$;
alter table public.bills enable trigger bill_apply_reader_coverage;

insert into public.account_events(area_id,actor_id,action,reason,details)
select area_id,admin_id,'beta_transaction_reset','User-run beta reset; identities and links preserved',
 jsonb_build_object('archive_run',(select id from beta_run)) from beta_scope;
select source_table,count(*) as archived_rows from app.beta_reset_archive
where run_id=(select id from beta_run) group by source_table order by source_table;
select (select id from beta_run) as archive_run,'PREVIEW unless final statement is COMMIT' as mode;
rollback;
