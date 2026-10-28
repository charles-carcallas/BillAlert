-- Save as "BA 90 - Verify beta". READ ONLY.
select p.username,p.role,p.account_status,p.staff_enabled,c.consumer_no,c.contact_number,
 c.meter_serial_no,c.account_status as household_status
from public.profiles p left join public.consumers c on c.profile_id=p.id
where p.area_id=(select area_id from public.profiles where username='mario.ombajin')
and p.account_status='active' order by p.role,p.username;

select p.username,b.bill_no,b.status,b.total_amount,b.balance,b.due_date,
 r.previous_reading,r.current_reading,r.consumption,s.route,s.state,s.referred_at
from public.bills b join public.consumers c on c.id=b.consumer_id
left join public.profiles p on p.id=c.profile_id
join public.meter_readings r on r.id=b.meter_reading_id
left join public.bill_settlements s on s.bill_id=b.id
where c.area_id=(select area_id from public.profiles where username='mario.ombajin') order by b.bill_no;

select kind,reason,amount from public.pondo_ledger
where area_id=(select area_id from public.profiles where username='mario.ombajin') order by occurred_at;

select channel,status,count(*) from public.notifications n join public.consumers c on c.id=n.consumer_id
where c.area_id=(select area_id from public.profiles where username='mario.ombajin') group by channel,status;

select 'active_households_without_login' as issue,count(*) from public.consumers c
where c.area_id=(select area_id from public.profiles where username='mario.ombajin')
and c.account_status='active' and c.profile_id is null
union all select 'active_logins_without_household',count(*) from public.profiles p
where p.area_id=(select area_id from public.profiles where username='mario.ombajin') and p.account_status='active'
and not exists(select 1 from public.consumers c where c.profile_id=p.id and c.account_status='active');
