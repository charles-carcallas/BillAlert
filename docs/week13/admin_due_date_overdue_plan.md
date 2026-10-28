# Admin due-date default and overdue collection plan

Implemented locally, 2 October 2026. Migrations await review and approval.
See `implementation_report.md` for verification and rollout limitations.
The design and baseline analysis below are retained as the implementation specification.
Companion to `offline_sync_staff_alerts_plan.md`.

## Decisions and boundaries

User-confirmed policy:

1. Block current-month payment until Admin resolves the overdue bill.
2. Admin authorizes collection; Cashier records the actual payment.
3. New payments, approvals and eligibility checks require internet.
4. Approval lasts until used or revoked, provided the balance stays unchanged.
5. Legacy operations without provable ownership are preserved and quarantined;
   they need manual receipt reconciliation before any recovery upload.

Planned interpretation: authorization permits overdue collection; it does not
clear debt. The current payment remains blocked until the overdue balance is
actually settled on the server. Overdue collection uses a separate authorized
workflow and receipt. Do not automatically bundle arrears into current billing.
Default implementation settles the approved overdue balance in full. Partial
settlements or exceptions require an explicit later decision; any unpaid
overdue balance continues to block current payment.

## A. Default due date when Admin posts an amount

Recommendation: prefill the 28th of the bill's billing month, editable and shown
on the confirmation. For the normal workflow this is the current month's 28th.
Use the bill's cycle rather than the month when the form happens to be opened.

| Situation | Proposed behavior |
| --- | --- |
| October reading, amount posted October 21 | Prefill October 28, 2026 |
| Amount posted October 28 | October 28 is valid; show that it is due today |
| October amount first posted October 29 | Require Admin to choose a valid date from the statement; explain the usual date has passed |
| September reading priced in October | Keep September billing month; require an explicit date if September 28 has passed |
| Admin changes the due date | Preserve their choice through rebuilds, validation and confirmation |

Keep Philippine dates consistent through `PhClock`/`PhDate`; the existing picker
uses device-local `DateTime.now()` and initially offers today plus 14 days.
Keep due date required. Preserve the present rule against posting a past due
date until a separate late/backdated billing policy is approved. Never
automatically roll the due date forward at upload time: retry the captured choice
and report any server refusal. Handle an open draft that crosses midnight.

The default itself need not count as a user edit in the unsaved-changes prompt.
Show billing month, cooperative amount, rounded total and chosen due date in the
confirmation. Changing due date must not move a bill into another cycle.

Scope: `_AmountFormState`, date picker and confirmation in
`lib/presentation/admin/post_bill_amount_screen.dart`, with a small testable
default-date helper using the bill cycle and injected Philippine clock.
Use-case/server validation remains authoritative. This default alone does not
require a live database migration.

## B. Define overdue separately from billing month

Proposed definition, consistent with the current `Bill.isOverdueOn`:
priced bill + positive remaining balance + Philippine date after due date.
Paid bills leave the actionable overdue list but remain in history.

- October bill due October 28 becomes overdue October 29, while still labelled October.
- September bill due October 8 is an earlier bill on October 2, but not yet overdue.
- A partial payment leaves only the unpaid balance overdue.
- An unpriced bill is awaiting its amount, not overdue.

Current-month and overdue lists must be disjoint. An overdue October bill goes
to Overdue even before November begins. Provide an Earlier bills/not-yet-due
section if custom due dates create that case; do not hide payable debt entirely.
Historical views and the Consumer's total outstanding balance remain accurate.

Reminder timing is independent: the configured three-days-after-due reminder
does not postpone the overdue date. Automatic overdue SMS is currently disabled
in the user's last supplied settings; this plan does not enable it.

## C. Cashier and Admin workflow

Cashier: add clearly labelled Current billing and Overdue sections under
Consumers/collections, avoiding a fifth bottom navigation destination. The
current bill card contains only that month's amount. Show an arrears warning
with a link to the separate Overdue screen. The latter lists month, due date,
remaining balance and Admin resolution state; ordinary Cashier bill checkboxes
must not select arrears directly.

Example: September has a 500-peso overdue balance and October has a 600-peso bill.

1. Cashier Current billing shows October, 600 pesos, with collection disabled:
   "Overdue balance needs Admin clearance and payment first."
2. Cashier Overdue shows September, 500 pesos, read-only pending approval.
3. Admin opens the area's Overdue management view, reviews the bill and selects
   Authorize collection. Record approver, time and exact approved balance.
4. Cashier refreshes Overdue and uses Collect approved payment for September.
   The approved bill and amount are fixed; no ordinary arrears checkbox.
5. The server records the 500-peso payment and receipt atomically, consumes the
   approval, and updates the balance. An approval must not be usable twice.
6. After all overdue balances are cleared, October's 600-peso collection unlocks.
   Record it as a separate payment/receipt and preserve both in history.

Add Admin Overdue as a clearly labelled management view (for example, alongside
Notices), while retaining the existing disconnection notice workflow. Admin
authorization does not add payment-collection permissions to the Admin role.

Distinguish these states in labels and data:
- Unresolved overdue: debt remains.
- Authorized for collection: debt still remains; an approval is not money.
- Payment pending upload: locally recorded but not yet server confirmed.
- Partially paid: only the remaining balance remains due.
- Settled: an accepted payment accounts for the full balance.

Do not make an Admin button simply set the bill to paid or delete arrears.
Record payment allocations and a receipt with actor, time and amount. Waivers,
corrections and external BOHECO payments, if required, need separately approved
accounting rules and evidence; they are not presumed in this plan. Closing a
disconnection notice is not proof that a bill was paid.

## D. Server and offline enforcement

The current `BillRepositoryImpl.payableFor` fetches all priced unsettled bills;
the controller can select any or all of them. `fn_record_payment` validates bill
balances but does not enforce an Admin overdue-approval rule. UI filtering alone
would leave older APKs and direct RPC calls able to bypass the new restriction.

Prepare a migration for the required approval record
and collection checks. Scope approvals to bill, household, area, allowed amount,
approver and state; make their use atomic with payment recording. Revalidate all
relevant balances and approvals under transaction locks, including competing
settlements and expiry/revocation. Preserve client UUID idempotency and exact
receipt lookup. Restrict decisions to the area's Admin and collection to the
authorized role; test role and cross-area denial.

Preserve consumer payment history, allocation totals, BOHECO remittance and
rounding-fund calculations. Count actual received cash once; authorization or
moving a bill between screens creates no cash entry. Explain the migration and
obtain user approval before any live database edit. Verify deployed definitions
first; this repository review is not a live-server audit.

Recommended first implementation: Admin approval, overdue checkout and current
payment eligibility checks require a connection. Offline views may show cached
balances with a saved-at time, but must not assert a current approval or that
all arrears are cleared. This restricts offline current-month collection until
a safe offline protocol is designed. This changes the existing offline payment
contract and must be stated
to testers before implementation. Never accept cash under an offline promise
that the server may reject because another device changed the approval.

Preserve existing queued payments during rollout. Do not retrospectively mark
them successful, discard them, or silently recollect the amount. Agree how
pre-change operations are reconciled before enforcing new rules.

## E. Delivery phases and tests

1. Use the confirmed block-until-settled and Admin-authorization policies.
   Confirm the proposed online-only restriction before implementing payment flows.
2. Implement the editable 28th default independently, with date-boundary tests.
3. Implement separate lists and clear balances; update domain/repository queries
   and cached-data freshness without removing debt from totals/history.
4. Implement Admin authorization and server checks for overdue-first settlement.
5. Integrate exact-operation payment status, account-owned outbox and refresh
   fixes from the earlier audit. Refresh both lists after settlement.
6. Test locally, present the migration for approval, then run a controlled
   multi-role phone rehearsal and distribute the updated APK.

Acceptance scenarios:
- October 21/28/29 posting; February and December/January boundaries; delayed
  September pricing; manual override; a draft open across midnight.
- September due October 8 vs September due September 28 on October 2.
- Current-month bill becoming overdue on the 29th; partial and fully paid bills.
- Current payment remains blocked after authorization and unlocks only after
  all overdue balances are settled; exact totals are shown before accepting cash.
- Cashier cannot bypass Admin controls via RPC or an old APK; other area's
  Admin cannot approve; duplicate submissions return the original receipt.
- Revoked approval, two concurrent Cashiers, network loss before/after acceptance,
  role switching, legacy queued payment and exact receipt reconciliation.
- No payment-history loss, no extra rounding income and no double-counted remit.

Implementation and current test evidence are recorded in `implementation_report.md`.
The accepted online-only payment policy supersedes the earlier offline cash contract.
No live SQL or deployment was performed.
