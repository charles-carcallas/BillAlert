-- Read-only rehearsal checks. No secrets, phone numbers or job command bodies.
-- One result table, so the SQL editor displays all checks together.
select 'cron: ' || jobname as item,
       case when active then 'ACTIVE' else 'PAUSED' end as value,
       schedule as detail
from cron.job
union all
select 'bill SMS', billready_sms_enabled::text, 'Expected true during rehearsal' from public.settings where id = 1
union all
select 'bill app alert channel', billready_channel::text, 'Expected push' from public.settings where id = 1
union all
select 'pre-due reminder', predue_reminder_days::text || ' days before due', predue_channel::text from public.settings where id = 1
union all
select 'overdue policy', overdue_enabled::text, overdue_days_after::text || ' days after due; channel ' || overdue_channel::text from public.settings where id = 1
union all
select 'automatic overdue SMS', sms_overdue_enabled::text, 'May stay false for the basic bill/payment rehearsal' from public.settings where id = 1
union all
select 'SMS queue: ' || status::text, count(*)::text, coalesce(dispatch_state, 'no dispatch state')
from public.notifications where channel = 'sms' group by status, dispatch_state
order by item, detail;
