# Repayment dialog and reserve accounting fixes

The Cashier repayment dialog keeps its amount controller alive until the closing
animation finishes. Cancel and back navigation with a focused amount field are
covered by regression tests.

## Database update

Run `supabase/migrations/20261007105843_regular_rounding_reserve_credit.sql`
once in Supabase SQL Editor, after the existing automatic-routing and monthly
compensation migrations. The application fix also needs an updated APK.

New regular receipts automatically credit the rounding actually collected to the
reserve ledger in the same transaction as the payment. A PHP250 payment against
a PHP249.40 cooperative amount credits PHP0.60. Cash tendered and change do not
affect the credit. Partial payments credit rounding only as it is received.
Receipt retries and remittance handovers do not credit it again. Covered-bill
repayments still credit their full amount once; direct BOHECO payments add no
Cashier cash or reserve money.

Admin balance corrections may record actual nonnegative cash below pending
compensation. Cashier withdrawals and new coverage still protect unpaid
compensation; paying compensation still requires the full PHP500.

## Existing money

Existing receipts are deliberately not backfilled, including when an old receipt
is retried. Previous rounding may already be included in opening cash or another
manual entry. Run `supabase/checks/regular_rounding_reconciliation.sql` for a
read-only receipt list, reconcile it with physical reserve cash and its ledger,
then use Admin's balance correction only for a confirmed difference. Do not add
the listed total blindly.

## Phone check

1. Cashier → Covered bills → Collect repayment → enter cash → Cancel. Repeat
   with the phone's back button. Both should close cleanly without a receipt.
2. Note the reserve balance. Collect PHP250 for a current test bill priced at
   PHP249.40. Refresh the fund: it should increase by PHP0.60, with one
   “Rounding from regular collection” entry linked to the receipt.
3. Refresh again; the credit must not repeat. Covered repayments should still
   replenish the full debt exactly once.

Local SQL tests cover full/partial/integer payments, change, duplicate receipts,
handover, direct payments, covered repayments, correction permissions and salary
protection. Live cash and SMS delivery are not exercised by these tests.
