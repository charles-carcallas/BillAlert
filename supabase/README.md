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
