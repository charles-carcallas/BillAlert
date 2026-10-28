# Disconnection notice review

2 October 2026. Implemented locally for review. No live SQL, deployment, data
cleanup, commit or push. Accounts, transactions, SMS configuration and existing
notice timing are preserved.

## What Admin sees

An active notice shows each covered bill, its original balance when available,
its remaining balance, the household's current overdue bills and the matching
receipt allocations. New notices capture their covered bills when inserted.
Old notices have reconstructed associations marked as legacy; original amounts
are left unknown rather than inferred from today's balance.

The review includes notice SMS states: waiting, gateway acceptance, sent, failed
or uncertain. A gateway send confirmation does not prove delivery to the person's
screen or that they read it. Raw gateway errors and phone destinations are not
exposed on the review screen. Local pending/failed notice uploads are displayed
separately above the active list, including when the server list is unavailable.

The notice document refreshes on resume, every minute while open and on pull to
refresh. Staff refreshes also reload the active and closed lists. Saved reviews
and history can be read offline with a saved-copy indicator; closing remains
online and the server checks the current state again.

## Payment and closure

1. Admin authorizes overdue collection in Overdue. This records permission only.
2. Cashier records the actual payment through the guarded collection workflow.
3. When all overdue balances are paid and every covered bill has full payment
   allocations backed by receipts, the notice becomes ready to close. A current
   bill whose due date has not passed does not block closure of the older notice.
4. Admin receives a payment-confirmed staff event and reviews the receipt evidence.
5. Admin selects Settled. Under household/bill/notice locks the server verifies
   payment again, then records the closing actor, timestamp and notes.

Authorization alone, an edited due date or an accounting balance adjustment
without sufficient receipt allocations cannot qualify a notice as Settled.
Another newly overdue bill blocks closure until paid. Payment never silently
closes a notice, and it does not restore or disconnect physical electricity.

Cancellation requires a reason; referral requires handover details. These outcomes
do not erase unpaid bills. Referred records handover to cooperative personnel and
does not schedule, authorize or execute a disconnection. Existing deadlines and
holiday calculations are unchanged.

Closed notice history can be searched by household/notice and filtered by outcome.
Opening a history entry displays its evidence, closing actor, date and notes.
It cannot be closed again with a different outcome. The same actor's exact retry
is safe if a previous close succeeded but its response was lost. A failed network
response is shown as unconfirmed and asks for an online refresh. An older pending
refresh cannot reopen a notice after a successful close.

## Database review and rollout

Apply only after explicit approval and comparison with deployed definitions:

1. `supabase/migrations/19_overdue_collection.sql`, if not already applied.
2. `supabase/migrations/20_staff_alerts.sql`, if not already applied.
3. `supabase/migrations/20261002034514_disconnection_review.sql`, once.

The timestamped file was created with Supabase CLI `migration new`. Existing
numbered migrations require the explicit order above; do not rely on sorting or
blindly push the migration folder. This migration adds `notice_bill_items`, Admin
review/history views, `fn_notice_review`, a guarded close function and private
snapshot/payment-alert triggers. RLS restricts review/history to Admin's own area;
Consumer and Meter Reader active warning access is retained. Direct client notice
updates/deletes cannot bypass the outcome checks.

The new application queries need this migration before distribution. No Edge
Function deployment or SMS secret/schedule change is required by this feature.
Keep existing device storage and pending work. Any later cleanup needs its own
approved scope and updated dependency review; do not reuse an old reset script
without checking the new tables.

## Verification and limits

The full Flutter suite passes 444 tests. Flutter analyze reports only the seven
existing scratch issues. New app checks cover missing receipt readiness, required
notes, stale server rejection, uncertain responses, closed records, delayed
refreshes, display controls, offline evidence and cache clearing across sessions.

The final migration applied cleanly to a fresh disposable PostgreSQL 17 database
with synthetic repository fixtures, simulated Auth identities and API grants.
`supabase/tests/disconnection_review_test.sql` and the existing
`supabase/tests/overdue_staff_test.sql` passed and rolled back their test data.
They cover receipt guards, permission/area isolation, required notes, exact
closure retry, history, legacy associations, delivery review and staff events.
These tests are not a deployed Supabase/PostgREST integration test.

Still required after approved application and a new signed APK:

- On real Admin/Cashier phones, issue a notice, authorize collection, record the
  payment and verify the receipt, ready badge and Admin alert. Confirm authorization
  alone leaves Settled disabled.
- Test a second overdue balance, cancellation/referral details and closed history.
- Go offline while reading a saved review. Reconnect and verify refresh, and
  interrupt a close response to confirm the recorded outcome before retrying.
- Check pending notice upload status, SMS state and notification taps with real
  permissions, background scheduling and account switches.

Live schema compatibility, physical phone behavior, background notification
delivery and signed APK installation remain unverified. No legal eligibility or
physical disconnection behavior is newly certified by these tests.
