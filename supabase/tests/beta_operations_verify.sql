-- LOCAL TEST ONLY. Run after COMMIT reset, then COMMIT seed, and 99 resume.
do $$ declare a uuid; begin
 if current_database() not like 'billalert_beta_kit_%' then raise exception 'Disposable beta-kit database required'; end if;
 select area_id into a from profiles where username='mario.ombajin';
 if exists((select id,email from auth.users except select * from beta_test.before_identity)
   union all (select * from beta_test.before_identity except select id,email from auth.users)) then
   raise exception 'Auth identities changed'; end if;
 if exists((select id,profile_id from consumers except select * from beta_test.before_links)
   union all(select * from beta_test.before_links except select id,profile_id from consumers)) then
   raise exception 'Household links changed'; end if;
 if (select count(*) from profiles where area_id=a and account_status='active')<>4 then raise exception 'Wrong active roster'; end if;
 if (select count(*) from bills b join consumers c on c.id=b.consumer_id where c.area_id=a)<>4 then raise exception 'Wrong bill count'; end if;
 if (select count(*) from bill_settlements where area_id=a and route='boheco' and state='awaiting_referral')<>2 then raise exception 'Expected exactly two unreported direct-pay bills'; end if;
 if (select sum(amount) from pondo_ledger where area_id=a)<>2000 then raise exception 'Wrong sample reserve balance'; end if;
 if exists(select 1 from payment_transactions where area_id=a) or exists(select 1 from reader_compensation where area_id=a)
 then raise exception 'Old receipts or salary payouts survived'; end if;
 if exists(select 1 from notifications n join consumers c on c.id=n.consumer_id where c.area_id=a and n.channel='sms')
 then raise exception 'Sample SMS exists'; end if;
 if not exists(select 1 from app.beta_reset_archive where source_table='public.reader_compensation')
 or not exists(select 1 from app.beta_reset_archive where source_table='public.payments')
 then raise exception 'Populated accounting rows were not archived'; end if;
 if not(select active from cron.job where jobname='invoke-send-sms')
 or (select active from cron.job where jobname='billalert-billing-cutoffs') then raise exception 'Original job states not restored'; end if;
 if has_table_privilege('authenticated','app.beta_reset_archive','select')
 or has_table_privilege('anon','app.beta_job_pause','select') then raise exception 'Operator tables exposed'; end if;
 if not exists(select 1 from pg_trigger where tgrelid='bills'::regclass and tgname='bill_apply_reader_coverage' and tgenabled='O')
 then raise exception 'Coverage trigger not restored'; end if;
end $$;
with after_other as (
 select 'profiles' as tbl,to_jsonb(p) as row from public.profiles p where area_id='11111111-0000-0000-0000-00000000000b'
 union all select 'consumers',to_jsonb(c) from public.consumers c where area_id='11111111-0000-0000-0000-00000000000b'
 union all select 'bills',to_jsonb(b) from public.bills b join public.consumers c on c.id=b.consumer_id where c.area_id='11111111-0000-0000-0000-00000000000b'
), differences as (
 (select * from after_other except select * from beta_test.other_area)
 union all (select * from beta_test.other_area except select * from after_other)
)
select 1 / case when count(*)=0 then 1 else 0 end as other_area_unchanged from differences;
select 'PASS: roster, identities, links, archive, sample routes, no SMS, job states and other area' as result;
