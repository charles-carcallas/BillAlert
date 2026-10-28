-- LOCAL TEST FIXTURE ONLY. Never run in Supabase.
do $$ begin
 if current_database() not like 'billalert_beta_kit_%' then raise exception 'Disposable beta-kit database required'; end if;
end $$;
create table if not exists auth.users(id uuid primary key,email text);
insert into auth.users(id,email) select id,username||'@billalert.local' from public.profiles on conflict(id) do nothing;
create schema if not exists cron;
create table if not exists cron.job(jobid bigint primary key,jobname text unique,active boolean);
create table if not exists cron.job_run_details(jobid bigint,status text);
create or replace function cron.alter_job(job_id bigint,active boolean) returns void language sql as $$
 update cron.job set active=$2 where jobid=$1
$$;
insert into cron.job values(1,'invoke-send-sms',true),(2,'billalert-billing-cutoffs',false) on conflict do nothing;
insert into public.consumers(consumer_no,profile_id,first_name,last_name,area_id,created_by)
select 'BETA-TEST-'||username,id,first_name,last_name,area_id,id from public.profiles
where username in('mario.ombajin','ledesman.dormal','mercedita.gales')
and not exists(select 1 from public.consumers where profile_id=profiles.id);
-- Snapshot identities and other-area rows before running the operational kit.
create schema if not exists beta_test;
create table beta_test.before_identity as select id,email from auth.users;
create table beta_test.before_links as select id,profile_id from public.consumers;
create table beta_test.other_area as
select 'profiles' as tbl,to_jsonb(p) as row from public.profiles p where area_id='11111111-0000-0000-0000-00000000000b'
union all select 'consumers',to_jsonb(c) from public.consumers c where area_id='11111111-0000-0000-0000-00000000000b'
union all select 'bills',to_jsonb(b) from public.bills b join public.consumers c on c.id=b.consumer_id where c.area_id='11111111-0000-0000-0000-00000000000b';
