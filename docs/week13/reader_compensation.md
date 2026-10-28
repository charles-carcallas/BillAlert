# Monthly Meter Reader compensation

Apply `supabase/migrations/20261004070000_reader_monthly_compensation.sql` after the reserve fund, billing schedule, and referred-notice updates. No live database changes were made during development.

Cashier: Remit → BOHECO trip → Record ₱500 payout → Confirm cash handed over. The active Reader is preselected when there is one; choose the recipient if there are several. Payouts require a connection and the full ₱500 in reserve. Salary is ₱200 and transportation is ₱300.

Tracking starts October 2026. Each unpaid month reserves ₱500 before household coverage; the actual ledger is debited only on payout. Unpaid months carry forward. One active payout is allowed per area per month, including when staff change. Admin: Profile → Reports → Reserve fund → Correct payout. Confirm cash was never handed over or has been returned, and provide a reason. Reversal restores ₱500 once and makes the month unpaid again.

New Meter Reader bills are payable normally. Previous waived bills remain unchanged and appear in the Admin report under Previous waived bills · Review. Review these individually before deciding on any historical correction.

If October compensation was already handed out before rollout, reconcile it before using the payout button: the opening ledger balance must represent cash BEFORE that recorded payout. Do not deduct the same historical payment from an opening balance that already excludes it. No automatic historical payout or opening balance is inserted by this migration.

Verification: local transactional SQL checks cover reserve protection, payout retries, reversal, roles, cross-area visibility, and normal Reader billing; widget checks cover the fixed payout, insufficient funds and paid state. Physical cash and live SMS are not exercised by these tests.
