# BillAlert — handoff

Paste this to whoever picks the work up next.

---

## The project

BillAlert is a Flutter + Supabase app for electricity billing in Barangay
Tubod, Clarin, Bohol. Four roles: Meter Reader, Admin (Area President),
Cashier, Consumer. **Deadline: 10 September 2026.**

**The one rule that outranks everything.** The instructor grades whether the
flow FUNCTIONS, not whether it matches the Figma. A screen that looks exactly
like the mockup and shows mock data is a failure; a screen that looks
approximate and moves real data through Supabase is a pass. When time runs
short, cut visual fidelity, never wiring. **Never insert placeholder data to
make a screen look finished** — if a screen cannot get real data, render an
honest empty state saying so.

**BillAlert never derives a bill amount from consumption.** There is no tariff
and no rate table. The cooperative returns a peso figure and the Admin types
it in; the app's only adjustment is to always round any centavos up to the next
whole peso before posting. If you write a multiplication from kWh that
produces pesos, you have misunderstood the domain.

## State: the core flow works end to end

Every leg proven against the live Supabase project with row ids, recorded in
`docs/week11/evidence_log.md`:

```
login → reading → unpriced bill → consumer sees it
      → Admin posts the amount → consumer sees the amount
      → cashier collects across two months → ONE receipt
```

Receipt `BIEC-2026-09-004472` settled July and August in one
`fn_record_payment` call: 1 row in `payment_transactions`, 2 in `payments`,
both bills `paid`. Posting an amount and recording a payment were both driven
**from the running app**, not just the API.

Slices 0–4 are done. Admin → Accounts now includes consumer creation and a
server-backed staff-account flow. The latter still needs migration 09 and the
Edge Function deployed, then verification as a signed-in Area President,
before it may be called complete.

## What is left

**Slice 5, and the brief says cut it without hesitation if time is short:**

- Admin New Account (staff) — implemented locally; deployment verification pending
- Disconnection Notice screen — Figma `132:2`

These are real features but are not in the Week 11 core flow, and there is no
data to demonstrate them.

**Higher value than Slice 5, if there is time:**

1. **`v_payment_history` has no `consumer_name`.** The Cashier receipt list
   shows each receipt without the payer's name. One-line view change — add
   `c.first_name || ' ' || c.last_name`. See the note on
   `PaymentRepositoryImpl.recentInArea`.
2. **On-device offline behaviour is unverified.** The outbox surviving an app
   kill and syncing on reconnect is covered by unit tests only, never on a
   phone. This is graded (NFR-05, MTR-11/12).
3. **Recording a reading has never been driven from the app** — only through
   PostgREST. Note FR-23 blocks a second reading per cycle, and all five
   households are already read for August; the September cycle starts on the
   15th.

## Hard constraints — each has already cost a day when broken

**Architecture.** Screen → controller → use case → repository. A widget or
controller that touches Supabase breaks the layering; there is a test for it.
`domain/` imports nothing — no Flutter, no Supabase, no Drift, no `intl`.

**Never reimplement a Postgres function in Dart.** `fn_record_payment` settles
several bills in one transaction; a Dart loop of updates leaves a consumer
half-paid the first time the network drops.

**Money is integer centavos.** Never a `double`, including at the JSON
boundary. Parse with `Money.tryParse`. `Money` has no `*` and no `/`,
deliberately.

**Ask the `Bill` entity its questions** — `isUnpriced`, `isPayable`,
`balance`, `statusLabelOn(today)`. Never test `bill.totalAmount == null` in a
screen.

**Offline.** Every mutation goes through the outbox first, written before the
UI confirms. `clientUuid` is minted once and reused on every retry — that is
what makes replay idempotent. `capturedAt` is the moment of capture, never of
sync; the 48-hour disconnection window is counted from it and has legal
meaning.

**Supabase.** Only five RPCs are app-callable: `fn_record_meter_reading`,
`fn_post_bill_amount`, `fn_record_payment`, `fn_issue_disconnection_notice`,
`fn_close_disconnection_notice`. Staff creation uses the authenticated
`create-staff-account` Edge Function; its `fn_create_staff_profile` database
helper is server-only. Everything else in `02_functions.sql` is a trigger or
helper. Read through the `v_` views, not raw joins.
`test/architecture/vocabulary_test.dart` enforces this.

**Domain.** The Admin is an **Area President**, not a superuser — RLS confines
every staff role to its own service area. One cash handover = ONE official
receipt, however many bills it settles. An unpriced bill can never appear in a
payment selection.

**Login.** `login_screen.dart` performs **no navigation**; the router reacts to
auth state. Keep `if (!mounted) return;`, `dispose()` on both controllers, the
`_obscure` toggle, and `FailureBanner`. The field is Username, never email —
the mapping happens in the data layer.

**Visual.** Colours and type scale live in `lib/presentation/theme.dart`, read
through `Theme.of(context)`. No hardcoded hex in screens. Spacing stays in
screens. **No new packages.** No animations, no dark mode.

**Errors.** Plain English through `Result` / `AppFailure` / `FailureBanner`.
Never a raw PostgREST string on screen. Graded explicitly.

**Security.** No credentials in any tracked file. Config arrives via
`--dart-define` through `AppConfig` from a gitignored `.vscode/launch.json`.
Graded.

## Traps already found and fixed — do not undo these

1. **`fn_record_meter_reading` held `select … for update` on the consumer
   lookup.** Under RLS, `for update` also checks the UPDATE policy's USING
   clause, and `consumers_admin_update` is admin-only — so the function failed
   for the Meter Reader, the only role allowed to call it. The locks in
   `fn_post_bill_amount` and `fn_record_payment` are on `bills` and must stay.
2. **All twelve `v_` views bypassed RLS.** A Postgres view runs as its OWNER
   unless `security_invoker` is set. A signed-in consumer could read every
   household's bills in their area. Fixed at the foot of `03_views.sql`; any
   new view needs the same line.
3. **`notifications` had no INSERT policy at all.** `fn_queue_notification` is
   SECURITY INVOKER, so posting an amount failed with `42501` and the whole
   transaction rolled back — the Admin could not price a single bill.
4. **`CycleLabel` only parsed `"2026-09"`,** but every view returns
   `"August 2026"`. Every bill rendered as January 1970. Now reads
   `cycle_year`/`cycle_month` integers first, `period_start` next, the text
   last.
5. **The consumer's bill screen looked up a household by PROFILE id.** A
   consumer signs in with a `profiles` row but bills hang off a `consumers`
   row. Use `ConsumerRepository.signedInConsumer()`.
6. **`FailureMapper` treated every unrecognised `AuthException` as a lost
   session,** so reusing your current password on the change-password screen
   said "You have been signed out" — on the one screen a forced user cannot
   leave. Only 401 and 403 may claim the session ended.
7. **`v_consumer_outstanding` is a per-consumer roll-up** — it has no
   `bill_id`, no cycle and no amount, so it cannot build a `Bill`. Per-bill
   reads use `v_bill_status`.
8. **PostgREST returns 204 on a DELETE that matched nothing.** Never read that
   as "a row was removed" — check the count.
9. **`05_seed.sql`'s FIXTURE section fails on Supabase** — `profiles.id`
   references `auth.users(id)` and the fixture UUIDs have no logins. The
   Supabase rows have RANDOM ids, so anything targeting Supabase must look
   consumers up by `consumer_no`, never by a hardcoded id.

## Environment

- Credentials: **`.vscode/launch.json`** (gitignored) holds `SUPABASE_URL` and
  `SUPABASE_ANON_KEY` as `--dart-define` args. Read them from there. Never
  print or commit them.
- Accounts (passwords are not tracked): `mario.ombajin` (admin), `ledesman.dormal`
  (meter reader), `mercedita.gales` (cashier), `virgilio.busalanan`
  (consumer). All Area 3 — Tubod.
- Run on web: `flutter run -d web-server --web-port 8080` with both
  dart-defines. **Android needs a real machine** — Gradle fails with
  `Unable to establish loopback connection` inside some agent sandboxes, though
  `flutter build apk` works from an ordinary terminal.
- **Every build needs both `--dart-define` values, including the APK.**
  `.vscode/launch.json` is read by VS Code, not by `flutter build`. An APK
  built without them starts on `MissingConfigApp` — the "not configured"
  screen — which is the app refusing to run against a null URL rather than a
  bug. README.md documents the command; from PowerShell:

  ```powershell
  $t = Get-Content -Raw .vscode/launch.json
  $u = [regex]::Match($t, 'SUPABASE_URL=(?<v>https://[^"\s]+)').Groups['v'].Value
  $k = [regex]::Match($t, 'SUPABASE_ANON_KEY=(?<v>[^"\s]+)').Groups['v'].Value
  flutter build apk --release --dart-define="SUPABASE_URL=$u" --dart-define="SUPABASE_ANON_KEY=$k"
  ```

  Rebuild the APK after any commit you intend to demo; the one in
  `build/app/outputs/` is whatever was last built and carries no version
  marker.
- `flutter analyze` should show only 7 issues, all in the gitignored
  `scratch/`. `flutter test` should be **156 passing**.
- SQL lives in `supabase/migrations/` (01–05, 07) and `supabase/tests/`. That
  folder is the source of truth; the old copy under `Week10_DataModel/sql/`
  has been replaced with a pointer. Applying SQL needs the Supabase SQL editor
  — there is no CLI or `psql` on this machine.

## How to verify anything

Do not trust a green test suite. Two of the three worst bugs above were
invisible to it.

Check against the **live database, as a real signed-in user, through
PostgREST with the anon key** — never the SQL editor, which connects as the
table owner and bypasses every RLS policy, so everything looks fine there.

Sign in at `POST /auth/v1/token?grant_type=password` and query
`/rest/v1/<view>` with the returned bearer token. A missing column returns
`400 / 42703`, which makes a `200` meaningful proof that a select is correct
even when the table is empty.

Report what you built, what you ran, what it returned, and what you could
**not** verify. An honest "not verified" is worth more than a confident claim.
