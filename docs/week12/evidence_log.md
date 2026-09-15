# Week 12 Evidence Log

The Week 11 rule still holds: **a feature counts when it has been seen
working, with evidence, not when the code exists.**

Verified 15 September 2026. Area 3 — Tubod. Times are Philippine time unless
marked UTC.

Where the evidence came from: the Supabase SQL editor, the Edge Function
invocation logs and cron history in the Supabase dashboard, the httpSMS
dashboard, and the team's test phones. The SMS functions run as `service_role`,
so the SQL editor is the right place to read them. It is **not** evidence
about row-level security, which it bypasses.

Phone numbers are shortened to their last 4 digits here: the gateway phone
ends **8974**, and the two team test phones end **3934** and **8436**.

---

### SMS gateway — httpSMS (Carcallas)

**Setup**

| Check | Evidence | Date |
|---|---|---|
| Migration `13_sms_delivery.sql` applied | `notifications.dispatch_state` exists and `fn_claim_sms_batch` exists: both checks `true` | 15 Sep 2026 |
| Edge Functions deployed | `send-sms` and `httpsms-webhook` deployed with `--no-verify-jwt`; each answered a call without credentials with its own `401 {"ok":false,…}` | 15 Sep 2026 |
| Secrets set by a person, not in any file | `HTTPSMS_API_KEY`, `HTTPSMS_PHONE_NUMBER`, `HTTPSMS_WEBHOOK_SIGNING_KEY`, `SMS_CRON_SECRET` set in the dashboard. The API key was checked against httpSMS by comparing SHA-256 digests, never by printing it | 15 Sep 2026 |
| Leaked TEBANS key no longer in use | the key saved in Supabase has a different digest from the one committed to the TEBANS repository; the owner regenerated it in httpSMS | 15 Sep 2026 |
| Webhook registered in httpSMS | URL `…/functions/v1/httpsms-webhook`, events `message.phone.sent`, `message.phone.delivered`, `message.send.failed`, `message.send.expired`, gateway phone only, with the signing key | 15 Sep 2026 |

**Delivery**

| Check | Evidence | Date |
|---|---|---|
| A refused send is recorded with its reason, never lost (SYS-04) | `bb72350c-f2a2-444d-af93-993940753860` and `dc0f1012-9145-4ea2-aa77-9df597adbf49`: `status=failed`, `failed_reason` "You are not authorized to carry out this request." | 15 Sep 2026 |
| httpSMS accepts a queued text | `send-sms` → `{"ok":true,"summary":{"queued":0,"claimed":1,"accepted":1,"failed":0,"uncertain":0}}` | 15 Sep 2026 |
| The text reaches a phone | `f080b143-ff50-4275-9cda-1e4c0dcb9a1f`, `0fe7561e-05f0-4fb6-869c-a6cf563350a5` and `506f4365-8a33-490f-935d-b9f36bf1b0b8`, accepted 16:46–16:50, received on the test phone | 15 Sep 2026 |
| Status comes back by itself (SYS-01) | `f1314d36-58c8-4013-b712-3b6335df06a4`, queued 18:58, `status=sent`, `sent_at=2026-09-15 11:00:46 UTC` (19:00:46), written by `httpsms-webhook` | 15 Sep 2026 |
| One text, from the gateway number | `f1314d36-…` to the test phone ending 3934 at 18:58 arrived **once**, from the number ending 8974 (as seen on that phone) | 15 Sep 2026 |

**Schedule**

| Check | Evidence | Date |
|---|---|---|
| Safe to switch on | `sms_waiting=0`; `billready_channel=push`, `predue_channel=push`, `overdue_channel=sms`, `sms_overdue_enabled=false`. The seeded sample numbers `+63917555…` were cleared, leaving only the two team test phones | 15 Sep 2026 |
| Cron secret in Vault matches the Edge Function secret | the first 8 hex characters of both SHA-256 digests match | 15 Sep 2026 |
| Job scheduled | `cron.job`: one row, `2 · invoke-send-sms · */15 * * * * · active` | 15 Sep 2026 |
| Job runs and is let in | first run 21:00:00 (`cron.job_run_details` count 1); `net._http_response` `200` `{"ok":true,"summary":{"queued":0,"claimed":0,"accepted":0,"failed":0,…}}` at `13:00:00 UTC` | 15 Sep 2026 |

**Problems found and fixed on the way**

1. **The wrong kind of httpSMS key.** Every send came back `401`. The key saved
   was a phone API key (`pk_…`), which httpSMS's API refuses; it needs the
   account key (`uk_…`). Found by making `send-sms` log httpSMS's refusal body,
   with phone numbers cut to their last 4 digits, and by calling
   `GET /v1/users/me` with the key: `401` for the `pk_` key, `200` for the `uk_`
   key.
2. **The sending number in local format.** `HTTPSMS_PHONE_NUMBER` was saved as
   `09…`. httpSMS needs `+63…`.
3. **No webhook.** Texts arrived but their rows stayed `pending` with no
   `sent_at`. The webhook's invocation log showed that httpSMS had never called
   it, because it had not been added in httpSMS. The three texts from
   16:46–16:50 were later marked `sent` by hand, using their `accepted_at`, not
   by the webhook.
4. **Duplicate texts, and a delivered text marked failed.** The gateway phone
   confirmed late, so httpSMS assumed the text was lost and sent it again.
   Test `8f2b20b0-89be-48d4-b512-45e568b45767` arrived twice and was marked
   `failed` "Provider reported failure" on httpSMS's first expiry. The next
   test, `f1314d36-…` at 18:58, arrived once and ended `sent`. Two changes
   followed, so that a slow confirmation neither duplicates a text nor marks
   it failed:
   - `httpsms-webhook` now ignores an expiry unless httpSMS marks it final
     (`is_final`), and was redeployed;
   - the httpSMS app's battery use on the gateway phone was set to
     Unrestricted.

---

### Bill-ready alerts by text (Carcallas)

**Design change.** Objective 3 kept SMS for overdue and disconnection notices
only, because every text costs load. That left a household with only a keypad
phone no way to learn its bill was ready. From `14_bill_sms.sql`, posting a
bill queues the app alert **and** a text. The text is stored read and left out
of the Inbox, so a household sees the bill once. A household with no number
gets a failed text with its reason. `settings.billready_sms_enabled` switches
bill texts off.

| Check | Evidence | Date |
|---|---|---|
| Migration `14_bill_sms.sql` applied | the test below produced the text row, which only 14 creates | 15 Sep 2026 |
| Posting a bill queues both alerts | a test inside one transaction that rolls itself back, so nothing was saved and nothing was sent. It created a household, recorded a reading of 100, and posted ₱500.00. Result: `sms -> status=pending, state=ready, read=t, to=...1414 \| push -> status=pending, state=-, read=f` | 15 Sep 2026 |
| The text households receive | "Hi Test Household, your BillAlert bill for September 2026 is PHP 500.00. Due on Sep 25, 2026. Account TEST-14." (113 characters, one SMS) | 15 Sep 2026 |

---

### On a phone: reading, posting and both alerts (Carcallas)

The first Android build of the Week 12 code. It is a debug build, not the
release APK, installed with `flutter run` onto a **Samsung Galaxy A31 (Android
12)** and running against the live project. It had to be started from an
ordinary terminal: inside the coding agent's sandbox, Gradle stops with
`Unable to establish loopback connection`.

| Check | Evidence | Date |
|---|---|---|
| App builds and installs on Android | `flutter run -d RR8R200AZMA --dart-define-from-file=env.json` → BillAlert opened on the A31 | 15 Sep 2026 |
| Reading recorded from the app, for the first time (FR-21a) | as `ledesman.dormal`, Virgilio Busalanan `2019-0917-TUB`: `previous_reading=3475.00`, `current_reading=3490.00`, `consumption=15.00`, `recorded_by` resolves to `ledesman.dormal` | 15 Sep 2026 |
| Capture time comes from the device (MTR-12) | `captured_at` 22:10:00.300 is 17 ms *after* `synced_at` 22:10:00.283: the phone's clock ran slightly ahead of the server, as in Week 11 | 15 Sep 2026 |
| Amount posted from the app | as `mario.ombajin`: `BA-202609-000007` → `total_amount=100.00`, `due_date=2026-09-29` | 15 Sep 2026 |
| Phone notification (FR-13, CON-05) | the A31, signed in as `virgilio.busalanan`, showed "Your bill is ready — The amount for your latest bill has been posted. Tap to see it."; `push` row `status=sent`, `sent_at` 22:14:01.364 | 15 Sep 2026 |
| Tapping the notification opens the bill | tapping it opened Virgilio's September 2026 bill | 15 Sep 2026 |
| Bill text reaches the household (SYS-01, `14_bill_sms.sql`) | `sms` row `status=sent`, `sent_at` 22:15:04.188, `is_read=true`. The phone ending 3934 received it at 22:15:06: "Hi Virgilio Busalanan, your BillAlert bill for September 2026 is PHP 100.00. Due on Sep 29, 2026. Account 2019-0917-TUB." | 15 Sep 2026 |

---

### Automated checks

| Check | Evidence | Date |
|---|---|---|
| `flutter analyze` | 7 issues, all in the gitignored `scratch/` | 15 Sep 2026 |
| `flutter test` | **290 passing**, including `test/domain/without_text_copies_test.dart`, and `test/data/consumer_offline_cache_test.dart` showing the Inbox holds a bill once, online and offline | 15 Sep 2026 |
| `supabase/tests/06_tests.sql` TC-18, TC-19, TC-44 updated for the bill text | **not run** — needs a local Postgres | — |

---

### Not verified

- **A disconnection notice served from the app reaching a phone by SMS**
  (Workstream A, A7).
- **`delivered_at`.** No carrier delivery report has come back, so every row
  has `delivered_at` null.
- **Overdue texts.** Switched off (`sms_overdue_enabled=false`), so "queued
  exactly once per bill" has not been seen live.
- **The old TEBANS key returning `401`.** Not tried.
- **`supabase/tests/sms_delivery_test.sql`.** Not run.
- **Urgent due-date alerts** (built 15 Sep; see
  `docs/week12/urgent_due_date_alerts.md`): full screen on Android 14 and
  later, a loud pop-up on Android 13 and older. Not yet seen on a phone. The
  A31 runs Android 12, so it can only show the pop-up.
- **The rest of Workstream C, on a phone:**
  - offline reading and sync;
  - the due-date reminder;
  - New Consumer with its sign-in;
  - password reset;
  - staff account;
  - fingerprint unlock;
  - cashier receipt on both phones.
- **Code state.** Everything above that was built this week is uncommitted on
  `master` as of this entry.
