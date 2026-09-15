-- =====================================================================
-- Phase D — sms_cron.sql
-- =====================================================================

create extension if not exists pg_net;
create extension if not exists pg_cron;

-- Run this once with your own secret:
-- select vault.create_secret('your-secret-here', 'SMS_CRON_SECRET');

-- Unschedule first to avoid duplicate jobs when redeploying
select cron.unschedule(jobid) from cron.job where jobname = 'invoke-send-sms';

select cron.schedule(
  'invoke-send-sms',
  '*/15 * * * *',
  $$
  do $job$
  declare
    v_secret text;
  begin
    select decrypted_secret into v_secret 
    from vault.decrypted_secrets 
    where name = 'SMS_CRON_SECRET';
    
    perform net.http_post(
      url := 'https://thbnomjwovsdvwulkaub.supabase.co/functions/v1/send-sms',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-sms-cron-secret', coalesce(v_secret, '')
      ),
      timeout_milliseconds := 60000
    );
  end;
  $job$;
  $$
);
