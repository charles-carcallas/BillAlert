-- Save as "BA 99 - Resume beta jobs". Review 90 first.
-- Restores ORIGINAL active states; never blindly enables every job.
begin;
do $$ declare j record; begin
 if to_regclass('app.beta_job_pause') is null then raise exception 'No saved job state. Inspect cron.job.'; end if;
 if exists(select 1 from app.beta_job_pause p where not exists(select 1 from cron.job jobs where jobs.jobname=p.job_name))
 then raise exception 'A saved job is missing. Inspect before restoring.'; end if;
 for j in select c.jobid,p.was_active from app.beta_job_pause p join cron.job c on c.jobname=p.job_name loop
   perform cron.alter_job(j.jobid,active=>j.was_active);
 end loop;
 delete from app.beta_job_pause;
end $$;
select jobname,active from cron.job where jobname in('invoke-send-sms','billalert-billing-cutoffs');
commit;
