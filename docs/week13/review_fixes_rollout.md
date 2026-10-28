# Review fixes and rollout

## What changed

- Cashier repayment Cancel/back no longer disposes a focused field during the
  dialog animation.
- Regular collections credit only the rounding actually received to the reserve
  ledger. Retries, change, and remittance handovers do not create extra credits.
- Admin can correct actual cash below the reserved compensation amount, but
  cannot make cash negative. Ordinary withdrawals still protect compensation.
- Reversing a direct BOHECO confirmation restores **Not yet reported** when the
  household was never reported. A real prior reporting date is preserved.
- Existing “referred” records without reporting dates are repaired to await an
  actual report. This does not invent a report or send a disconnection notice.
- Admin can correct a covered BOHECO verification before Cashier repayment.
  The money remains with the Reader and repayment pauses. **Record returned
  funds** is a separate action requiring physical cash return.
- Corrections check the latest record and reject stale screens. Repeating the
  same successful correction cannot reverse newer evidence or credit cash twice.
- Cash already repaid is protected: verification reversal is refused and the
  receipt must be reconciled separately. No automatic refund or receipt deletion
  is introduced.
- Remittance alerts now open the correct staff screen and still reject another
  role's destination.
- Trip screens always offer a month selector, including months with no records.
  Selecting an empty month does not silently display another month's bills.
- Compensation history shows the monthly amount without the salary/transport
  breakdown.

## Apply in this order

The code and migrations are prepared and tested locally. This work has not
applied either migration to the live project.

1. If not already applied, run
   `supabase/migrations/20261007105843_regular_rounding_reserve_credit.sql`.
2. Run `supabase/migrations/20261007111213_settlement_correction_recovery.sql`.
3. Build and install the updated app, preserving the installed app's signing key.
   For the existing debug installation:
   `flutter build apk --debug --dart-define-from-file=env.json`.

These follow the existing compensation and automatic BOHECO routing migrations.
Do not rerun older setup/reset scripts to apply this patch. The new correction
screen needs the second migration before it can save corrections.

Historical rounding is not automatically added: it may already be included in
opening cash. Use `supabase/checks/regular_rounding_reconciliation.sql`, compare
against actual cash, and correct only a verified difference.

## Short phone check with test households

1. Cashier → Covered bills → Collect repayment → enter cash → Cancel, then repeat
   using Back. No receipt should be created.
2. Collect PHP250 on a current PHP249.40 cooperative bill. The fund increases by
   PHP0.60 once; refreshing does not add it again.
3. Reader → Remit → BOHECO trip → verify a direct test payment before reporting.
   Admin → Follow-up → Pay at BOHECO → Settled bills → Correct verification.
   It returns to **Not yet reported**. Reader completes the trip with that
   household included; Admin can then serve an eligible overdue notice.
4. For a covered test bill verified but not yet repaid:
   Admin → Profile → Reports → Reserve fund → Correct verification.
   Cash stays with Reader, the fund balance stays unchanged, and Cashier cannot
   collect repayment. Reader verifies the correct receipt to resume repayment.
   Use **Record returned funds** only when cash was physically returned instead.
5. Select a month with no trip in Pay at BOHECO and Remit. Confirm the empty
   message and switch back. Tap a remittance alert on each staff phone.

## Remaining release preparation

The earlier live review found 20 active QA households without logins/contact
numbers. These are data setup gaps, not records this patch deletes or invents
contact numbers for. Run `supabase/checks/account_setup_inventory.sql`; choose
linked test accounts with real authorized test phone numbers for login/SMS
checks. The reviewed backfill helper is `tools/backfill_household_logins.ps1`.

Verify actual SMS delivery and offline restart/sync on the installed APK before
distributing it. Local tests cannot prove phone delivery or live cash balances.

## Automated verification

597 Flutter tests passed and `flutter analyze --no-pub lib test` found no issues.
Local rollback SQL suites passed for correction recovery, regular rounding,
automatic BOHECO routing, and Reader compensation. They cover cross-role/area
refusals, stale corrections, retries, retained evidence, restored notice
eligibility, repayment protection, partial payments, and compensation guards.
