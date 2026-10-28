-- Save as "BA 10 - Pause beta jobs". This DOES change job state.
-- Stop testers, sync every device and take a database backup first.
begin;
create table if not exists app.beta_job_pause (
 job_name text primary key, was_active boolean not null,
 paused_at timestamptz not null default now()
);
alter table app.beta_job_pause enable row level security;
revoke all on app.beta_job_pause from public,anon,authenticated,service_role;
do $$ declare j record; begin
 if (select count(*) from cron.job where jobname in
     ('invoke-send-sms','billalert-billing-cutoffs'))<>2 then
   raise exception 'Expected both named jobs. Inspect cron.job before continuing.';
 end if;
 for j in select * from cron.job where jobname in
   ('invoke-send-sms','billalert-billing-cutoffs') loop
   insert into app.beta_job_pause(job_name,was_active) values(j.jobname,j.active)
     on conflict(job_name) do nothing; -- reruns preserve ORIGINAL state
   perform cron.alter_job(j.jobid,active=>false);
 end loop;
end $$;
select * from app.beta_job_pause order by job_name;
commit;
-- Wait for any already-running job to finish before opening 20.
