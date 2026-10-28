# Account management

## Guided household setup

My household shows a neutral “No household linked yet” card. An active Area
President can choose “Set up my household” there or at the top of Manage accounts.
Unlinked staff also have a setup button on their account card and after account
creation. The owner is already selected; names are prefilled for a new household.

Choose existing searches unlinked active households by name, consumer number or
meter. The President confirms ownership before linking. Occupied households
remain in the separate reviewed handover workflow. New households use existing
registration rules and a zero reading baseline; existing services with earlier
readings should use their existing record.

Creation and linking use two existing server operations. If linking cannot be
confirmed after creation, the record is preserved and the screen directs the
President to refresh and select it without repeating creation. This UI update
needs no SQL or Edge deployment. BOHECO approval remains separate.

Verification: three guided setup widget tests and eleven existing staff,
Accounts and current-bill tests passed. Analysis reports only the seven existing
scratch issues. Phone operation remains to be checked after rebuilding.

## Screens

- `AccountManagementScreen`: `lib/presentation/admin/account_management_screen.dart`, route `/admin/accounts/manage`, active Area President only.
- `AccountTransferScreen`: `lib/presentation/common/account_transfer_screen.dart`, route `/account/transfer`, **all signed-in identities**, including work-disabled president candidates in household mode. Existing mandatory password-change gate still applies. Shows `area_name`, `outgoing_name` and `successor_name`, with friendly fallback labels; never displays their UUIDs.
- `AdminAccountsScreen` has a Manage existing accounts button. My president transfers is also accessible from Profile.
- Providers are in `account_management_providers.dart`, repository in `lib/data/repositories/account_management_repository.dart`.

All changes require connectivity, are never queued, and are never retried automatically. Refresh after any uncertain result before considering another operation. Work restoration can conflict with a now-occupied position; the server decides.

## Flows

People: end/restore work separately from disable/enable login. Admin accounts have no generic action menu: use president transfer. End work requires a reason and explicit reconciliation. Emergency login suspension requires a reason but no assertion that reconciliation has finished. The queue warning counts this session's unsynced/rejected work on this phone only; zero does not verify other phones, quarantined entries, cash or handover.

Households: own staff links and reviewed same-household changes are separate from unrelated occupant handovers. The latter creates a fresh household, preserves the old household/history and old login link, and transfers its meter. Post every unpriced old bill first. Opening reading must equal the last recorded reading or initial baseline. Replacement login must be active, registered in the area and unlinked. Replacement login creation appears only inside a reviewed same-household change or unrelated occupant handover. The President can use an existing login or create a replacement; a newly created login is selected automatically in the next form. Cancelling afterward preserves that login for later use. Uncertain creation stops the flow without automatic retries.

President: outgoing president prepares a separate successor identity with a temporary password and reconciliation assertion. Candidate signs in, changes password, uses household mode and accepts on My president transfers. Outgoing president explicitly reconciles and completes. Completion activates successor work and ends outgoing work, retaining household history. Cancel is available to the outgoing identity on pending/accepted rows. SQL authorizes all transitions.

The completion dialog is the initial confirmation. After the RPC the screen calls `AuthController.confirmSession()` to refresh profile capabilities and stop old work scope. It also refreshes after an uncertain response, reloads transfer status and never automatically repeats completion.

BOHECO coverage: meter-reader menu opens assignment history. An active reader can receive coverage for their own linked active household, starting the first of the current/future month. End existing coverage before replacement. Applies only to newly priced eligible bills, no backfill. Covered by BOHECO is never a payment/receipt. Calls the three RPCs documented in `reader_waiver_contract.md`.

## Edge Function and failure handling

New `manage-accounts/index.ts` is the runtime adapter; `handler.ts` accepts injectable dependencies for isolated tests. It verifies `getUser(token)`, then checks the stored active/admin/staff-enabled/area profile. Privileged prepare RPCs independently recheck the actor and area. Never authorize from user metadata.

- `create_successor`: username, first_name, last_name, temporary_password, reason, reconciled=true. Calls `fn_prepare_president_transfer(p_actor,p_successor,p_username,p_first_name,p_last_name,p_reason)`.
- `create_consumer_login`: same identity fields and reason; reconciliation not required. Calls `fn_prepare_consumer_identity(p_actor,p_user,p_username,p_first_name,p_last_name,p_reason)`.
- `disable_login` / `enable_login`: target UUID and reason. Calls `fn_manage_account` **with the caller JWT**, then sets/removes the Auth ban using the service client. A partial failure reports uncertainty. Repeating after state review is safe with SQL's idempotent login change. Enable does not restore ended work.

Auth banning prevents new logins/refresh. It does not claim cryptographic revocation of an already issued access token: current database RLS/status guards must block that token's data access. This function does not promise remote cache deletion or access to an already unlocked offline phone. No sessions-revoked claim is displayed.

Supabase JS is pinned to 2.57.4, whose auth-js 2.71.1 `AdminUserAttributes` supports optional `id`: [versioned type source](https://github.com/supabase/auth-js/blob/v2.71.1/src/lib/types.ts). Preallocate an Auth UUID and return that reference on uncertainty. The UUID is a recovery reference, **not an idempotency token**. Do not repeat account creation blindly. The service must inspect Auth by username/reference and the corresponding profile/transfer before resolving.

Compensating Auth deletion happens only after a known PostgreSQL rejection (explicit validation/permission/constraint SQLSTATE). Lost responses, timeouts, network/gateway errors and ambiguous create results never trigger deletion. A failed/uncertain deletion says an authentication account may remain; it never says no account was kept. Passwords and service keys are not logged.

Required runtime environment: SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY. Keep service credentials server-only. Deploy only after the lifecycle and waiver migrations are applied and verified. No deployment, SQL execution or commit is part of this implementation.

## Maintainer-only president recovery

No recovery role or app UI is added. An authorized maintainer creates a separate Auth identity through the Auth dashboard, then uses the reviewed maintenance procedure for `fn_prepare_president_recovery(p_area,p_successor,p_username,p_first_name,p_last_name,p_reference)`. Preparation creates a work-disabled identity without falsely attributing the action to the outgoing president. The candidate changes their temporary password. After verifying identity and the handover, the maintainer uses `fn_recover_president(p_area,p_successor,p_reference)`. An audit event with null actor denotes maintainer action. These are manual instructions only; no SQL is executed by this task.

## Verification

`supabase/functions/tests/manage_accounts.test.ts` covers verified identity/admin gating, successor and consumer creation, strict reconciliation, definite rejection cleanup, ambiguous outcomes without deletion, cleanup failures and preallocated recovery references. Run with `deno test supabase/functions/tests/manage_accounts.test.ts` (pure injected dependencies, no network/database permissions).

Repository request tests: `flutter test test/data/account_management_repository_test.dart`. Existing Accounts widget regression: `flutter test test/presentation/admin/accounts_screen_test.dart`.

Local verification: four repository tests plus the existing Accounts widget regression passed (5/5). A subsequent rerun after final UI guards was blocked by a locked `build/native_assets/windows/sqlcipher.dll`. Dart analyzer encountered an environmental Dart perf-file shutdown error; analysis remains unverified. No SQL, live deployment or commit was performed.

The 12 isolated Edge handler tests and `deno check supabase/functions/manage-accounts/index.ts` passed. Canonical routes are `/admin/accounts/manage` and `/account/transfer`; legacy aliases remain available.
