# Updated overdue workflow

The former **Request authorization → Authorize collection** process is replaced by pondo allocation and BOHECO settlement.

- **Cashier → Remit**: record real pondo, select small bills and confirm allocation with physical cash handover.
- **Meter Reader → Remit**: optionally close collection early, verify pondo payments, confirm referrals and record verified direct BOHECO payments.
- **Cashier → Consumers → Overdue → household**: follow the payment route and collect only full eligible pondo repayments.
- **Admin → Overdue → Pondo / Notices / History**: review funds, correct exceptions, manage notices and preserve history.

Cutoff: **28th at 12 noon PH time**, or earlier Meter Reader closure. Repayments restore pondo and are excluded from repeated BOHECO remittance. Direct payments are verified noncash settlements.

See [rollout and phone checks](pondo_boheco_rollout.md) for dependencies, QA cleanup, accounting and step-by-step checks. Older authorization SQL tests describe the retired flow and are not acceptance checks for this update.
