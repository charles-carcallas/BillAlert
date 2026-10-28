# Current BillAlert SQL kit

Prepared for the schema through `20261007202922_restrict_legacy_settlement_correction.sql`.
These are **operator scripts**, not migrations. Run whole files as the SQL Editor's database owner.
Do not run this reset on member billing history you need to retain.

## What belongs where

| Folder | Purpose |
| --- | --- |
| `migrations/` | Historical schema changes, applied once in dependency order. Keep these files. |
| `operations/` | This current status / beta reset / confirmed roster / sample-data kit. |
| `checks/` | Older investigations and QA fixtures. Not the current reset workflow. |
| `tests/` | Disposable local database tests. Never paste these into the hosted project. |

The SQL Editor's saved tabs are copies, not the database itself. Rename old tabs with
`ARCHIVE - ` or delete their saved text after keeping needed copies. Deleting a saved query
does not undo its database changes. Do not rerun old migration or combined patch tabs.
This kit does not rename or delete your existing saved SQL Editor tabs.

## Confirmed people, provisional household details

| Username (email is username + `@billalert.local`) | Assigned role |
| --- | --- |
| `mario.ombajin` | Admin / Area President |
| `ledesman.dormal` | Meter Reader |
| `mercedita.gales` | Cashier |
| `virgilio.busalanan` | Consumer |

The live inspection on October 8 found only Mario among these four Auth accounts.
Use `00` again for current state. The helper creates missing people using the deployed
`manage-accounts` Auth API and creates each linked household in the same account workflow.
It asks privately for Mario's current password and a temporary password for NEW accounts.
Existing passwords are unchanged. No passwords are stored in these files.

New household numbers `BETA-LEDESMAN`, `BETA-MERCEDITA`, and `BETA-VIRGILIO` are
**placeholders**, not verified BOHECO numbers. Unknown phone, meter and purok stay blank.
Mario's current household and all existing account links are preserved.
Replace provisional household details with verified details before real use.

## Run order for this existing project

Stop testing, sync all devices, and take a restorable database backup first. Keep apps
closed throughout setup. Pausing cron does not prevent a signed-in app from writing data.

1. Run `00_status.sql` (save as **BA 00 - Status**). Inspect missing people and patch checks.
   The rounding, correction-recovery and legacy-permission fixes were already verified live;
   you do not need to rerun those migration files just to use this kit.
2. Run `10_pause_jobs.sql` (**BA 10 - Pause beta jobs**). It pauses SMS and scheduled cutoffs
   while remembering their original states. Wait for any running job to finish.
3. From the project PowerShell terminal, preview then create missing accounts:

   ```powershell
   .\tools\setup_confirmed_beta_accounts.ps1
   .\tools\setup_confirmed_beta_accounts.ps1 -Apply
   ```

   They temporarily have Consumer roles. Continue to `30` for the final roles.
   If a request's outcome is uncertain, STOP and inspect `00` and Supabase Auth before retrying.
   An existing Auth identity without a profile needs repair, not another account.
4. Run `20_reset_beta.sql` (**BA 20 - Reset beta PREVIEW**). Review its archived-row counts.
   It ends in **ROLLBACK**, leaving data unchanged. When correct, change ONLY its final
   `rollback;` to `commit;` and run the whole file again.
5. Run `30_activate_confirmed_people.sql` (**BA 30 - Confirmed people PREVIEW**).
   Review the roster, then change its final `rollback;` to `commit;` and rerun.
   This disables other logins and households **in Mario's area** without deleting them.
   The four confirmed people become active with the roles above.
6. Optional: run `40_seed_beta_scenarios.sql` (**BA 40 - Sample bills PREVIEW**).
   Review the sample results, then change its final `rollback;` to `commit;` and rerun.
   Skip this file if you want an empty, confirmed roster ready for actual data entry.
7. Run `90_verify.sql` (**BA 90 - Verify beta**). Both missing-link counts should be zero.
   If seeded, expect four bills, exactly two overdue direct-pay bills and PHP 2,000 fictional
   reserve money. No initial sample SMS, fabricated receipts, or completed salary payout.
8. Run `99_resume_jobs.sql` (**BA 99 - Resume beta jobs**) to restore the original job states.
   Once every device's pending work is already synced, clear its BillAlert app data and
   sign in again so old cached test bills cannot be uploaded into the reset dataset.

If a script errors, its transaction is rolled back; investigate rather than continuing.
The reset blocks in-flight/uncertain SMS until delivery has been reconciled.
If you abandon setup, use `99` to restore the jobs after checking any pending SMS.
Jobs affect the whole project, although the reset changes only Mario's area.

## What the reset keeps and removes

`20` removes area readings, bills, payments/receipts, notices, remittances, reserve entries,
compensation payouts, BOHECO settlements/evidence, transaction retry records and staff alerts.
It includes the recent money-accounting and correction tables.

It keeps all Auth users, profiles, household links, contact details, area configuration,
billing schedules, calendar cycles and account/assignment/President-transfer audit history.
It does not reset receipt counters or change passwords. A pending President transfer blocks reset.
Other areas are preserved. `30`, separately, disables unverified area accounts/households.

Removed rows and pre-change profile/household snapshots are stored in private
`app.beta_reset_archive`, grouped by `run_id`; previews roll back that archive too.
Only database operators can read it. It is a diagnostic row archive, **not an automatic
restore tool or a substitute for the database backup**. Auth records are never archived there.

## Small sample set for the current flow

| Household | Sample | What to test |
| --- | --- | --- |
| Mario | 100 kWh, amount not posted | Admin posts the bill amount |
| Ledesman | PHP 249.40 cooperative / PHP 250 payable | Normal payment **or**, after closing collection, reserve coverage |
| Mercedita | Previous-month PHP 349.40 / PHP 350 overdue | Pay at BOHECO, report, verify direct payment |
| Virgilio | Previous-month PHP 449.40 / PHP 450 overdue | Report, serve eligible notice, verify payment, close notice |

The two overdue bills route to **Pay at BOHECO** without reserve allocation. Reporting is
still unconfirmed; the Meter Reader must record actually reporting them before the Admin
can serve an eligible notice. Sample data does not pretend these actions already happened.

The current sample uses the upcoming configured due day; after cutoff it uses next month.
The script refuses to overwrite a nonempty dataset. All sample bill numbers start `BETA-`.
Readings are synthetic increments of 100 from the household's stored opening reading.
The PHP 2,000 reserve entry is labeled `[BETA SAMPLE]`; it is not money actually received.
Monthly PHP 500 compensation remains unpaid for you to test normally.

For SMS testing, enter a consenting tester's real number and trigger a NEW bill/notice
action in the app after setup. The seed deliberately sends no initial sample SMS.
Do not disseminate these fictional balances as actual member debts.

For another beta round: pause jobs, preview/apply `20`, skip the account helper and `30`
if the roster is unchanged, preview/apply `40`, verify with `90`, then restore jobs with `99`.

## Verification performed

Tested in a disposable PostgreSQL 17 database with the current schema: preview and
committed reset, confirmed roster activation, sample seeding, regular payment and rounding,
reserve coverage/repayment, monthly compensation, BOHECO reporting and a notice, then
reset and reseed. Assertions verified unchanged Auth identities and household links,
other-area preservation, private archives, original job states and zero seeded SMS.
Cron and Auth tables were local test stand-ins; the helper's PowerShell parsing and
no-network preview passed. Live account creation and the live reset have not been run.
