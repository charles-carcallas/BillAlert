# Household-required account setup

Prepared locally; not applied or deployed to live Supabase.

## Behavior

- Accounts → Create account uses one form for the person, role, household and username. A temporary password is generated automatically.
- Choose a new household or an active existing household without a login. Already-linked households reuse their existing account through staff assignment.
- The backend creates the profile and household link in one transaction after Auth Admin API creation. Definite database rejection compensates by deleting only the new Auth identity. Uncertain responses stop and require account-state review; they never delete an identity or retry automatically.
- The old standalone sign-in route redirects to account creation. Unlinked legacy households retain **Finish account setup**, which opens the unified form with that household selected.
- Staff replacement requires the incoming person’s household. An outgoing staff member without a household must be linked or explicitly disabled first. Disabling and appointing are separate reviewed operations; a failed appointment may leave the position vacant. Refresh and select the intended replacement again.
- Existing staff retain **Set up household**. Names are never automatically matched to households.
- Successor nomination also requires a household. It does not immediately grant work access.
- Reviewed same-household identity replacement requires the previous login to be disabled first. Unrelated occupants get a new household and retain the old household’s separate ledger.
- Only separately recorded eligible Meter Reader coverage waives bills. Creating or linking a household does not grant coverage.

## Deployment order (user-run, after review)

Pause account creation during the coordinated update; existing reading/payment records are preserved.

1. Review and apply `supabase/migrations/20261003122000_household_required_accounts.sql` after the existing staff-assignment migration.
2. Redeploy `manage-accounts` with your established deployment command: `npx supabase functions deploy manage-accounts`.
3. Rebuild/install the updated app. Old staff-only creation clients will be rejected by the new database constraint and should be updated.
4. Run `supabase/checks/account_setup_inventory.sql`. It is read-only and lists missing household links separately from households without logins.
5. Link existing staff to their actual household in-app BEFORE creating any legacy household login. If their household does not exist, create and link it through **Set up household**. Do not guess ownership or create another login for the same person.
6. For the remaining reviewed households, either use **Finish account setup**, or the batch procedure below.

The migration does not backfill, delete, disable or rename existing accounts. Its deferred INSERT constraint requires a household for newly created profiles. Existing unrelated-occupant handover history can remain attached to retired households.

## Optional reviewed batch

`tools/backfill_household_logins.ps1` is preview-only unless `-Apply` is explicitly supplied. It uses the authenticated Area President and the same `manage-accounts` Edge Function, never direct inserts into `auth.users` or a service-role key in the app.

Export the inventory's first result privately, review every row, exclude households belonging to existing logins, and retain these CSV columns:

```text
household_id,username,first_name,last_name
```

The inventory provides a unique suggested `household.<uuid>` username; you may replace it with a reviewed friendly username. Keep both the manifest and credentials outside the repository, for example `$env:USERPROFILE\BillAlertPrivate`.

Preview:

```powershell
./tools/backfill_household_logins.ps1 -Manifest "$env:USERPROFILE\BillAlertPrivate\reviewed-households.csv" -PrivateOutput "$env:USERPROFILE\BillAlertPrivate\created-logins.csv"
```

Only after approving those exact rows, rerun with `-Apply`. Enter the project URL, publishable/anon key and Admin credentials privately at its prompts. Never paste passwords or the output CSV in chat or commit them. The script does not change existing passwords.

The private output is written before each request. If interrupted, an `attempted_unconfirmed` row may already exist in Auth/database: check that username and household before doing anything else. Never rerun the full manifest. Confirmed existing accounts should be reused; if their password was lost, use the app’s reset-password flow. A failed batch is not automatically rolled back. Output files cannot be overwritten by a second run.

## Verification and limitations

- Local SQL tests cover new/existing household creation, duplicate rollback, other-area rejection, active-login replacement rejection, unrelated occupant separation, staff and successor setup, deferred orphan blocking, function permissions and idempotent appointment.
- Edge handler tests exercise missing ownership confirmation, denied access, uncertain outcomes and compensation.
- Flutter tests cover unified creation, required ownership confirmation, corrected retry, existing-household filtering, narrow screens, legacy staff replacement and routing.
- The batch script’s parser and preview were checked without contacting Supabase. Its live Apply path and real Auth/database integration still require a user-run smoke test after deployment.
- Phone installation, live migration, Edge deployment and existing-account backfill remain unperformed.
