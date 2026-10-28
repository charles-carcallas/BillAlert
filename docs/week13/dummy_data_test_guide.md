# Dummy-data test run

Run `supabase/checks/dummy_test_data.sql` in the Supabase SQL Editor as one complete script. It targets the existing active Admin `mario.ombajin`; edit `admin_username` if necessary. The Admin's area must already have an active Meter Reader and Cashier. All reviewed migrations through `20261002151432_staff_assignment.sql` are required.

The file commits **12 new test households, 11 bills, 3 receipts and 3 notices**. It preserves existing accounts and records. These are ordinary test records visible in the app: **they add to collection totals, receipt history, rosters, staff alerts and Remit figures in that area**. Use this in your testing project, not a production billing database.

Dates use the current Philippine month and the previous month. On October 3, 2026 the prefix is `QA01-202610`, the current cycle is October and the overdue cycle is September. Receipt dates are the time the script runs. Existing calendar cycles are reused; closed or incompatible cycles stop the script. The file makes no changes to settings, cron jobs, Edge Functions, Auth users, passwords or existing household links. It generates staff inbox alerts through the existing triggers.

## Run it

1. Run the whole SQL file. For a preview only, replace its final `commit;` with `rollback;` before running.
2. Check the 12-row result. An error stops the transaction; do not run selected fragments.
3. Refresh the app while online on each test device. Search `QA01` or the `Test` household names.
4. Continue with the cases below. Running the same batch again is deliberately refused, so it cannot overwrite completed tests. Changing `batch_label` to `QA02` creates an additional full batch; it does not reset `QA01`.

## Household cases

All names begin with **Test**. All contacts and login links start empty. The suffix is the end of the consumer number (for example `QA01-202610-03`).

| Suffix / name | Starting state | Test |
|---|---|---|
| 01 · New Reading | No reading or bill, opening reading 0 | Meter Reader records 100; Admin posts cooperative amount 349.40; bill becomes 350; Cashier collects 350. |
| 02 · Awaiting Amount | Current unpriced bill, reading 100 | Admin posts an amount and confirms the suggested due date against the test statement. For SMS, add your own test number before posting. |
| 03 · Current Unpaid | Current bill 350, balance 350 | Consumer views bill; Cashier records full payment; Consumer checks receipt/history. |
| 04 · Overdue Block | Previous bill 350 plus current bill 350 | Try current payment: it must be blocked. Cashier requests authorization for the older bill; Admin approves; Cashier pays older 350, then current 350. Also test revoke before payment. |
| 05 · Partial Payment | Bill 500, receipt 200, balance 300 | View the existing receipt; collect the remaining 300. This is a historical partial-payment fixture, not permission to enter a new partial payment through the current app. |
| 06 · Paid History | Bill 800, paid 800 | Paid history, receipt details, collections and Remit. No amount remains collectible. |
| 07 · Active Notice | Older unpaid bill 350, active notice | Review covered bill and waiting period; request/approve overdue collection; collect 350; Admin reviews receipt and closes as settled. |
| 08 · Ready To Close | Older bill paid 350 after its notice, active notice | Admin sees receipt-backed closure readiness and closes as settled. |
| 09 · Closed Notice | Cancelled notice, older bill still owing 350 | Closed notice history; cancellation does not erase the debt. Can also be used to issue a new notice through the app. |
| 10 · Due Reminder | Bill 350, due today plus configured reminder days | After linking a consumer login, test the scheduled pre-due phone alert. Delivery depends on permissions, the configured reminder time and Android background scheduling. |
| 11 · Reader Coverage | Current unpriced bill | If the Reader has no household, link this household through their account details. Admin records BOHECO coverage from the current month, then posts 529.40. Expect full noncash coverage of the rounded 530, no cash receipt. |
| 12 · Household Handover | Empty household | Create sign-in, reset password, disable/enable login, or reviewed household handover with separate test identities. |

## Consumer login and SMS

Choose the specific test household in **Manage accounts → Households → ⋮ → Create sign-in**. Use a distinct test username and the temporary password shown by the app. Sign in as that consumer and change the password. Creating an unrelated new consumer account would create a different household, so it will not show these seeded bills.

For case 11, use **Manage accounts → People → Meter Reader → Set up household → Choose existing** instead of creating a separate consumer login. If the Reader already has a linked household, keep it and test coverage there through the normal reviewed flow. Do not replace a real household link merely to attach a fixture. Do the same for Admin/Cashier Work/My household tests using an available unlinked test household.

The script contains no mobile numbers and inserts no SMS queue rows. It does insert pending app alerts. To test real SMS, add your own consenting test phone number to case 01 or 02, ensure the existing SMS cron is active, and post the amount **through the app**. Check the actual phone and notification delivery status. Adding a number after a seeded bill was already posted does not itself create a bill-ready text. The script leaves existing SMS work and schedules alone.

Case 10 prepares the bill condition for the reminder; SQL cannot guarantee a phone popup or full-screen display. Test urgent alerts on supported Android devices with notification permission, the Profile switch and full-screen access where supported. If today's reminder time has passed, scheduling may move to the next background run according to the app; verify actual behavior rather than claiming a pass from the database state.

## Functions that must be exercised in the app

| Function | How to test |
|---|---|
| Online reading → posting → payment | Use case 01 end to end. Confirm one reading/bill per cycle, correct rounded/cooperative amounts, notification and receipt. |
| Offline reading and sync | First load case 01 online. Turn off connectivity, record its reading once, reopen the saved work, reconnect and sync. Verify exactly one bill. Use a fresh app-created household for a second run. |
| Offline Admin posting | Open case 02 online, disconnect, post the amount, inspect pending work, reconnect and sync. Verify the server saved the intended amount once and then notified the household. |
| Offline Cashier | Load case 03 online, disconnect and attempt collection. Payment must be blocked with an honest connection message; no receipt or cash-payment upload should be invented. Reconnect and collect once. |
| Rejected sync / account ownership | With disposable test identities, save a Reader operation offline, then end/replace their work access on another online Admin device. Reconnect the original device and verify rejected work remains reviewable and never uploads as the replacement. Do not claim reconciliation while work is pending. |
| Consumer cache | Open bill/history/inbox online, disconnect and reopen. Confirm cached data and its saved-state indicator. Clear no app storage while unsynced work exists. |
| Staff inbox | Refresh existing staff logins after seeding. Then perform a fresh reading, post and overdue request/approval; verify role-specific events and in-app/phone delivery. SQL fixtures alone do not prove delivery. |
| Receipts / change | Use a fresh payable bill; tender more than its balance. Check total, change, allocation, receipt number and consumer history. Seed receipts use exact tender amounts. |
| Remit / remaining gap | The fixtures include 1,350 in synthetic receipts. Remit combines these with existing area receipts and unpaid bills. Verify BOHECO share and remaining gap, then record the handover when finished collecting. Handover is allowed once per area/remittance month; an existing handover is preserved and cannot be repeated. Payments after the 28th fall under the app's next remittance month. |
| Reader compensation | Verify only permitted roles see the cash rounding share and that the gap is accounted for. This small batch does not reach the 300 cap; the automated database tests cover that rule. |
| Create accounts / temporary password | Create a new consumer through New account, then sign in and change its temporary password. Test duplicate usernames and consumer numbers. Seed data does not create Auth credentials. |
| Password reset / disabled login | Use a disposable consumer login, reset it from Admin, and verify the old device signs out after its session check. Verify disabled login cannot access data. Restore it through Admin. |
| Staff replacement | Finish syncing first. Manage accounts → Staff → Change. Test selecting an existing eligible identity and creating a new one, then confirm. Check outgoing work access ends, incoming work begins, and history keeps its original authors. |
| President transfer | Perform last, with a separate tester identity. Nominate, have the successor change their password and accept, then complete from the current President. Completion changes who has Admin access. |
| Household handover | Use case 12 and disposable logins. Test reviewed same-household continuity separately from unrelated occupant handover; inspect retained old history and opening reading. |
| Profile and devices | Theme, password change, phone-number validation, fingerprint unlock and Work/My household visibility need interactive checks. A staff login without a household must not open household mode. |

Do not treat changing timestamps, creating Auth rows by SQL or marking notifications sent as evidence that these functions work. Record actual results from each role/device. Do not run the old beta reset scripts to repeat a case: they have a much broader deletion scope.

## Local verification

The SQL was executed against an isolated PostgreSQL 17 database with the repository migrations applied. The initial insertion succeeded, and a repeat run was refused. Receipt total: 1,350; bill count: 11; newly queued SMS: 0. Under authenticated Admin access, notice 07 was active/not ready, notice 08 was active/ready to close, and notice 09 was cancelled. A separate rolled-back workflow test passed reading capture, amount posting, overdue payment blocking, request/approval, older-then-current payment, partial-balance settlement, ready-notice closure and remittance summary access. Posting for a household without a number produced no pending SMS. Live Supabase execution, Auth login, Edge Functions, SMS delivery and physical-device behavior remain for your test run.

This is a manual data-only fixture, separate from schema migrations, consistent with [Supabase's seed-data guidance](https://supabase.com/docs/guides/local-development/seeding-your-database).
