# Supabase — the database of record

**Existing project / October 2026 beta:** use [the current operations kit](operations/README.md)
for status checks, the four confirmed member accounts, a previewable transaction reset,
and a small sample dataset. Do not rerun old saved migration or dummy-data queries.
The historical run order below is for building a fresh database, not resetting this one.

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
| `migrations/15_bill_meter_readings.sql` | appends meter readings to bill details; preserves view RLS |
| `migrations/15_sms_event_ordering.sql` | reconciles early webhooks by request ID and prevents late acceptance from resetting final delivery states |
| `migrations/16_cycle_named_by_reading_month.sql` | files each reading and bill under the month it was read |
| `migrations/17_bill_cooperative_amount.sql` | keeps BOHECO's own amount beside the rounded bill (`bills.cooperative_amount`) and adds `boheco_share` to `v_payment_history`, so Remit can split the money collected into BOHECO's part and the Meter Reader's rounding share |
| `migrations/18_remit_handovers.sql` | the Cashier records handing BOHECO's part of the month's money to the Meter Reader (`remit_handovers`, `fn_record_remit_handover`); amounts frozen at the handover |
| `migrations/19_overdue_collection.sql` | REVIEW REQUIRED: overdue approvals, guarded online collection, exact UUID payment/post replay; preserves existing records |
| `migrations/20_staff_alerts.sql` | REVIEW REQUIRED: recipient-scoped staff inbox, event triggers and per-device notification claims |
| `migrations/20261002034514_disconnection_review.sql` | REVIEW REQUIRED, apply after 19 and 20: receipt-checked notice closure, bill snapshots, closed history, delivery review and Admin payment alert |
| `migrations/20261002064410_account_lifecycle.sql` | REVIEW REQUIRED, after disconnection review: separate work/login access, audited President transfer, household handover, cache access versions and guarded mutations |
| `migrations/20261002064728_reader_boheco_waiver.sql` | REVIEW REQUIRED, after account lifecycle: approved one-household Meter Reader coverage, noncash bill settlement and corrected financial summaries |
| `migrations/20261002151432_staff_assignment.sql` | REVIEW REQUIRED, after reader coverage: atomic Meter Reader/Cashier replacement using existing logins, stale-selection checks and audited handover; preserves accounts and history |
| `migrations/20261003122000_household_required_accounts.sql` | REVIEW REQUIRED, after staff assignment: atomic profile/household setup, deferred household requirement for new accounts, and household checks during staff replacement. Redeploy `manage-accounts` and install the updated app together. |
| `migrations/20261003212547_overdue_batch_authorization.sql` | historical batch approval API |
| `migrations/20261003221703_overdue_household_request.sql` | historical household request API |
| `migrations/20261004015207_pondo_boheco_settlement.sql` | reserve ledger, BOHECO trips and settlement routes |
| `migrations/20261004030427_billing_schedule.sql` | area schedules and frozen trip cutoffs |
| `migrations/20261004060000_referred_disconnection_notices.sql` | notices following confirmed BOHECO referrals |
| `migrations/20261004070000_reader_monthly_compensation.sql` | monthly PHP 500 reserve-funded compensation |
| `migrations/20261004071610_automatic_boheco_routing.sql` | automatic uncovered overdue routing |
| `migrations/20261007105843_regular_rounding_reserve_credit.sql` | receipt-backed rounding credits, exactly once |
| `migrations/20261007111213_settlement_correction_recovery.sql` | explicit, version-checked settlement corrections |
| `migrations/20261007202922_restrict_legacy_settlement_correction.sql` | blocks the obsolete correction endpoint |
| `scheduling/sms_cron.sql` | runs `send-sms` every 15 minutes with `pg_cron` — apply last, see below |

`07` is not optional. Every policy calls a helper in the `app` schema, and
without the grant every request fails with
`401 permission denied for schema app` — which surfaces in the app as a silent
bounce back to the login screen.

### Account lifecycle and BOHECO coverage rollout

For the simplified **Manage accounts → Staff → Change** flow, review and apply
`20261002151432_staff_assignment.sql` after the lifecycle/coverage migrations.
It extends the account workspace and adds a guarded assignment function. No
Edge Function redeployment is needed for this change: new people use the existing
`manage-accounts` creation action. See [staff assignment rollout](../docs/week13/staff_assignment_implementation.md).

The two October 2 account/waiver migrations above are prepared locally and have
not been applied to the live project by this implementation. Existing accounts
and transactions are retained. Review both files before applying them in order;
the updated app requires both migrations. Existing installations that already
applied 19, 20 and disconnection review should not rerun those earlier files.

After the two new migrations, deploy the new authenticated `manage-accounts`
Edge Function, then release the updated app. It uses the usual server-side
Supabase URL/service key; no new SMS setup is needed. Deployment remains a
separate user-approved step. See `docs/week13/account_management.md` for
failure recovery and `docs/week13/account_lifecycle_implementation.md` for the
test sequence and verification limits.

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

**Existing installations:** the user must run the whole
`migrations/15_sms_event_ordering.sql` file, then redeploy **both**
`httpsms-webhook` and `send-sms` with the commands below. Do SQL first: the new
webhook passes a fifth RPC argument. The old four-argument signature remains
for compatibility. Keep the separate `15_bill_meter_readings.sql`; neither
file replaces the other. This repository uses the explicit manual run order
above, not automatic migration discovery by numeric prefix.

The webhook matches an established gateway ID first, then the notification
ID in `request_id`, and saves the binding under a row lock. An unmatched
event returns an error rather than silently acknowledging it. Non-final
expiry events are still ignored by the webhook. Existing lost events are
not automatically recovered; replay them through the signed provider webhook.

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
| `tests/sms_event_ordering_test.sql` | local Postgres after migration 15, with a local household fixture; both delivery orders, final states, replay, binding precedence and grants; rolls back |

Run the isolated HTTP-mocked Edge Function suite (Deno installed):

```sh
deno test --allow-env supabase/functions/tests/sms_delivery.test.ts
```

Run that command from the repository root. No network permission is granted
to the tests, and no real credentials or destination numbers are used.

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

## Pending Week 13 rollout

Migrations 19 and 20 are prepared, not applied live. Apply each once, in order,
only after approval and checking deployed definitions against migrations through
18. They change payment policy for older APKs too. Reconcile pre-upgrade queued
cash before rollout; do not clear app data to remove pending items. See
`../docs/week13/implementation_report.md` for the release and phone checklist.

`tests/overdue_staff_test.sql` is for a disposable local database with synthetic
05 fixtures and migrations 19/20. It uses simulated Auth identities and ends in
ROLLBACK. Never run this fixture-dependent test against the live project.

The disconnection review migration must follow 19 and 20, regardless of filename
sorting. It preserves existing notices and reconstructs legacy bill associations
without inventing original balances. Its new read APIs require the migration
before distributing the updated app. See
`../docs/week13/disconnection_review_implementation.md` for verification and the
phone checklist. Existing cleanup scripts need a separate review against the new
dependencies before reuse; this rollout does not perform a reset.

`tests/disconnection_review_test.sql` runs only in a disposable local database
with synthetic 05 fixtures and all three pending migrations. It tests payment
evidence, closing permission, required notes, history, legacy associations, SMS
review and the Admin alert. It ends in ROLLBACK; never run it on production.

Household-required creation and the optional reviewed legacy backfill are documented in [household account setup](../docs/week13/household_required_accounts.md). Start with the read-only `checks/account_setup_inventory.sql`; no backfill is part of the migration.

The combined Admin billing settings are documented in [billing schedule](../docs/week13/billing_schedule.md). Apply `20261004030427_billing_schedule.sql` after the pondo settlement migration before using the updated app. No live migration has been applied by this task.
