# Automatic Pay at BOHECO routing

Apply `20261004071610_automatic_boheco_routing.sql` after the notice and monthly compensation migrations. Existing balances, receipts and handed-over coverage are preserved. The migration routes overdue waiting bills and queues an in-app payment instruction, not a disconnection notice.

## Staff flow

- Cashier: Remit → BOHECO trip → choose eligible bills → Confirm allocation & handover. Selected bills must still have the expected positive balance and must not be overdue on the Philippine calendar date. Rejected stale selections refresh without moving any money.
- Unselected bills move to Consumers → Pay at BOHECO immediately. Overdue uncovered bills move there on the next server tick, without requiring Cashier allocation.
- Reader: record BOHECO receipts for reserve-funded payments, then Remit → BOHECO trip → Complete BOHECO trip. Confirm the displayed uncovered accounts were actually reported. This replaces separate referral buttons.
- Reader: Verify direct payment whenever an actual consumer BOHECO receipt is available, even before trip reporting. That clears local debt without creating a Cashier receipt.
- Admin: serve a notice only for a still-unpaid overdue account after the Reader confirms reporting. Existing notice/SMS rules remain in force.
- Admin: Record returned funds only after the physical cash is returned. This restores the fund once and moves the cancelled coverage to Pay at BOHECO.

Due date remains inclusive through the end of that Philippine date. Already-handed-over coverage never changes just because the date passes. An overdue bill before the configured collection cutoff does not close other household collections; its provisional trip does not count as a collection closure.

## Server automation and checks

The existing pg_cron job `billalert-billing-cutoffs` runs `app.run_boheco_cutoffs()` every minute, including while all apps are closed. The migration updates it when pg_cron is installed. Deployment must verify the job is active; if pg_cron is absent, enable it in Supabase before applying this migration. A snapshot refresh also reconciles waiting records.

Read-only deployment checks:

```sql
select jobname, schedule, active from cron.job
where jobname = 'billalert-billing-cutoffs';
select c.consumer_no, b.due_date, b.balance, s.route, s.state
from bills b join consumers c on c.id=b.consumer_id
left join bill_settlements s on s.bill_id=b.id
where b.balance>0 and b.due_date<fn_ph_today()
order by c.consumer_no;
```

Local rollback tests: `supabase/tests/automatic_boheco_routing_test.sql` covers automatic routing before cutoff, stale/paid allocation, unchanged handed-over money, one-time cash return, role/area boundaries, direct verification before reporting, batch-report retries and notice eligibility. Widget tests cover narrow-phone completion, account confirmation and blocked completion while money remains unrecorded. Tests do not send live SMS or confirm physical cash.
