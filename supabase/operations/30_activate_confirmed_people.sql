-- Save as "BA 30 - Confirmed people PREVIEW".
-- Run the account helper first, then COMMIT the reviewed 20 reset.
-- Preserves passwords and all household links. Disables other area logins;
-- does not delete them. Defaults to ROLLBACK; review then change final line.
begin;
set local lock_timeout='5s';
create temp table expected_people(username text,first_name text,last_name text,role public.user_role) on commit drop;
insert into expected_people values
 ('mario.ombajin','Mario','Ombajin','admin'),
 ('ledesman.dormal','Ledesman','Dormal','meter_reader'),
 ('mercedita.gales','Mercedita','Gales','cashier'),
 ('virgilio.busalanan','Virgilio','Busalanan','consumer');
do $$ declare a uuid; actor uuid; begin
 select p.area_id,p.id into strict a,actor from public.profiles p join auth.users u on u.id=p.id
 where p.username='mario.ombajin' and lower(u.email)='mario.ombajin@billalert.local'
 and p.role='admin' and p.account_status='active' and p.staff_enabled;
 perform 1 from public.areas where id=a for update;
 lock table public.profiles,public.consumers in share row exclusive mode;
 if (select count(*) from expected_people e join auth.users u on lower(u.email)=e.username||'@billalert.local'
   join public.profiles p on p.id=u.id and p.username=e.username and p.area_id=a
   join public.consumers c on c.profile_id=p.id and c.area_id=a)<>4 then
   raise exception 'All four exact emails/usernames need linked households in Mario area. Run 00 and account helper.';
 end if;
 if exists(select 1 from public.bills b join public.consumers c on c.id=b.consumer_id where c.area_id=a)
   or exists(select 1 from public.pondo_ledger where area_id=a)
   or exists(select 1 from public.meter_readings m join public.consumers c on c.id=m.consumer_id where c.area_id=a)
 then raise exception 'Run and COMMIT the reviewed transaction reset before changing beta roles.'; end if;
 if exists(select 1 from public.profiles where area_id=a and role='admin' and id<>actor and account_status='active')
 then raise exception 'Another active Admin requires review.'; end if;
 if exists(select 1 from public.president_transfers where area_id=a and status in('pending','accepted'))
 then raise exception 'Finish/cancel pending President transfer first.'; end if;

 -- Remove previous assignments before enabling the confirmed replacements.
 update public.profiles set staff_enabled=false,account_status='inactive'
 where area_id=a and username not in(select username from expected_people);
 update public.consumers c set account_status='inactive'
 where c.area_id=a and not exists(select 1 from public.profiles p join expected_people e using(username) where p.id=c.profile_id);
 -- Allows swaps between the confirmed staff without violating unique indexes.
 update public.profiles set staff_enabled=false where area_id=a and username in
   (select username from expected_people where role<>'admin');
 update public.profiles p set first_name=e.first_name,last_name=e.last_name,role=e.role,
   position_title=case e.role when 'admin' then 'Area President' when 'meter_reader' then 'Meter Reader'
     when 'cashier' then 'Cashier' else null end,
   account_status='active',staff_enabled=(e.role<>'consumer')
 from expected_people e where p.username=e.username and p.area_id=a;
 update public.consumers c set first_name=e.first_name,last_name=e.last_name,account_status='active'
 from public.profiles p join expected_people e using(username) where c.profile_id=p.id and c.area_id=a;
 insert into public.account_events(area_id,actor_id,target_id,action,reason)
 select a,actor,p.id,'beta_confirmed_identity','Confirmed beta roster; other area accounts disabled, not deleted'
 from public.profiles p join expected_people e using(username);
end $$;
select p.username,p.role,p.account_status,p.staff_enabled,c.consumer_no,c.account_status as household_status
from public.profiles p left join public.consumers c on c.profile_id=p.id
where p.area_id=(select area_id from public.profiles where username='mario.ombajin') order by p.username;
rollback;
