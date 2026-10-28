# Reserve fund and BOHECO settlement

Collection defaults to the **28th at 12 noon Philippine time**. Admin can change it in **Profile → Settings → Billing schedule**; see [combined schedule](billing_schedule.md). Collection can close earlier when Meter Reader closes the BOHECO trip. Closure pauses unpaid bills for Cashier allocation; it does not claim BOHECO has received cash or a referral.

## Staff steps

1. **Cashier → Remit → Record reserve fund money**: enter the actual opening balance once. Record later contributions and actual withdrawals with a reason. Previous estimated funds are not imported as real cash.
2. **Meter Reader → Remit → Close collection** if leaving early. At the saved cutoff, the server enforces closure automatically. Late-priced bills join an already-closed trip on refresh.
3. **Cashier → Remit → BOHECO trip → Choose bills to cover**: smallest bills appear first. Select bills within available reserve fund, choose the receiving Reader if needed, physically hand over cash, then **Confirm allocation & handover**. Unselected bills become BOHECO referral cases; select none to refer all.
4. **Meter Reader → Remit → BOHECO trip**: confirm each covered payment with receipt reference, payment date and evidence. For uncovered bills, confirm the actual referral, then record verified direct payment when BOHECO confirms it.
5. **Cashier → Consumers → Covered bills → household → Collect repayment**: receive the entire balance and enter cash tendered. The confirmed receipt shows change and replenishes reserve fund. Earlier debts must be settled before current collection resumes.
6. **Admin → Profile → Reports → Reserve fund**: review balances, transactions and corrections. Routine fund entries belong to Cashier. **Admin → Follow-up → Bills** shows trip progress; **Notices** includes Serve a notice and active notice review; **History** retains closed notices, accepting verified BOHECO receipts as evidence. Cashier uses **Current bills**, **Covered bills**, and **Pay at BOHECO**; direct-payment cases are view-only for Cashier. Routine collection authorization is retired. New notices require an overdue unpaid bill with a confirmed direct BOHECO referral. Reserve-covered bills are excluded.

Reserve fund pays the actual cooperative amount, such as ₱249.40. The household repays its rounded bill, ₱250.00. The ₱0.60 stays in reserve fund until a recorded withdrawal. Repayments are Cashier receipts but never money to remit to BOHECO twice. Direct BOHECO payment clears a bill without inventing Cashier cash or a Cashier receipt.

Payment does not automatically reconnect supply. Meter Reader records BOHECO-confirmed disconnection/reconnection separately. BillAlert does not contact BOHECO through an API.

Custom due dates use the monthly cutoff on or after the due date. An August bill due in October remains open until the applicable October trip closes. Dates after the saved cutoff day use the next monthly cutoff. Early closure applies to bills due by that trip's cutoff.

## Rollout

- Review `supabase/migrations/20261004015207_pondo_boheco_settlement.sql` and apply after existing household, staff, overdue and notice migrations. Do not rerun fixture seed migrations in production.
- Back up and reconcile pending Cashier payments on every phone first. Existing approval records remain history, without becoming payments or reserve fund cash. Retire older APKs together with this update; their authorization APIs are disabled.
- Enable Supabase Cron before applying if background closure is required while nobody is online. The billing schedule migration replaces the old monthly job with `billalert-billing-cutoffs`, a one-minute server tick for configured cutoffs. If Cron is enabled later, schedule `select app.run_boheco_cutoffs()` every minute. Snapshot and Cashier payment functions enforce the same cutoff without Cron.
- Build/install the updated APK. No new Edge Function is needed. Financial writes and verification require a connection; saved routes remain readable offline.
- `supabase/checks/pondo_test_reset.sql` defaults to **ROLLBACK**. It retains one overdue bill each for QA02-202610-04 and QA02-202610-07, archives removed unpaid QA records, preserves accounts/current bills/paid history and seeds enough test reserve fund. It refuses deletion of payment-linked rows or settlements beyond unallocated review; review-only cases are archived before removal. Inspect its output before changing the final line to COMMIT. Never use synthetic fund money in production.

## Phone check

1. Cover one retained household and leave the other for referral, even if the fund can cover both.
2. Confirm handover. Check available reserve fund falls by the cooperative amount while household debt remains.
3. Reader verifies BOHECO payment; Cashier receives the full repayment. Check change, replenished fund and unchanged regular remittance total.
4. Reader confirms referral and direct payment for the other household. Check overdue debt clears without a Cashier receipt or reserve fund credit.
5. Retry a completed action and try an action offline. Check no duplicate movement or payment; offline writes are refused. Review any notice against the directly paid household.

Local SQL tests use PostgreSQL 17, synthetic authentication and rollback. Flutter tests cover role actions, narrow layouts, insufficient funds, confirmation, offline refusal and receipt caching. Live Supabase, Cron execution, SMS delivery, concurrent physical-device use and Android layout still need a rollout check. No live SQL has been applied.

Final local validation: 561 Flutter tests passed; 11 focused UI tests passed again after the final consumer statement change. Analysis of lib/test/tools reports no issues. A fresh migration chain and the settlement SQL regression passed; QA reset preview retained two bills and seeded ₱1,000, then rolled back.

If neither of the two pending updates has been applied, run `supabase/checks/apply_reserve_fund_and_billing_schedule.sql` once in SQL Editor instead of running the two migrations separately. It applies both in one transaction, preserves existing data, adds no sample balance, and refuses an installation where either update is already present. Earlier account and notice updates must already exist. User-facing labels use **Reserve fund**; existing internal database keys stay compatible.

### Restored Admin notices
After the reserve fund and billing schedule update, apply `supabase/migrations/20261004060000_referred_disconnection_notices.sql`. This preserves existing notices, validates eligibility again on sync, and queues SMS directing the household to the BOHECO main office. The same notification record appears in the consumer Inbox. Delivery requires the existing SMS worker and a valid household mobile number. No live migration or SMS was sent during development.
