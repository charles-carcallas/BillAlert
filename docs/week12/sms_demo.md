# Showing the instructor that the SMS integration works

Week 12 check, 16 September 2026, 1:00–2:30 PM. Everything below runs **in the
app**, against the live Supabase project and the real httpSMS gateway. No SQL
and no terminal during the demo.

**The story in one line:** the Area President posts a bill in BillAlert →
Supabase queues the alerts → a scheduled job calls our `send-sms` function →
httpSMS sends the text from the gateway phone → httpSMS calls our webhook back
→ the row says `sent`.

---

## 0. Before the check

| Check | How |
|---|---|
| Gateway phone (ending 8974) on, charged, online, httpSMS app open | the phone itself |
| TECNO (Elena's SIM, ending 8436) has signal and BillAlert installed | the phone itself |
| Supabase awake | run any query once |
| **Schedule set to every minute** (see below) | SQL, once |
| A household that can still be read this month | query below |
| Laptop | BillAlert in Chrome, plus Supabase dashboard tabs if they ask for proof |

**Set the schedule to every minute, so the demo doesn't wait:**
```sql
select cron.alter_job(
  (select jobid from cron.job where jobname = 'invoke-send-sms'),
  schedule := '* * * * *'
);
select jobname, schedule, active from cron.job;
```

**Who can be used:**
```sql
select c.consumer_no, c.first_name, right(c.contact_number, 4) as number_ends,
       (c.profile_id is not null) as has_login,
       exists (
         select 1 from meter_readings mr
         join billing_cycles bc on bc.id = mr.billing_cycle_id
         where mr.consumer_id = c.id
           and fn_ph_today() between bc.period_start and bc.period_end
       ) as read_this_month
from consumers c where c.contact_number is not null order by c.consumer_no;
```
`read_this_month = false` means that household can go through the whole flow
today.

---

## 1. The demo, entirely in the app (about 3 minutes)

**Say first:** "BillAlert talks to a Supabase backend, and sends SMS through the
httpSMS API. You'll see one posting travel from staff phone to household phone."

1. **Meter Reader** (A31 or Chrome), signed in as `ledesman.dormal`
   - Open the September round, choose the household, enter the present reading,
     save.
   - *Point out:* it refuses a reading lower than last month's, and refuses a
     second reading for the same month. Those rules are enforced by the
     database, not the app.

2. **Area President**, signed in as `mario.ombajin`
   - **Amounts** shows the reading waiting for a figure.
   - Type the amount and due date, review the confirmation, post.
   - The screen says "₱X posted for NAME", and the row leaves the queue.
   - *Point out:* the note under the button — the alert goes out in the app and
     by text, automatically.

3. **The household's phone (TECNO)** — within about a minute
   - The **app notification** "Your bill is ready" appears.
   - The **text message** arrives: *"Hi NAME, your BillAlert bill for September
     2026 is PHP X. Due on DATE. Account …-TUB."*
   - Tap the notification: it opens that bill.

4. **The household's app**, signed in as the consumer
   - **Bill** shows the amount just posted.
   - **Inbox** → open the alert → it shows the bill and its **delivery status**,
     which is what came back from httpSMS.

That is the whole integration: app → Supabase → server function → httpSMS →
phone → webhook → back into the app.

---

## 2. If they ask for proof beyond the phone

- **Network traffic:** BillAlert in Chrome with DevTools → Network. Sign-in and
  posting show as HTTPS requests to `thbnomjwovsdvwulkaub.supabase.co`.
- **The schedule is real:**
  ```sql
  select status, start_time at time zone 'Asia/Manila' as ran_ph
  from cron.job_run_details
  where jobid = (select jobid from cron.job where jobname = 'invoke-send-sms')
  order by start_time desc limit 5;
  ```
- **The function's own log:** Supabase → Edge Functions → `send-sms` →
  Invocations, and `httpsms-webhook` → Invocations, which is httpSMS calling us.
- **Failures are never lost (SYS-04):**
  ```sql
  select status, failed_reason, created_at at time zone 'Asia/Manila' as at_ph
  from notifications where status = 'failed' order by created_at desc limit 5;
  ```

---

## 3. Likely questions

- **"Where is the API key?"** In Supabase's Edge Function secrets, set by hand.
  Never in the app, never in the repository. The app cannot send a text; only
  the server function can.
- **"What if the phone has no signal?"** The row stays `pending` and the next
  run tries again; httpSMS also retries on the gateway phone. A text that
  cannot be sent is recorded as `failed` with its reason.
- **"Why SMS and not only push?"** Households with a keypad phone can't run the
  app. Bills and disconnection notices reach them by text.
- **"How often does it run?"** Every minute today so the demo doesn't wait;
  normally every 15 minutes, which is enough for bills and notices.

---

## 4. If the text is slow during the demo

Keep talking through the Consumer screens; it arrives on the next run. As a
last resort, from PowerShell:
```powershell
curl.exe -s -X POST https://thbnomjwovsdvwulkaub.supabase.co/functions/v1/send-sms -H "x-sms-cron-secret: YOUR_SECRET"
```

---

## 5. After the check

```sql
select cron.alter_job(
  (select jobid from cron.job where jobname = 'invoke-send-sms'),
  schedule := '*/15 * * * *'
);
update settings set predue_reminder_days = 3;
```
