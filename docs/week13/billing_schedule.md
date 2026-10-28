# Combined billing schedule

Open **Admin work → Profile → Settings → Billing schedule**. Set the default bill due day, Cashier collection closing day and closing time, then tap **Save schedule**. Time is always Philippine time (UTC+8). The initial defaults are day 28 and noon on day 28. Days 29–31 clamp to the last day in shorter months.

The due day pre-fills new amount forms within the bill's own month. Admin must still check the BOHECO statement and can choose another date. An older bill whose suggested date has passed requires an explicit date; the app never moves its due date to another billing month automatically. Posted dates are never rewritten.

Collection changes apply to the current open month's trip when both its old and proposed cutoff are still ahead. Otherwise they begin next month. A pending next-month change cannot be backdated by another save. Each closed trip retains its scheduled cutoff and actual close time. Meter Reader keeps **Remit → Close collection** to close earlier. Reopening a closed trip is not a schedule action.

A bill due after that month's scheduled cutoff follows the next monthly trip. A delayed bill follows its actual due-date month, not its reading month. Early closure includes unpaid bills due by that trip's scheduled cutoff. Consumer bill details show the effective Cashier deadline when available.

The regular receipt summary retains its existing 29th–28th reporting period for historical accounting. It is labeled as a reporting period, not a handover deadline. Actual collection closure and reserve fund routing follow the saved schedule or earlier trip closure.

Saving requires an online active Area President. Cashier and Meter Reader can read their area's schedule but cannot edit it. Consumers receive their own bill's deadline. Revisions retain actor, version and request ID. Lost-response retries return the original saved revision; a stale version is refused. Tap the refresh icon to reload saved values before editing again. Cached schedules and bill deadlines remain readable offline.

## Apply before distributing the updated app

Apply `supabase/migrations/20261004030427_billing_schedule.sql` after `20261004015207_pondo_boheco_settlement.sql`. This migration contains the new table, RPCs, view columns and schedule-aware trip rules. It neither deletes QA data nor changes reserve fund balances.

With Supabase Cron enabled, the migration replaces the fixed monthly job with `billalert-billing-cutoffs`, running `select app.run_boheco_cutoffs()` every minute. Only elapsed unpaid bills without a settlement case are processed. If Cron is enabled later, create that job then. Without Cron, staff snapshots and Cashier payment preflight still enforce the same deadline when requested. This update has not been applied to live Supabase.

## Physical checks

1. Admin opens the combined settings on a phone, changes the due day and cutoff, and saves once. Reopen to verify the values.
2. Open an unpriced bill in that month. Confirm its suggested date, choose the statement's date instead, and verify posted dates remain unchanged.
3. Check the Cashier and Consumer deadlines use Philippine time. Test collection just before and after the configured cutoff in a disposable QA area.
4. Meter Reader closes an open trip early. Check collection pauses, then change the schedule and confirm the closed trip does not reopen.
5. Turn off the connection. Read the cached settings; attempting Save must make no change.

Local SQL tests use synthetic Auth fixtures and roll back. They verify atomic saves, stale versions, retries, role/area access, short months, frozen trips and early closure. Flutter tests cover the narrow editor, cached saves, offline refusal, default dates and statement overrides. Live Cron and Android interaction still need the physical checks.

Final local validation: 569 Flutter tests passed, lib/test/tools analysis found no issues, and both schedule and reserve fund SQL regression tests passed against disposable PostgreSQL fixtures.

If neither of the two pending updates has been applied, run `supabase/checks/apply_reserve_fund_and_billing_schedule.sql` once in SQL Editor instead of running the two migrations separately. It applies both in one transaction, preserves existing data, adds no sample balance, and refuses an installation where either update is already present. Earlier account and notice updates must already exist. User-facing labels use **Reserve fund**; existing internal database keys stay compatible.
