# BOHECO full Meter Reader waiver

Implemented in `20261002064728_reader_boheco_waiver.sql`, created using installed
Supabase CLI 2.117.0 through Node/npx offline. Apply **after**
`20261002064410_account_lifecycle.sql` and the existing disconnection migration.
No existing migration was edited by this worker.

## UI / RPC contract

- `fn_assign_reader_waiver(p_reader_id uuid, p_consumer_id uuid, p_start_month date)`
  returns one `reader_waiver_assignments` row. Start must be the first of the
  current or a future Manila billing month. Active enabled same-area Admin only.
- `fn_end_reader_waiver(p_assignment_id uuid, p_reason text)` returns that row.
  Requires a reason. Repeating an end preserves the original ending evidence.
- `fn_reader_waiver_history(p_reader_id uuid)` returns assignment rows, newest
  first. Readable by the reader themself or same-area Admin/Cashier through RLS.

Assignment fields: `id`, `reader_id`, `consumer_id`, `area_id`, `meter_serial_no`
(snapshot), `start_month`, `assigned_by`, `assigned_at`, `ended_at`, `ended_by`,
`end_reason`. One unended assignment per reader and household. End before replacing.

`consumers.profile_id` must point to the reader. Reader role stays `meter_reader`;
account status must be active and `staff_enabled` true. Household must be active,
in the same area, and use the designated meter. No additional profile role.

Lifecycle integration needs **no waiver calls from the main migration**. Waiver
triggers automatically end assignments when reader role/area/status/staff-enabled
changes, or household profile/area/meter/status changes. Reactivation does not
restart an ended assignment. The mutation RPCs acquire `app.lock_own_area()`
before authorization; posting retains the main area-lock prelude and then locks
reader profile, household and assignment. Ending triggers do not acquire area
locks late. Remittance-recipient lookup requires `staff_enabled`.

## Financial semantics

Only a bill first priced while an assignment is eligible, in or after its start
billing month, receives coverage. Existing priced bills are never backfilled;
older unpaid bills remain payable. An earlier reading awaiting an amount can
qualify if its billing month is eligible. This is the deliberate interpretation
of future billing coverage: eligibility is evaluated at initial amount posting.

`total_amount` remains the rounded bill; `cooperative_amount` retains the original
BOHECO amount. `waiver_amount` equals the full rounded bill, `amount_paid` stays
zero, `balance` is zero and `status` is `waived`. `waiver_assignment_id` and
`waived_at` retain the audit link. Covered bills cannot be edited or deleted,
including through cascading household/reading deletion.

No payment, receipt or remittance cash is generated. Covered demand is excluded
from outstanding bills, collection progress, reminder views and rounding-fund
gap. The existing PHP 300 salary cap/formula is unchanged; waiver does not count
as salary or fund income. Posted cash and frozen past handovers are untouched.
Notice review includes coverage evidence and permits that evidence in settlement
readiness without requiring a synthetic receipt. Ordinary debts still need real
cash evidence. Bill-ready messages explicitly say BOHECO covered the full bill.

## Flutter integration and owned files

- `lib/domain/entities/bill.dart`: parses waiver fields; `isWaived`, zero balance,
  not payable, settled but status label `Covered by BOHECO`.
- `lib/data/repositories/bill_repository_impl.dart`: requests waiver fields,
  excludes waived payment selections; saves waiver metadata in existing
  account-cleared `cached_queries` alongside bill cache transactions.
- `lib/presentation/consumer/bill_details_sheet.dart`: original amount, actual
  cash received, separate coverage line and coverage progress wording.
- `lib/presentation/consumer/current_bill_screen.dart` and `history_screen.dart`:
  distinguish covered bills from paid bills in current/history labels.
- `test/domain/bill_waiver_test.dart`, `test/data/bill_waiver_cache_test.dart`,
  `test/presentation/consumer/bill_waiver_display_test.dart`.
- `supabase/tests/reader_waiver_test.sql`.

No Drift schema/generated file change. This app build requires the waiver
migration: missing financial fields fail instead of silently treating covered
bills as collectible. Pre-upgrade cached bills have no waiver and keep their old
semantics until refreshed. Normal sign-out/account-switch cache clearing covers
the new metadata too.

Assignment/history contract was sent directly to UI agent
`01a0fb5b-1519-7a52-9021-7ad016566d70`. Consumer current-bill/history label changes
were coordinated with that agent and completed by this worker.

## Verification

Local only: `127.0.0.1:55489`, database `waiver_test`, recreated from main's
`billalert_accounts_final`. Waiver migration applies cleanly. Waiver SQL suite,
existing disconnection-review suite and overdue/staff suite passed and rolled
back fixtures. They cover authorization/area isolation, duplicate assignment,
backdating refusal, full coverage, older debt, immutable bills, cash rejection,
correct collection/rounding figures, lifecycle auto-ending, notice evidence and
disabled remittance recipients.

Flutter: 30 passing focused tests across the final runs: 22 domain/repository/
details, one offline coverage, and seven waiver/current-bill widgets. Static
analysis is unverified: Dart Analysis Server crashes on shutdown deleting its own
AppData/Local/Dart/perf file (Windows error 1920). Focused test builds compile
successfully. No live SQL, deploy, commit or push performed.

