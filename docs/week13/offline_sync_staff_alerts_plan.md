# Admin and staff offline, sync and notifications: implementation plan

Implemented locally, 2 October 2026. Database migrations await review and approval.
See `implementation_report.md` for current tests and rollout. The defect descriptions
below document the pre-change baseline, rather than the resulting implementation.
The user accepted the staff events and online-only payment proposal.

## Scope and evidence

The user will rehearse the full flow, starting as Admin and creating the other
accounts. Existing rehearsal accounts and transactions must be preserved.
This review inspected repository code and ran 51 existing focused Flutter tests;
all passed. The findings below come from code paths those tests do not fully
cover. They are not claims of reproducing the problems on a physical phone.

No live SQL, deployment, cleanup, commit or backend configuration change was made.
Supabase tools are not exposed in this chat, despite the user's account connection,
so live schema, policies, logs and deployment versions remain unverified.
Before any live database edit, explain the exact change and obtain approval.

## Confirmed implementation defects

### 1. Queued work is not owned by its creator (high priority)

`lib/data/local/tables.dart` stores no profile/area owner on `OutboxRows`.
`AuthRepositoryImpl.signOut` clears caches but preserves the outbox, and
`AuthController.signIn` immediately drains it with the newly signed-in session.
`SyncService.stop` cancels the connectivity subscription, not an ongoing drain.

Result: switching roles with pending work can retry someone else's operation.
Different permissions may reject it; another authorized staff account could
upload it with incorrect attribution. SQL reading/payment functions use the
current authenticated user as the actor.

Fix: persist creator profile, area and role on every operation; filter pending
queries and badges by owner; pause submission across sign-out/account changes.
Keep unsent work for its original owner. For legacy ownerless rows, quarantine
until ownership is established; do not assign them to whoever signs in next.
Use a session generation token and await/cancel the drain safely on sign-out.
Allow a request already submitted to settle without starting another under a
different account. Reset in-memory providers on identity changes as well.

### 2. Sync concurrency and retry lifecycle are incomplete (high priority)

`lib/data/sync/sync_service.dart:80` checks `_isDraining` before awaiting
connectivity, but sets it only afterwards. Two callers can both pass the check
and drain the same queue. A busy caller otherwise receives `nothingToDo`, which
can misleadingly become "Nothing waiting to sync".

Status-write results from `markSyncing`, `markSynced` and `markFailed` are ignored.
The queue is captured once; work enqueued during the pass may be left behind.
Only connectivity changes trigger automatic retries: returning to the app checks
the session but does not explicitly drain staff work. Recovery of internet on
the same Wi-Fi link may not create a connectivity event. The WorkManager task
checks Consumer alerts only; it does not synchronize staff work.

Fix: acquire the drain guard before any await; return a shared drain future;
request another pass for newly queued work; inspect every persistence result;
trigger bounded retries on startup, resume, and confirmed network recovery.
Show failed items distinctly and provide explicit retry/recovery. Do not promise
uploads while the app is closed unless a separate background sync worker is
implemented and tested with the encrypted database and session ownership.

### 3. Cashier can show the wrong receipt and queue a repeated payment (high)

`lib/presentation/cashier/record_payment_controller.dart:294` ignores the sync
outcome and fetches household history. `_fetchReceipt` selects `value.first`.
`PaymentRepositoryImpl.historyFor` can return previously cached receipts offline.
Consequently an old receipt can be displayed as proof of a newly queued payment.
Server rejection can also be presented as "queued" instead of a failure.

`RecordCashPayment` validates against cached bill balances but does not reserve
amounts already queued. Starting another payment offline can offer the same
balance again with a new UUID. Server checks may reject the later submission,
but they cannot undo cash the cashier has already accepted twice.

Fix: return the operation UUID from enqueue; track its actual status and returned
transaction ID; retrieve that exact receipt. Reserve queued allocations locally
and show pending payments against affected bills. Preserve reservations across
restart, and reconcile accepted, rejected and uncertain submissions explicitly.
An offline confirmation is a pending payment acknowledgement, never an official
receipt until that exact operation is accepted.

### 4. Admin post status incorrectly includes completed operations (high)

`lib/presentation/admin/post_bill_amount_controller.dart:214` uses `all()` and
discards status when collecting bill IDs. `post()` uses the same set for
`stillWaiting`, so even successfully synced posts can say "waiting to sync".
Rejected posts stay hidden from the actionable list without a repair path.

Fix: separate pending/syncing, failed and synced operations. Derive confirmation
from the current UUID. Show queued and failed posts in a recoverable section;
never silently hide a server failure. The notice controller also ignores the
drain result: retain the locally captured service event, but distinguish saved
locally, server accepted, and rejected in its confirmation.

### 5. Profile's queue status can be stale or falsely empty (high)

`lib/presentation/common/profile_screen.dart:24` uses a one-shot FutureProvider,
not `watchAll()`, and converts a queue-read failure into an empty list.
The page and sign-out dialogue can then claim everything was sent.
The displayed item list omits each entry's `lastError` and has no retry control.

Fix: expose an owner-scoped reactive outbox stream; distinguish loading, unknown,
pending, syncing and failed; show safe failure messages and Retry. Re-read status
before sign-out. A database-read failure must never equal "all synced".

### 6. Reader and Cashier screens do not reliably reconcile after sync (high)

The Reader invalidates its roster immediately after saving, before asynchronous
upload completes. Manual `RosterController.syncNow` reloads local data without
fetching the server roster. Synced readings are excluded from queued reading
keys, but the cached household can still say it has not been read: a household
can return to the remaining list until a server refresh.

Only the Admin amount controller subscribes to sync reports. Cashier payment and
receipt controllers do not. They are persistent NotifierProviders and read auth
imperatively, so account changes do not themselves rebuild their state. Cached
disk cleanup does not clear these in-memory states.

Fix: reconcile successful reading submissions into local roster state, refresh
affected server data, and retain local acknowledgement until the server confirms
it. Invalidate/update payment lists, receipts, notices and remittance after
relevant successful operations. Scope persistent controllers to identity and
ignore results from a previous session. Refresh visible staff data on resume;
add a modest foreground polling interval for changes made on other phones.

### 7. Repost recovery ignores the original cooperative amount (medium)

`SupabaseOutboxGateway._samePostOnServer` compares only rounded total and due date.
Two cooperative amounts such as 529.10 and 529.40 both round to 530.00; the
fallback can wrongly accept the mismatch, which changes rounding-fund accounting.

Fix: compare `cooperative_amount` when known, and preserve uncertainty for legacy
operations. Prefer a server operation UUID for posting, with atomic replay of
the original result, if a database migration is approved.

## Notifications: missing feature versus bugs

`RoleShell` wraps only `ConsumerUser` in `PhoneAlertsGate`, and
`SupabaseAlertFeed.signedInHousehold` explicitly selects a household by profile.
Admin, Reader and Cashier tray alerts are not currently implemented. They cannot
be enabled by toggling the SMS cron. The Consumer's alert must not be reused or
marked read/sent on behalf of staff.

Proposed initial staff behavior:

| Recipient | Event | Destination |
| --- | --- | --- |
| Admin | Reading accepted, amount needs posting | Amounts |
| Cashier | Bill amount posted, ready for collection | Consumer's payable bills |
| Reader | Household assigned/created in their area | Readings |
| Any staff member | Their upload rejected or later accepted | Sync status |

First implement accurate in-app status and refresh. Staff phone alerts require
an agreed event list and recipient-scoped persistence: event ID, recipient,
area, safe payload, timestamp and read state; deduplicate at creation and on
device. A separate staff feed with RLS is preferable to broadening access to
Consumer notifications. Consider multiple devices and role changes explicitly.
Foreground polling fits the existing design; background notifications remain
best-effort and must not be advertised as instant. A push service would be a
separate architecture decision. Meter Reader alerts must not expose pay/fund data.

## Intended offline behavior

| Action | Expected behavior |
| --- | --- |
| Create staff/Consumer login, new household, reset password | Online required; clear message; no claim that it was queued |
| View previously loaded staff screens | Cached result with freshness indication; distinguish empty from never loaded |
| Record reading, post amount, record service of notice | Save durably with creator and UUID; show pending state |
| New cash payment | Online eligibility check required; retain UUID and pending acknowledgement if the submission becomes uncertain; never fabricate a receipt |
| Record remittance handover | Online required; no success on connection failure |
| First sign-in on a new installation | Requires connection |
| Resume an already cached account offline | Existing offline unlock rules; no cross-account data |

Accounts needing signal is intentional and already has tests. It is not evidence
that all offline behavior is broken. `QueryCache` returns cached rows without
freshness metadata; extend its result so staff screens can label saved answers.

## Implementation order and acceptance checks

1. **Owner isolation and drain lifecycle.** Local Drift migration, repositories,
   sync service, auth integration. Tests: simultaneous sync calls submit once;
   enqueue during drain gets another pass; sign-out mid-drain stops subsequent
   operations; role B cannot submit role A's work; original owner can resume;
   DB status-write failure remains visible.
2. **Payment correctness.** UUID-specific receipt lookup and pending allocations.
   Tests: prior cached receipt is never shown for a new offline payment; lost
   response retries the same UUID; re-entry after restart cannot collect the
   same reserved balance; genuine server rejection is shown with recovery.
3. **Admin/Reader/Profile correctness and refresh.** Realistic persisted outbox
   tests for synced vs pending confirmation, reactive badges, unknown status,
   roster reconciliation, identity changes and stale request completion.
4. **Staff notification feature.** Agree events above; prepare migration and RLS
   tests for recipient/area isolation, duplicates and unauthorized access.
   Explain changes and obtain approval before applying anything live.
5. **Phone rehearsal and release.** Test on the intended Android devices, rebuild
   with an increased build number, then distribute the verified APK. No cleanup
   of the user's new accounts is needed for the review or fixes.

Phone scenarios: switch Admin -> Reader -> Cashier on one phone; airplane-mode
capture then reconnect; Wi-Fi with no internet then recovery on the same link;
background/resume; kill/reopen with unsent work; try a second payment while the
first is queued; verify another phone's data refresh; test denied notifications.
Use October 2026 readings and October 28 due dates for this rehearsal. Confirm
one server operation/receipt per UUID and exact creator attribution.

## Verification limits and follow-up server checks

The 51 tests passed for staff cache, Reader offline cache, real SQLite outbox,
Admin offline errors, amount controller, Cashier widgets and sign-out alerts.
They do not establish that the bugs above are absent: the shared fake outbox
does not change status in `markSynced`, and the successful Admin-post test only
checks the person's name in the message. Add behavior-focused regressions using
real SQLite/stateful fakes before changing the implementation.

When the Supabase connection exposes read tools, inspect deployed function
definitions, RLS, status aggregates, scheduler health and sanitized errors. Never
select keys, password hashes, full phone numbers or unfiltered logs. Confirm
deployment matches the repository before proposing migrations.

Current Supabase session guidance was consulted:
https://supabase.com/docs/guides/auth/sessions . Sessions and JWT lifetime do not
provide application outbox ownership. The changelog markdown endpoint could not
be fetched by the web tool; recheck applicable release notes before implementation.
