# Staff assignment and replacement

Manage accounts now opens on **Staff**, with one card each for Meter Reader and
Cashier. **People** retains login suspension, household setup and BOHECO coverage
controls. **Households** retains household-link and occupant-handover workflows.

## Normal handover

1. Finish syncing all affected phones. Review pending or rejected work and
   complete any cash/remittance handover. The checkbox is the President's
   confirmation; a count from one phone cannot prove this for every device.
2. Open **Accounts → Manage accounts → Staff → Change Meter Reader/Cashier**.
3. Select an existing person. Only active accounts in the same area without
   another active staff appointment are offered. Former staff may be selected.
4. If the person has no login, choose **Add new person**, enter their name and
   username, then create the login. Give them the generated temporary password.
   Their first sign-in requires a new password.
5. Review the outgoing and incoming names, confirm readiness, then confirm the
   assignment. For a vacancy, the card says **Assign** and has no outgoing person.

Creating a new login and confirming a staff assignment are separate operations.
If the President cancels after creation, the new login remains without work
access and can be selected later. No household is invented or linked automatically.
If creation cannot be confirmed, check the username in the refreshed accounts
before trying again; contact support if an Auth identity lacks a profile.

## What changes

- The outgoing person loses work access; their login and household link remain.
- The replacement keeps their identity and login and receives the selected work
  role. Their own household access remains available when linked.
- Both staff updates and the audit event commit in one transaction. Stale account
  versions or a changed current holder refuse the whole request.
- The area lock also serializes this handover with existing guarded financial
  writes. Concurrent replacement attempts cannot silently overwrite each other.
- Access versions change so online session checks refresh permissions and the
  corresponding local cache scope. Offline phones cannot learn the change until
  they reconnect; server authorization prevents stale work uploads afterward.
- Existing readings, receipts, bills, balances and authors are preserved.
- The outgoing Meter Reader's active BOHECO coverage ends through the existing
  lifecycle trigger. Historic covered bills remain covered. Record coverage for
  the new reader separately after confirming eligibility and household linkage.

Account activity records `staff_assigned`, the role, incoming/outgoing IDs and
the reconciliation confirmation. A private operation receipt makes an exact
replay harmless and prevents an old request from reapplying an appointment.

## Database rollout — user review and execution required

Review **supabase/migrations/20261002151432_staff_assignment.sql**, then apply it
after the account lifecycle and reader coverage migrations. It contains a
transaction, preserves current data, and enables RLS on its private operation
table with no client table access. No existing assignment changes merely by
applying the migration.

No Edge Function redeployment is required. The app uses the already implemented
`manage-accounts` action `create_consumer_login` to create a candidate, then the
new `fn_assign_staff` RPC for the handover. Rebuild/restart the app for the UI.

No live SQL, deployment, commit or push was performed for this change.

## Verification

Local result: **521 Flutter tests passed**. Static analysis reports only the
seven existing `scratch/test_supabase.dart` issues. Light/dark phone and desktop
previews were rendered and inspected. All current SQL migrations applied to a
fresh isolated PostgreSQL database, and staff assignment, lifecycle, reader
coverage, disconnection review and overdue/staff SQL suites passed there.

The widget tests exercise selecting an existing login, cancellation, creating
a new person before confirmation, uncertain responses, offline refusal and
layouts at phone/desktop widths including large text. Repository tests verify
the creation action and assignment request versions and reconciliation flag.

`supabase/tests/staff_assignment_test.sql` is for a disposable local database
with synthetic `05_seed.sql` fixtures and all current migrations. It rolls back.
It checks area/role permissions, stale selections, atomic rollback including
coverage, vacancy assignment, replay protection, access versions and unchanged
household/reading/receipt/bill records. Do not run this fixture test on live data.

Local concurrent-session testing also checks that one assignment commits and a
competing stale assignment fails. Live Edge Function creation, installed-phone
permission refresh, Android layouts and the real handover still need an on-device
smoke test after the migration and updated app are installed.
