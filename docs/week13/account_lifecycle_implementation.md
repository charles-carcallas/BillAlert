# Account replacement and staff households

Implemented locally on October 2, 2026. Four roles remain. No live SQL,
deployment, account deletion, commit or push was performed.

## What changed

- Accounts → Manage existing accounts separates ending a work assignment from
  disabling login. Ending work preserves household access and historical credit.
  Restoring login does not automatically restore a job that may now be occupied.
- Staff can switch between Work and My household with one login. Household reads
  explicitly select their linked household. Access changes refresh permissions,
  clear stale cached data and preserve unresolved queued work for reconciliation.
- President transfer prepares a distinct successor, requires their password
  change and acceptance, then lets the outgoing President complete the handover.
  Historical actions keep the original person's identity. Manual verified
  maintainer recovery is available without a fifth application role.
- A reviewed same-household login change preserves its ledger. An unrelated
  occupant gets a separate ledger with the recorded closing reading as its
  opening baseline; the old person retains their own archived history and debt.
- An Area President can approve one linked Meter Reader household for full BOHECO
  coverage from an explicit current/future billing month. It applies when an
  eligible bill is first priced. Earlier priced debt is not changed. Coverage
  ends when the work assignment or household/meter eligibility ends.
- Covered bills show “Covered by BOHECO,” zero payable balance and a separate
  coverage amount. They generate no cash payment or receipt. Collection and
  remittance calculations exclude covered demand. The existing PHP 300 salary
  cap is unchanged. President and Cashier bills remain ordinarily payable.

## Reviewed rollout, still pending

1. Back up the database privately and retain the existing app build. Finish and
   reconcile device queues before using account transfers.
2. Review and apply `supabase/migrations/20261002064410_account_lifecycle.sql`.
3. Review and apply `supabase/migrations/20261002064728_reader_boheco_waiver.sql`.
4. Deploy the new `manage-accounts` Edge Function using the project's existing
   authenticated-function setup, then install/release the updated app.

These are forward migrations, not cleanup scripts. They retain current accounts
and transactions. They require the previously applied 19, 20 and disconnection
review migrations. Do not rerun older migrations over these definitions. This
build expects both new migrations; releasing it first can cause missing-column
or missing-function errors. No SMS secret or webhook change is required.

## Acceptance walkthrough after approved rollout

1. Link each staff login to their own household. Switch Work/My household and
   verify bills, history, alerts and contact changes affect only that household.
2. Reconcile a reader's device, end their work access, and create the replacement
   reader. Confirm the old login retains only household access; queued old work
   does not upload under the successor's identity. Repeat for Cashier.
3. Disable a test Consumer login and check online access is refused. Re-enable
   it. Do not assume an offline unlocked phone can be remotely erased.
4. Prepare a President successor, change their temporary password, accept, then
   complete from the outgoing President. Confirm only the successor has work
   access and earlier records retain their original author.
5. Exercise same-household change and unrelated occupant handover separately.
   Verify the new occupant cannot view the old ledger and the next reading uses
   the correct opening baseline.
6. Assign reader BOHECO coverage, record a reading and post its first amount.
   Verify coverage, no receipt/cash, correct remittance figures, and ordinary
   payment for President/Cashier. End the reader's assignment and confirm new
   bills no longer receive coverage while existing covered bills remain intact.

## Verification and limits

Both migrations applied together to a fresh isolated local PostgreSQL database.
Account lifecycle, reader waiver, overdue/staff and disconnection SQL suites
passed. Lifecycle tests include manual recovery guards. A concurrent upload test
confirmed a reading waiting behind an assignment change is refused afterward.

The new Edge handler has 12 passing isolated tests and its runtime adapter passes
Deno type-checking. These tests inject Auth dependencies; they do not exercise
the live Supabase Auth service. The full Flutter suite passed: 470 tests.
Final analysis reports only the seven pre-existing `scratch/test_supabase.dart`
issues. The web release build compiled successfully without live credentials;
its existing missing CupertinoIcons font warning remains. No APK was built or
distributed for this change.

Still requires live testing after approved rollout: Auth account creation and
banning, real-device session refresh, offline household switching, notifications,
and the full two-phone President transfer. An already unlocked offline phone
cannot learn an access change until reconnecting. Reconciliation covers every
device and actual cash; a zero queue on one phone is not sufficient evidence.

Auth and database updates span separate services. An uncertain login change
requires checking both database status and Auth ban status before retrying.
Serialize account changes for the same person. Ambiguous identity creation is
never blindly repeated or automatically deleted; use the returned reference and
the recovery instructions in `account_management.md`.
