-- READ ONLY: run before any backfill. No phones, credentials or Auth hashes.
-- Review both lists together: a household may belong to an existing unlinked
-- staff login. Link that login in the app; do NOT create a duplicate for it.
select c.id as household_id, c.consumer_no, c.first_name, c.last_name,
       c.area_id, 'household.' || replace(c.id::text,'-','') as username
from public.consumers c
where c.profile_id is null and c.account_status='active'
order by c.area_id,c.consumer_no;

select p.id as profile_id,p.username,p.first_name,p.last_name,p.role,
       p.staff_enabled,p.account_status,p.area_id
from public.profiles p
where not exists(select 1 from public.consumers c where c.profile_id=p.id)
order by p.area_id,p.role,p.username;

-- Expected after reviewed completion: no active login without a household,
-- and no active household without a login. Retired accounts can remain.
select 'active_households_without_login' as issue,count(*) as count
from public.consumers where account_status='active' and profile_id is null
union all
select 'active_logins_without_household',count(*) from public.profiles p
where p.account_status='active' and not exists(select 1 from public.consumers c where c.profile_id=p.id);
