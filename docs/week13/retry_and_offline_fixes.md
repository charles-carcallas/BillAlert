# Reserve retry, correction access, and offline refresh fixes

## Install

The two previous October 7 fixes were verified as present in live Supabase on
October 8, 2026 Philippine time. Do not rerun those migrations.

Run `supabase/migrations/20261007202922_restrict_legacy_settlement_correction.sql`
in Supabase SQL Editor, then install the updated APK. This new migration has
been tested locally, not applied to the live project by this change.

For the existing debug installation:

```powershell
flutter build apk --debug --dart-define-from-file=env.json
```

## Behavior

- A reserve contribution, withdrawal, opening balance, or correction is saved
  locally before sending. If the response is lost, its original reference and
  exact amount/reason survive restart, sign-out, cache clearing, and outbox
  clearing. Requests remain separated by staff account, role, and area.
- Tap **Record reserve fund money** to resolve an unconfirmed entry. The app
  offers **Check previous fund entry?** instead of another amount form. Checking
  resends the same request; the server returns the existing ledger entry if it
  already saved. A successful check does not record new physical cash.
- A different entry cannot replace an unresolved request. Explicit validation
  refusals on a first attempt allow correction; uncertain results remain saved.
  A retry refused because access has changed remains pending for reconciliation.
- The old two-argument settlement correction endpoint is no longer executable
  by clients. The checked correction endpoint retains its explicit action,
  version check, retry protection, and Admin/area checks. Older APKs must update
  to perform corrections.
- Foreground staff polling leaves cached lists alone while disconnected. A
  restored connection refreshes once. A connected Wi-Fi link with no reachable
  server gets a lightweight reachability probe rather than refreshing all work
  lists. Pausing the app stops foreground polling.

## Phone acceptance check

1. Use a test contribution and interrupt connectivity during submission. If its
   confirmation is uncertain, reopen the app and tap Record reserve fund money.
   Check the original entry; verify one ledger credit, not two.
2. Repeat with a test withdrawal/correction and compare the actual balance.
3. Turn off Wi-Fi and mobile data while on each staff home screen. Wait more
   than a minute: no repeated background loading should replace the cached list.
   Reconnect and confirm the list refreshes.
4. Admin corrects a test BOHECO verification through the updated screen. Confirm
   the expected state and unchanged cash unless recording a physical return.

Do not uninstall or clear Android application storage while a fund entry is
unconfirmed: that removes the device database. Reconcile with the server first.

## Verification

601 Flutter tests passed, including lost-response recovery across database
restart/cache clearing, owner separation, blocking replacement entries,
database upgrades, and offline/reconnect polling. Local rollback SQL suites
passed for checked corrections with legacy access denied, rounding, automatic
BOHECO routing, and monthly compensation. Live records were not changed.
