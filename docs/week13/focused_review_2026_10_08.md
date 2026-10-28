# Focused review — 8 October 2026 (Philippine time)

Review only: no application changes, live financial writes, or live fixture tests.

## Findings

### P1 — Reserve entries can duplicate after an uncertain network result

`lib/presentation/common/settlement_panel.dart:282` creates a new request UUID
each time the fund form is submitted. The form/controllers are discarded after
the attempt; `action` displays the network failure and allows a new entry. If
Supabase committed the first entry but its reply was lost, re-entering the same
contribution, withdrawal, or correction uses a different UUID. The server's
duplicate guard only recognizes the original UUID.

Local reproduction: two submissions for one simulated PHP100 contribution with
different request IDs create two credits. This reproduced the server effect;
the lost-response/re-entry path was verified in code, not on a physical phone.

Fix: persist each financial request before sending it, retain its UUID and exact
payload across reconnect/restart, and resolve an uncertain result before
allowing a replacement submission. Do not deduplicate legitimate contributions
merely by amount and reason.

### P1 — Legacy correction remains callable and bypasses checked actions

`supabase/migrations/20261007111213_settlement_correction_recovery.sql:64`
delegates to the older public function but does not revoke its authenticated
execution grant. Live verification confirms that the old function is callable.
It infers the correction action from the current state, without an expected
version or explicit action.

Local reproduction: after reversing a covered BOHECO verification through the
new checked function, call the legacy function with the same bill/reason. It
treats the now `handed_over` state as physically returned cash, credits PHP249.40,
and moves the bill to Pay at BOHECO. No cash-return confirmation was supplied.
Old clients/stale calls therefore bypass the new protection. This still requires
an authorized area Admin; it is not an anonymous access vulnerability.

Fix: revoke direct authenticated execution of the legacy function (the checked
security-definer wrapper can still call it), or move it to a private helper.
Require the checked endpoint for client corrections, with a clear old-app update
message. Test both the permission boundary and repeat calls after new evidence.

### P2 — Staff refresh continues every minute while offline

`lib/presentation/common/staff_alerts.dart:139` starts a one-minute timer.
`_refresh` has no connectivity gate, attempts staff alerts, and always refreshes
work providers in `finally`, even when the request fails. `QueryCache.rows`
attempts the network before falling back to saved data. This affects the shared
Admin, Reader, and Cashier gate and explains repeated offline loading attempts.

Fix: skip polling when disconnected, retain the cached screen without repeated
loading, and refresh once on reconnect/resume. A physically disconnected phone
cannot send those requests to Supabase; no quota usage estimate was made here.

## Verified live, read-only

- Reserve rounding index and payment credit implementation are present.
- Admin reserve correction guard is present.
- Checked BOHECO correction endpoint is present.
- No referred records missing a reporting date.
- No negative reserve totals or duplicate regular rounding transaction credits.
- Current settlement counts: one covered bill with money handed over; eleven
  direct BOHECO bills awaiting actual reporting. These states alone are not bugs.
- All active enabled staff have a household link.
- Twenty active households have no login. Review test-data setup before testing
  consumer sign-in; this review did not create credentials or contact numbers.
- SMS queue totals: one sent, three failed. This does not prove current phone
  delivery. Both SMS and billing-cutoff scheduled jobs are enabled.

## Validation and limits

43 focused Flutter tests passed across sync ownership, password-reset sessions,
payment confirmation, settlement screens, and staff notification destinations.
Rollback-only local SQL probes reproduced both accounting findings and retained
the existing correction-recovery assertions. No live balances were changed.

Previous 597-test results are from the earlier fix turn; the full suite was not
rerun for this read-only review. Actual Android SMS delivery, installed APK
version/signature, and physical cash remain phone/reconciliation checks.

Recommendation: fix the two P1 findings before member distribution, then address
offline refresh and perform the short phone acceptance check.
