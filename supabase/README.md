# Supabase — the database of record

These files are the source of truth for the BillAlert database. They used to
be duplicated under
`04_Phase2_Build/Week10_DataModel/sql/` in the coursework folder; that copy
drifted, a stale `03_views.sql` was deployed from it by mistake, and the two
sets have now been merged here. That folder holds only a pointer back to this
one.

## Run order

Apply to a fresh database in this order:

| File | What it does |
|---|---|
| `migrations/01_schema.sql` | tables, enums, triggers, sequences |
| `migrations/02_functions.sql` | the `app.*` session helpers and the five transactional app functions |
| `migrations/03_views.sql` | the twelve `v_` views, **and `security_invoker` on every one** |
| `migrations/04_rls.sql` | row-level security policies |
| `migrations/05_seed.sql` | reference data, then a fixture section |
| `migrations/07_api_grants.sql` | lets `anon` and `authenticated` enter the `app` schema |
| `migrations/08_calendar_cycles.sql` | creates billing cycles from calendar months without pricing bills |
| `migrations/09_staff_accounts.sql` | server-only profile helper for Meter Reader and Cashier account creation |
| `migrations/10_consumer_contact_number.sql` | lets a consumer update only their own household SMS number through a narrow authenticated function |
| `migrations/11_account_password_reset.sql` | server-only rules for an Area President resetting a forgotten password in their own area |
| `migrations/12_household_logins.sql` | server-only rules for an Area President giving a household in their own area a sign-in (MTR-04) |
| `migrations/13_sms_delivery.sql` | SMS delivery tracking: the number each text goes to, claim/accept/sent states, and the server-only functions `send-sms` and `httpsms-webhook` call |
| `migrations/14_bill_sms.sql` | bill-ready alerts also go out as a text, next to the app alert, so keypad phones are not left out |
| `scheduling/sms_cron.sql` | runs `send-sms` every 15 minutes with `pg_cron` — apply last, see below |

`07` is not optional. Every policy calls a helper in the `app` schema, and
without the grant every request fails with
`401 permission denied for schema app` — which surfaces in the app as a silent
bounce back to the login screen.

Staff creation enters through the authenticated `create-staff-account` Edge
Function. It uses Supabase's Auth Admin API, then calls the `SECURITY DEFINER`
helper in `09` to create a Meter Reader or Cashier profile in the caller's own
area. The helper is executable only by `service_role`; neither it nor the
service-role key is exposed to the Flutter client.

Deploy the function after applying migration `09`:

```sh
supabase functions deploy create-staff-account
```

Password resets work the same way. An Area President resets a forgotten
password through the authenticated `reset-account-password` Edge Function.
It checks the rules in `11` — the caller's own area only, a Meter Reader,
Cashier or household login, never another Area President or themselves —
then requires the account to choose a new password at its next sign-in, and
only then sets the temporary password with the Auth Admin API. Deploy it after
applying migration `11`:

```sh
supabase functions deploy reset-account-password
```

Household sign-ins (MTR-04) follow the same pattern. New Consumer saves the
household record, then gives it a sign-in in the same step through the
authenticated `create-household-login` Edge Function, which also serves
households added before that. It checks the rules
in `12` — an active household in the caller's own area, with no sign-in yet,
and a free username — before it creates the auth user, then links a consumer
profile to the household that must choose a new password at first sign-in.
Deploy it after applying migration `12`:

```sh
supabase functions deploy create-household-login
```

### SMS delivery (httpSMS)

Texts go out through [httpSMS](https://httpsms.com), which sends them from an
Android phone running its app. Nothing in the Flutter app sends a text: the
database queues them, and two Edge Functions do the rest.

- `send-sms` claims queued texts and hands them to httpSMS. `pg_cron` calls it
  every 15 minutes with an `x-sms-cron-secret` header. When httpSMS refuses a
  text, the function log shows why, with phone numbers cut to their last 4
  digits.
- `httpsms-webhook` is called by httpSMS when the phone reports a text sent,
  delivered, failed or expired. It checks the HS256 token httpSMS signs.

Neither is called by the app, and both check their own credentials, so deploy
them without Supabase's JWT check:

```sh
supabase functions deploy send-sms --no-verify-jwt
supabase functions deploy httpsms-webhook --no-verify-jwt
```

Edge Function secrets — set these in the dashboard, never in a file:

| Secret | Value | Mistake that cost time |
|---|---|---|
| `HTTPSMS_API_KEY` | the httpSMS **account** API key, `uk_…` | a phone API key (`pk_…`) is refused with `401` |
| `HTTPSMS_PHONE_NUMBER` | the sending phone, as `+63…` | `09…` is refused |
| `HTTPSMS_WEBHOOK_SIGNING_KEY` | the same value as the signing key on the httpSMS webhook | |
| `SMS_CRON_SECRET` | any random value — also stored in Vault under the same name | |

The webhook has to be added in httpSMS by hand. Use this function's URL, the
signing key above, and only the events `message.phone.sent`,
`message.phone.delivered`, `message.send.failed` and `message.send.expired`
(not `message.phone.received`, which would forward replies people send to the
phone). Select only the sending phone. Without the webhook, texts arrive but stay
`pending` forever.

Last, store `SMS_CRON_SECRET` in Vault and run `scheduling/sms_cron.sql`. Check
the first run after the next quarter hour:

```sql
select status, return_message, start_time from cron.job_run_details order by start_time desc limit 3;
select status_code, content, created from net._http_response order by created desc limit 3;
```

Overdue texts stay off until `settings.sms_overdue_enabled` is set to `true`.
Leave it off until every household's number is real — the seeded sample
numbers belong to nobody in Tubod, and possibly to a stranger.

Bill-ready alerts go out as a text too (`14_bill_sms.sql`), so a household
with only a keypad phone still learns its bill is ready. Posting a bill queues
the app alert and a text copy of it. A household with no number gets a
**failed** copy with the reason, so the Area President can see whose number is
missing. The copy is stored read and left out of the Inbox, so the household
sees the bill once. Every household with a number costs one text per bill. To
stop bill texts, for example when the sending SIM is out of load:

```sql
update settings set billready_sms_enabled = false;
```

`send-sms` takes 5 texts per run. At every 15 minutes that is 20 texts an
hour, so a round of 100 posted bills takes about 5 hours to reach everyone.

If the sending phone reports texts late, httpSMS assumes they were lost and
sends them again, so households get duplicates. Set battery use for the httpSMS
app to Unrestricted on that phone.

There is no `06` migration: `06_tests.sql` is a test suite, and lives in
`tests/`.

## On Supabase specifically

**Do not run the FIXTURE section of `05_seed.sql`.** `profiles.id` is a foreign
key to `auth.users(id)`, and the fixture UUIDs have no logins, so it fails.
Seed the reference data only (settings, holidays, SMS providers, areas), create
the auth users, then insert profiles and consumers keyed to the real
`auth.users` ids.

A consequence worth knowing before writing any SQL that targets Supabase: the
households there do **not** have the fixture UUIDs from `05_seed.sql`. They have
random ids. Look consumers up by `consumer_no`, which is the same in both
places.

## Tests

| File | Where to run it |
|---|---|
| `tests/06_tests.sql` | local Postgres — the 56-case suite |
| `tests/fn_record_meter_reading_rls_test.sql` | local Postgres, or Supabase with one line changed |
| `tests/fn_update_own_contact_number_test.sql` | local Postgres — own-household, validation, and staff-denial checks; rolls back |
| `tests/fn_check_household_login_test.sql` | the Supabase SQL editor is fine here — the rules take the caller as a parameter, so RLS plays no part; rolls back |
| `tests/sms_delivery_test.sql` | Supabase — it looks up live households by `consumer_no`; queueing, claiming and gateway events; rolls back |

Run them against a **local Postgres**, not the Supabase SQL editor. The editor
connects as the table owner, which bypasses every RLS policy, so a suite run
there proves nothing about the rules it is testing.

Two things this project learned the hard way, both worth reading before
trusting a green run:

- `06_tests.sql` runs as `test_app`, which `05_seed.sql` grants the `app`
  schema to. All 56 cases passed while the real API roles could not enter that
  schema at all. The suite was testing the rules, not the grants — see the
  header of `migrations/07_api_grants.sql`.
- Postgres views run as their **owner** unless `security_invoker` is set, so
  the views bypassed RLS no matter who was asking. A signed-in consumer could
  read every household's bills in their area through `v_bill_status`, while the
  `bills` table underneath was correctly returning one row. See the block at
  the foot of `migrations/03_views.sql`.

Both were invisible to the test suite. Neither was a policy bug.
