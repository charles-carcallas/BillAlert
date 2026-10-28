# Week 13 implementation and review

2 October 2026. Application changes are local; database migrations are prepared
for review. No live SQL, Edge Function deployment, account cleanup, commit or push
was performed. Existing accounts and server records were not changed.

## Accepted behavior

- New payments require online collection eligibility checks. Readings, amount
  posting and notice capture can remain queued offline with the original owner.
- Admin authorizes the full overdue balance; Cashier records the cash. Approval
  lasts until used or revoked, provided the balance has not changed. Authorization
  creates no cash, payment or receipt. Current collection stays blocked until all
  overdue balances are actually paid. Overdue collection creates a separate receipt.
- The editable due-date default is the 28th of the bill's cycle month. If that
  date has passed, Admin must choose a valid date. Due date never moves the cycle.
- Legacy queue entries without provable ownership are preserved and quarantined.
  Their ownership and receipt status require manual reconciliation; no automatic
  reassignment, deletion, replay or claim of successful payment is made.

There are no remaining policy decisions blocking these features. Partial overdue
settlement, waivers and external payments remain outside the accepted scope.

## What changed

The local database is version 9. New outbox rows retain profile, role and area.
Reads, badges and updates are scoped to that owner. Account changes stop and await
the active drain, invalidate the session generation and clear account caches.
Late responses are guarded from replacing another account's results.

Sync callers share one drain, including while connectivity is being checked.
Interrupted operations retry the same UUID. Captures added during a drain receive
another pass. Local status-write failures propagate instead of becoming success.
Foreground resume, connectivity recovery and a one-minute check retry pending work;
this is not a promise of closed-app background uploads.

Payment allocations are reserved durably on the device. Duplicate collection is
blocked while confirmation remains uncertain, including after reopening. Only the
exact transaction returned for that operation is used to retrieve its receipt.
An older receipt from history is never substituted. Server checks are repeated
under locks at collection, since a preflight response cannot reserve cash on
another phone. A pending or rejected result needs review, not another collection.

Admin posting also uses exact operation replay, including the original cooperative
amount. Profile displays status and failure text, allows retry and offers a date
correction only after an explicit past-due-date rejection. The correction preserves
the UUID and amounts. Reader success updates the cached reading cycle and refreshes
the roster. Staff list refresh and saved timestamps help distinguish cached data.

Admin reaches Overdue from Notices; Cashier reaches it from Consumers. Normal
collection excludes overdue bills. Earlier bills that are not yet overdue remain
available with their billing month shown. Admin can authorize/revoke; Cashier can
request authorization and collect the approved full balance.

Staff have a separate notification inbox and phone-alert feed. Events cover
accepted readings for Admin, priced bills for Cashier, assigned households for
Reader, and overdue requests/decisions for Admin/Cashier. Sync produces one local
summary per completed drain. Reader alerts contain no pay or rounding-fund amounts.
Claims are per device, retry failed display after a lease, and skip old delivered
claims before limiting a batch. Destinations and recipient identity are checked
when opening an alert. Staff alerts do not consume Consumer notifications.

## Database review

Apply **19 then 20**, once each, only after explicit approval:

1. `supabase/migrations/19_overdue_collection.sql`: adds approval/audit records,
   private post-operation replay records, guarded payment and amount RPCs, online
   collection preflight and the overdue view. Existing receipt/allocation logic
   remains behind a private function. Direct bill/payment mutation grants are
   tightened to prevent bypass. This policy also affects older APKs.
2. `supabase/migrations/20_staff_alerts.sql`: adds recipient-scoped inbox records,
   private device claims, event triggers and notification RPCs. No historic events
   are backfilled. No SMS schedules, provider settings or secrets are changed.

These files preserve rows and do not reset accounts, balances, sequences or data.
They assume the repository schema through migration 18. The deployed definitions
must still be compared before application. Do not rerun already-applied 19/20,
reapply old definitions afterward, or execute the fixture test on production.

## Verification

- Flutter: 434 tests passed, including SQLite ownership/isolation, simultaneous
  drains, capture during drain, sign-out mid-upload, legacy preservation, reserved
  payment restart, account change during preflight, rejected-date repair, exact
  receipt lookup, persisted Admin confirmation, local status-write failure,
  due-date boundaries and existing application regressions.
- Flutter analyze: only the seven pre-existing `scratch/test_supabase.dart`
  issues remain; no new analysis findings. `git diff --check` passed.
- Both migrations applied to a fresh disposable PostgreSQL 17 database using
  synthetic repository fixtures, simulated Auth identities and API grants.
- `supabase/tests/overdue_staff_test.sql` passed: overdue-first enforcement,
  approval without cash, revocation, role/area denial, exact payment/post replay,
  cooperative-amount mismatch, no double cash, per-device claims and batches over
  fifty events. The test rolls back its synthetic transactions.
- Separate local concurrent requests returned one receipt for the same UUID;
  competing different UUIDs for the same balance allowed only one collection.

The local harness is not a deployed Supabase/PostgREST environment. Auth account
creation integrations were not exercised by these SQL tests.

## Required rollout and phone checks

Keep the existing data and app storage. Before upgrading, inventory every phone's
pending work, verify any cash against its exact receipt and preserve unresolved
legacy operations. Quarantine is deliberately not a self-service reassignment
tool; any recovery of those rows needs a separately reviewed reconciliation.

After migration approval/application, build and distribute the updated APK using
the existing signing key and a new build number. This task did not build or
distribute an APK. Test on the actual Android devices:

1. Switch Admin → Reader → Cashier on one phone with unsent work. Only its original
   owner may see/upload it; check role and area changes too.
2. Capture a reading in airplane mode, kill/reopen, reconnect and verify one
   reading with the right actor. Try Wi-Fi without internet and recovery on the
   same Wi-Fi connection. Check that the roster stays reconciled after sync.
3. Post the cooperative amount with the cycle's 28th default; try an expired
   offline due date and use Profile to correct the explicit rejection.
4. With an overdue bill and a current bill, verify current checkout is blocked.
   Request approval, authorize it, revoke it, reauthorize, collect overdue once,
   then collect current. Verify separate receipts, Consumer history and Remit.
5. Interrupt a payment response, reopen and sync. Verify the same UUID/receipt and
   no second cash collection. Check that legacy quarantine survives sign-out.
6. Confirm each staff event on its intended role, two devices, foreground/resume,
   background, denied notification permission and alert taps after account switch.
   Background timing depends on Android/WorkManager; it is not instant delivery.

Live schema compatibility, phone behavior, notification permissions/background
delivery, signed APK installation and Firebase distribution remain unverified.

## Disconnection follow-up

The recommended notice improvements are implemented locally. See
`disconnection_review_implementation.md` for bill/receipt evidence, server-checked
Settled outcomes, required cancellation/referral notes, closed history, SMS/upload
status and refresh behavior. The additional migration
`20261002034514_disconnection_review.sql` follows 19 and 20 and awaits approval.
The expanded full app suite passes 444 tests; both notice and overdue/staff SQL
suites pass on a disposable local database. No live deployment or cleanup occurred.

## Laptop layout follow-up

At 900 logical pixels and wider, signed-in roles use a left sidebar with the same
permitted destinations. Narrow windows retain bottom navigation. The sign-in page
uses two panels, the amount queue uses two columns when content width reaches 920
pixels, and shared expandable sheets open as centered, scrollable desktop dialogs.
Draft dismissal guards and role permissions are preserved. The web build compiled
locally without live credentials; no web deployment or database change was made.
Synthetic desktop rendering and navigation/resize/dialog tests passed. Live browser
account flows and actual device checks remain separate rollout tasks.
