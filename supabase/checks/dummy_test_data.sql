-- LEGACY QA FIXTURES: includes retired approvals/waiver scenarios.
-- Current confirmed-person beta data: ../operations/40_seed_beta_scenarios.sql.
-- BillAlert manual test data. Run the WHOLE file in the Supabase SQL Editor.
-- Adds synthetic records; never deletes or updates existing households/accounts.
-- Requires all migrations through 20261002151432_staff_assignment.sql.
-- Existing Admin/Reader/Cashier logins are used. No Auth users/passwords are created.
-- All new household phone numbers are NULL. Staff in-app alerts WILL be generated.
-- Dates follow the current Philippine month, so the same file works next month.
-- Re-running the same batch is refused, preserving any testing already performed.
-- For an optional dry run, replace the final COMMIT with ROLLBACK.

begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

create temp table billalert_test_cases (
  test_no integer primary key, consumer_no text, scenario text,
  household_id uuid, current_bill uuid, older_bill uuid
) on commit drop;

do $seed$
declare
  -- EDIT ONLY THESE TWO VALUES if needed. Use your existing Admin username.
  admin_username text := 'mario.ombajin';
  batch_label text := 'QA01'; -- Change to QA02 only if you want ANOTHER full batch.
  admin_row public.profiles;
  reader_id uuid;
  cashier_id uuid;
  today date := public.fn_ph_today();
  month_start date := date_trunc('month',public.fn_ph_today())::date;
  previous_month date := (date_trunc('month',public.fn_ph_today())-interval '1 month')::date;
  batch text;
  cycle_id uuid;
  old_cycle_id uuid;
  household_id uuid;
  reading_id uuid;
  bill_id uuid;
  notice_id uuid;
  transaction_id uuid;
  rec record;
  part integer;
  reading_day date;
  opening numeric;
  cooperative numeric;
  rounded numeric;
  due_day date;
  paid numeric;
  paid_bill uuid;
  served timestamptz := now()-interval '1 hour';
begin
  if to_regclass('public.reader_waiver_assignments') is null
     or to_regclass('app.staff_assignment_operations') is null then
    raise exception 'Required migrations are missing. Apply the reviewed lifecycle, BOHECO coverage and staff assignment migrations first.';
  end if;
  if batch_label !~ '^QA[0-9]{2}$' then
    raise exception 'Use a batch label such as QA01 or QA02.';
  end if;
  select * into admin_row from public.profiles
    where username=admin_username and role='admin' and account_status='active' and staff_enabled;
  if not found then raise exception 'No active Area President with username %. Edit admin_username at the top.',admin_username; end if;
  select id into reader_id from public.profiles where area_id=admin_row.area_id
    and role='meter_reader' and account_status='active' and staff_enabled;
  select id into cashier_id from public.profiles where area_id=admin_row.area_id
    and role='cashier' and account_status='active' and staff_enabled;
  if reader_id is null or cashier_id is null then
    raise exception 'Create/assign an active Meter Reader and Cashier in this Admin area using the app, then run this file.';
  end if;
  batch := batch_label||'-'||to_char(month_start,'YYYYMM');
  perform pg_advisory_xact_lock(hashtextextended('billalert-dummy:'||batch,0));
  if exists(select 1 from public.consumers where consumer_no like batch||'-%') then
    raise exception 'Batch % already exists. Nothing changed. Continue testing it; use a new batch_label only for a separate batch.',batch;
  end if;

  -- Reuse real calendar-cycle rows, never replace them or reopen closed cycles.
  insert into public.billing_cycles(cycle_year,cycle_month,period_start,period_end)
  select extract(year from d)::smallint,extract(month from d)::smallint,d,
    (d+interval '1 month'-interval '1 day')::date
  from (values(month_start),(previous_month)) months(d)
  on conflict(cycle_year,cycle_month) do nothing;
  select id into cycle_id from public.billing_cycles
    where cycle_year=extract(year from month_start) and cycle_month=extract(month from month_start)
      and period_start=month_start and period_end=(month_start+interval '1 month'-interval '1 day')::date and not is_closed;
  select id into old_cycle_id from public.billing_cycles
    where cycle_year=extract(year from previous_month) and cycle_month=extract(month from previous_month)
      and period_start=previous_month and period_end=month_start-1 and not is_closed;
  if cycle_id is null or old_cycle_id is null then
    raise exception 'Current/previous billing cycle is closed or has non-calendar dates. No data was added.';
  end if;

  for rec in select * from (values
    (1,'New Reading','Record the first reading online or offline'),
    (2,'Awaiting Amount','Post the cooperative amount and due date'),
    (3,'Current Unpaid','Collect a normal current bill'),
    (4,'Overdue Block','Older debt blocks current payment; request Admin approval'),
    (5,'Partial Payment','Legacy partial payment with real receipt allocation; collect remaining balance'),
    (6,'Paid History','Fully paid bill, receipt and remittance cash'),
    (7,'Active Notice','Unpaid overdue notice; approve, collect and review closure'),
    (8,'Ready To Close','Receipt-backed payment after notice; Admin may close as settled'),
    (9,'Closed Notice','Cancelled notice history; overdue debt is still unpaid'),
    (10,'Due Reminder','Due in the configured number of pre-due reminder days'),
    (11,'Reader Coverage','Unpriced bill for optional reviewed staff household link and BOHECO coverage'),
    (12,'Household Handover','Empty household for login/link/handover testing')
  ) cases(n,label,scenario) loop
    insert into public.consumers(consumer_no,first_name,last_name,area_id,purok,
      meter_serial_no,contact_number,created_by)
    values(batch||'-'||lpad(rec.n::text,2,'0'),'Test',rec.label,admin_row.area_id,
      'Test Purok '||((rec.n-1)%4+1),batch||'-M'||lpad(rec.n::text,2,'0'),null,admin_row.id)
    returning id into household_id;
    insert into billalert_test_cases values(rec.n,batch||'-'||lpad(rec.n::text,2,'0'),rec.scenario,household_id,null,null);
    if rec.n in (1,12) then continue; end if;

    -- Scenario 4 has two bills; 7/8/9 have only last month's overdue bill.
    for part in 0..case when rec.n=4 then 1 else 0 end loop
      reading_day := case when rec.n in (4,7,8,9) and part=0 then previous_month+6 else today end;
      opening := case when part=1 then 100 else 0 end;
      insert into public.meter_readings(consumer_id,billing_cycle_id,previous_reading,
        current_reading,reading_date,captured_at,recorded_by,client_uuid)
      values(household_id,case when reading_day<month_start then old_cycle_id else cycle_id end,
        opening,opening+100,reading_day,reading_day::timestamp at time zone 'Asia/Manila',reader_id,gen_random_uuid())
      returning id into reading_id;
      insert into public.bills(bill_no,consumer_id,billing_cycle_id,meter_reading_id,
        consumption,generated_by,generated_at)
      values(batch||'-B'||lpad(rec.n::text,2,'0')||'-'||part,household_id,
        case when reading_day<month_start then old_cycle_id else cycle_id end,reading_id,
        100,reader_id,reading_day::timestamp at time zone 'Asia/Manila') returning id into bill_id;
      if reading_day<month_start then
        update billalert_test_cases set older_bill=bill_id where test_no=rec.n;
      else
        update billalert_test_cases set current_bill=bill_id where test_no=rec.n;
      end if;
      if rec.n in (2,11) then continue; end if;
      cooperative := case when rec.n=5 then 499.40 when rec.n=6 then 799.40 else 349.40 end;
      rounded := ceil(cooperative);
      due_day := case when reading_day<month_start then month_start-3
        when rec.n=10 then today+(select predue_reminder_days from public.settings where id=1)
        else greatest(month_start+27,today+1) end;
      update public.bills set cooperative_amount=cooperative,total_amount=rounded,
        due_date=due_day,priced_at=reading_day::timestamp at time zone 'Asia/Manila',priced_by=admin_row.id
        where id=bill_id;
      insert into public.notifications(consumer_id,billing_cycle_id,bill_id,notif_type,channel,message_content)
      select household_id,b.billing_cycle_id,bill_id,'bill_ready','push',
        '[TEST DATA] '||public.fn_render_bill_message(bill_id) from public.bills b where b.id=bill_id;
    end loop;

    if rec.n in (7,8,9) then
      insert into public.disconnection_notices(notice_no,consumer_id,reason,served_at,
        earliest_lawful_at,issued_by,client_uuid)
      values(batch||'-N'||rec.n,household_id,'TEST DATA: unpaid demonstration bill',served,
        public.fn_earliest_lawful_disconnection(served),admin_row.id,gen_random_uuid()) returning id into notice_id;
      insert into public.notifications(consumer_id,disconnection_id,notif_type,channel,message_content)
      values(household_id,notice_id,'disconnection','push','[TEST DATA] Demonstration disconnection notice. Open the notice for details.');
      if rec.n=9 then
        update public.disconnection_notices set status='cancelled',closed_at=now(),closed_by=admin_row.id,
          outcome_notes='TEST DATA: cancellation example; debt remains payable' where id=notice_id;
      end if;
    end if;
    if rec.n in (5,6,8) then
      select coalesce(current_bill,older_bill) into paid_bill from billalert_test_cases where test_no=rec.n;
      paid := case rec.n when 5 then 200 when 6 then 800 else 350 end;
      insert into public.payment_transactions(receipt_no,verification_code,consumer_id,area_id,
        cashier_id,total_collected,cash_tendered,change_due,paid_at,client_uuid)
      values(batch||'-R'||rec.n,batch||'-VERIFY-'||rec.n,household_id,admin_row.area_id,
        cashier_id,paid,paid,0,now(),gen_random_uuid()) returning id into transaction_id;
      insert into public.payments(transaction_id,bill_id,consumer_id,amount_paid,received_by,paid_at)
      values(transaction_id,paid_bill,household_id,paid,cashier_id,now());
      update public.bills set amount_paid=paid where id=paid_bill;
    end if;
  end loop;
  -- Postconditions: fail the entire transaction if a fixture is inconsistent.
  if (select count(*) from billalert_test_cases)<>12 then raise exception 'Incomplete fixture'; end if;
  if exists(select 1 from public.bills b join billalert_test_cases t on t.household_id=b.consumer_id
    where b.amount_paid<>coalesce((select sum(p.amount_paid) from public.payments p where p.bill_id=b.id),0)) then
    raise exception 'Payment totals do not reconcile';
  end if;
  if exists(select 1 from public.notifications n join billalert_test_cases t on t.household_id=n.consumer_id
    where n.channel='sms' and n.status='pending') then raise exception 'Unexpected pending SMS'; end if;
  raise notice 'Added %: 12 households, 11 bills, 3 receipts, 3 notices. No login credentials or phone numbers were created.',batch;
end
$seed$;

-- This summary contains only the newly created test records.
select t.consumer_no,t.scenario,
  (select string_agg(b.status::text||' / PHP '||coalesce(b.balance::text,'awaiting amount'),'; ' order by b.due_date nulls last)
    from public.bills b where b.consumer_id=t.household_id) as bills,
  'Create sign-in in Manage accounts > Households if needed' as consumer_access
from billalert_test_cases t order by t.test_no;

commit;
