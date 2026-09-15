# Week 12 — Implementation plan

> The SMS workstream below is superseded by
> `docs/week12/sms_delivery_development_plan.md`, which incorporates the
> verified httpSMS response, webhook, durable-claim, and timeout behavior.

**Milestone:** API or device feature integration complete.
**Deliverable:** an integrated application build demonstrating successful
API and device functionality.

Written 15 September 2026, from the repository, the live Supabase project and
the commit history. The Week 11 rule still holds: **a feature counts when it
has been seen working, with evidence, not when the code exists.**

Team, by role: Carcallas (Area President, lead) · Busalanan (Meter Reader) ·
Obiso (Cashier) · Basio (Consumer).

---

## 1. Where we stand

| Integration | State | Evidence so far |
|---|---|---|
| Supabase database, RLS and views | ✅ Verified live | `docs/week11/evidence_log.md` |
| Supabase Auth (username sign-in, forced password change) | ✅ Verified live | Week 11 evidence log |
| Encrypted on-device cache (SQLCipher + secure storage) | ✅ Working | `test/data/encryption_test.dart` |
| Edge Functions `create-staff-account`, `reset-account-password`, `create-household-login` | ⚠️ Deployed 15 Sep, never used from the app | CLI deploy output |
| Migration `12_household_logins.sql` | ⚠️ Written, not confirmed applied | — |
| New Consumer creates household **and** sign-in, `BillAlert####` passwords, meter number | ⚠️ Built, 269 tests pass, **uncommitted**, never on a device | `flutter test` |
| Fingerprint / PIN unlock (`local_auth`) | ⚠️ Built and unit-tested, **never compiled for Android** | commit `073104d` |
| Phone notifications (`flutter_local_notifications` + WorkManager) | ⚠️ Built and unit-tested, **never compiled or run** | commits `a546edf`, `a7ba479` |
| Offline outbox → sync on reconnect (NFR-05) | ⚠️ Unit tests only, never on a phone | Week 11 "Not verified" |
| Recording a reading from the app | ⚠️ Only ever driven through PostgREST | Week 11 "Not verified" |
| **SMS gateway (SYS-01 / SYS-04, ADM-12–14)** | ❌ **Not built.** Disconnection notices queue `sms` rows that nothing sends; overdue notices are never queued | — |
| Release APK | ❌ Last built 10 Sep, before every Android change above | `build/app/outputs` |

---

## 2. Workstream 0 — Before anything else

| # | Task | Owner | Done when |
|---|---|---|---|
| 0.1 | **Regenerate the httpSMS API key** at httpsms.com/settings. The old one is in the public history of the TEBANS repository. Put the new key in TEBANS's SMS settings page and its `.env.local`. | Carcallas | The old key returns 401 |
| 0.2 | Confirm migration 12 is applied: `select proname from pg_proc where proname in ('fn_check_household_login','fn_create_household_login');` returns 2 rows | Carcallas | 2 rows |
| 0.3 | Commit the household sign-in, automatic password and meter number work | Carcallas | Clean `git status` |

---

## 3. Workstream A — SMS through httpSMS

The one feature left to **build**. It uses the same httpSMS account and
Android gateway phone as TEBANS, and the same API TEBANS already calls:

```
POST https://api.httpsms.com/v1/messages/send
x-api-key: <key>            ← a Supabase secret, never in the app or a SQL file
{ "from": "+639…", "to": "+639…", "content": "…" }
→ 202 Accepted, message id at data.id
```

### How it fits together

```
fn_issue_disconnection_notice ──┐
fn_queue_overdue_notices (13) ──┼──▶ notifications (channel = sms, status = pending)
                                │
pg_cron, every 15 min ──▶ send-sms Edge Function ──▶ httpSMS API ──▶ gateway phone ──▶ consumer
                                                          │
          httpsms-webhook Edge Function ◀─────────────────┘
          message.phone.sent / .delivered / message.send.failed / .expired
```

**Accepted is not sent.** httpSMS accepts a message the moment it is queued,
but the phone sends it later and can still fail. So a row stays `pending`
with the gateway's message id until the webhook says `sent` or `failed`. This
is what SYS-04 asks for: a failure is recorded with its reason, never lost.

### Tasks

| # | Task | Owner |
|---|---|---|
| A1 | **Supabase secrets** (dashboard → Edge Functions → Secrets): `HTTPSMS_API_KEY` (the new key from 0.1), `HTTPSMS_PHONE_NUMBER` (the gateway phone, `+639…`), `HTTPSMS_WEBHOOK_SIGNING_KEY` (any long random string), `SMS_CRON_SECRET` (another). Set by a person, not by code. | Carcallas |
| A2 | **Migration `13_sms_delivery.sql`**, all server-only (`service_role`): <br>• `notifications.gateway_message_id` (unique when set) and `delivered_at` <br>• `fn_queue_overdue_notices()` reads `v_due_for_overdue_notice`, renders the message from `settings.sms_template`, and queues each notice once through `fn_queue_notification` on `settings.overdue_channel` <br>• `fn_claim_sms_batch(limit)` claims pending SMS rows not yet handed to the gateway, with `for update skip locked` so two runs never send the same row, and respects `settings.batch_size` <br>• `fn_record_sms_handoff(…)` stores the gateway id, or marks the row failed with the gateway's reason <br>• `fn_apply_sms_event(…)`: sent → `status = sent`, `sent_at`; delivered → `delivered_at`; failed or expired → `status = failed`, `failed_reason` <br>• enable `pg_cron` and `pg_net`, keep the project URL and `SMS_CRON_SECRET` in Vault, and schedule `send-sms` every 15 minutes | Carcallas |
| A3 | **Edge Function `send-sms`**: refuses a call without `SMS_CRON_SECRET`; queues today's overdue notices; claims a batch; posts each to httpSMS, sending the notification id as `request_id` (confirm the parameter) and waiting `settings.batch_delay_ms` between messages. A 4xx marks the row failed with the reason. A network error or 5xx leaves it pending for the next run, up to `retry_count` 3 (already a CHECK). | Carcallas |
| A4 | **Edge Function `httpsms-webhook`**, deployed with `--no-verify-jwt` because httpSMS does not send a Supabase token: verifies the HS256 JWT in `Authorization` with `HTTPSMS_WEBHOOK_SIGNING_KEY`; reads `X-Event-Type`; takes the message id from `data.id` (`data.message_id` for expired) and the reason from `data.error_message`; applies `fn_apply_sms_event`; answers 2xx even for an unknown id so httpSMS does not retry forever. | Carcallas |
| A5 | **httpSMS dashboard**: add the webhook `https://thbnomjwovsdvwulkaub.supabase.co/functions/v1/httpsms-webhook` for the four events, with the signing key from A1. Optionally add `phone.heartbeat.offline` to warn when the gateway phone drops. | Carcallas |
| A6 | **SQL test** `supabase/tests/sms_delivery_test.sql`: a row is claimed once; an overdue bill is queued once; a failure has a reason; a household with no number fails at queue time. Rolls back. | Carcallas |
| A7 | **Live test** on a team phone: serve a disconnection notice in the app, receive the SMS, and see the row go `pending → sent → delivered`. | Carcallas + Basio |

**Deploy:** `npx supabase functions deploy send-sms --project-ref thbnomjwovsdvwulkaub`,
then the same for `httpsms-webhook --no-verify-jwt`.

### Done when

- A disconnection notice served from the app reaches the consumer's phone
  within 15 minutes, and its `notifications` row reads `sent` with `sent_at`.
- A household without a mobile number shows `failed` with the reason. No
  row goes missing.
- An overdue bill on due date + `overdue_days_after` is queued exactly once,
  however many times the job runs that day.

### The gateway phone

- It stays plugged in, on Wi-Fi or data, with battery optimisation **off**
  for the httpSMS app. Otherwise messages wait.
- Load an unlimited-text promo. Each SMS is charged to that SIM.
- It is shared with TEBANS. httpSMS paces at 10 messages a minute per phone
  by default, and both apps share that.
- Messages come from the phone's own number, not a "BillAlert" sender name.

---

## 4. Workstream B — The Android build

This blocks everything that has to be seen on a phone.

| # | Task | Owner | Done when |
|---|---|---|---|
| B1 | `flutter build apk --release --dart-define-from-file=env.json` on a developer machine | Carcallas | `app-release.apk` is newer than today's commits |
| B2 | Fix whatever Gradle refuses. Core library desugaring, `FlutterFragmentActivity` and the AppCompat themes have never been compiled. | Carcallas | Build succeeds |
| B3 | Install on one phone per role, not the gateway phone | Everyone | All four roles sign in |

---

## 5. Workstream C — Device verification

Run on the APK from B, against the live project. For each check, record the
date, what was done, and the row id or screenshot in the evidence log.

| Check | Requirement | Owner | Passes when |
|---|---|---|---|
| Reading saved with no signal, survives the app being closed, syncs on reconnect | NFR-05, MTR-12 | Busalanan | `meter_readings` row whose `captured_at` is before the sync time |
| Reading recorded from the app, never done before | FR-21a | Busalanan | Unpriced bill appears for the consumer |
| Area President posts an amount; consumer's phone shows a notification; tapping it opens the bill | FR-13, CON-05 | Carcallas + Basio | Notification seen, bill opens |
| Due-date reminder scheduled for 08:00, `predue_reminder_days` before due | ADM-16 | Basio | Reminder appears |
| New Consumer creates the household and its sign-in; the household signs in with `BillAlert####` and must choose a new password | ADM-03, MTR-04, GEN-04 | Carcallas + Basio | New household reaches its bill screen |
| Reset a forgotten password; the person is forced to change it | — | Carcallas | Old password refused, new one works |
| Create a staff account (expect "Assignment blocked" in Area 3) | FR-31 | Carcallas | The server's message appears |
| Fingerprint unlock, and the Profile switch on and off | GEN auth | Basio | Restored session held until the fingerprint |
| Cashier collects; consumer sees the receipt | FR-30, CON-03 | Obiso + Basio | Receipt number on both phones |
| SMS reaches a phone (Workstream A, A7) | SYS-01, SYS-04 | Carcallas + Basio | SMS received, row `sent` |

---

## 6. Workstream D — Evidence

| # | Task | Owner |
|---|---|---|
| D1 | `docs/week12/evidence_log.md` in the Week 11 format: check, evidence, date, row ids | Each owner writes their own rows |
| D2 | Update the requirements audit: FR-31, MTR-04 and SYS-01/04 have moved; ADM-12–14 become httpSMS | Carcallas |
| D3 | Screenshots or a short screen recording per integration, for the milestone submission | Everyone |

---

## 7. Suggested order

1. **Workstream 0**: rotate the key, confirm migration 12, commit.
2. **B1–B2**: build the APK. If Gradle fails, that is the most important
   thing to learn early.
3. **A1–A5**: SMS, while the role owners start C on the new APK.
4. **C**: device checks, in parallel by role.
5. **A6–A7, D**: prove SMS live, write the evidence, build the final APK.

## 8. Risks

| Risk | What we do |
|---|---|
| The APK does not build | B comes before everything else |
| The old httpSMS key is used by someone else before it is rotated | 0.1 today |
| The gateway phone is offline, so SMS sits pending | Plugged in, battery optimisation off, optional heartbeat webhook |
| The carrier flags bulk texts | Small batches, `batch_delay_ms` between messages |
| A consumer has no mobile number | Expected: a `failed` row with the reason (SYS-04) |
| `pg_cron` / `pg_net` not enabled | Enable under Database → Extensions before A2 |
