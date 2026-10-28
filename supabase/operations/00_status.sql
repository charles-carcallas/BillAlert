-- READ ONLY. Save in SQL Editor as "BA 00 - Status".
with expected(username, expected_role) as (values
 ('mario.ombajin','admin'), ('ledesman.dormal','meter_reader'),
 ('mercedita.gales','cashier'), ('virgilio.busalanan','consumer'))
select e.username, e.expected_role, p.role as actual_role, p.account_status,
 p.staff_enabled, c.consumer_no, c.account_status as household_status,
 case when u.id is null then 'Create through account helper'
      when p.id is null then 'Auth exists but profile missing: inspect before continuing'
      when p.username<>e.username then 'Email/username mismatch: inspect'
      when c.id is null then 'Household link missing: inspect'
      when p.area_id is distinct from c.area_id then 'Area mismatch: inspect'
      when p.role::text<>e.expected_role then 'Role update needed'
      else 'Present' end as result
from expected e left join auth.users u on lower(u.email)=e.username||'@billalert.local'
left join public.profiles p on p.id=u.id
left join public.consumers c on c.profile_id=p.id order by e.username;

select to_regclass('public.pondo_one_regular_rounding') is not null as rounding_credit_installed,
 to_regclass('public.reader_compensation') is not null as compensation_installed,
 to_regclass('app.settlement_corrections') is not null as correction_recovery_installed,
 case when to_regprocedure('public.fn_correct_settlement(uuid,text)') is null then false
 else not has_function_privilege('authenticated','public.fn_correct_settlement(uuid,text)','EXECUTE')
 end as legacy_correction_restricted;

select jobname, active from cron.job
where jobname in ('invoke-send-sms','billalert-billing-cutoffs') order by jobname;

select c.account_status, count(*) as households,
 count(*) filter(where c.profile_id is null) as without_login
from public.consumers c join public.profiles a on a.area_id=c.area_id
where a.username='mario.ombajin' group by c.account_status;
