# Week 11 Evidence Log

Everything below was read back from the **live Supabase project** as a real
signed-in user through PostgREST with the anon key — never from the SQL
editor, which connects as the table owner and bypasses every RLS policy.

Verified 9 September 2026. Area 3 — Tubod.

Accounts used: `ledesman.dormal` (meter reader), `mario.ombajin` (Area
President), `virgilio.busalanan` (consumer).

---

### Meter reading (Busalanan)

| Check | Evidence | Date |
|---|---|---|
| Offline save | **not verified** — needs a device; the outbox write is covered by unit tests only | — |
| Survives restart | **not verified** — needs a device | — |
| Syncs | `fn_record_meter_reading` accepted 5 readings as `ledesman.dormal` | 9 Sep 2026 |
| Replayed clientUuid creates no duplicate | replayed the first `clientUuid`: returned the **same** bill `f75463e9-96ab-4d84-b187-ed6a9cc6d841`; counts stayed 10 readings / 5 bills | 9 Sep 2026 |
| Resulting bill is unpriced with null total_amount | all 5 bills born `status='unpriced'`, `total_amount`, `due_date`, `priced_at`, `balance` all null | 9 Sep 2026 |

Bills created: `BA-202608-000001`…`000005` — 62, 59, 67, 55, 58 kWh.

**Blocker found and fixed:** `fn_record_meter_reading` held `select … for
update` on the consumer lookup. Under RLS, `for update` also checks the
UPDATE policy's USING clause, and `consumers_admin_update` is admin-only —
so the function failed for the Meter Reader, the one role allowed to call
it, with "Consumer … not found or not visible to you" for a household the
reader could select a moment earlier.

---

### Post bill amount (Charles)

| Check | Evidence | Date |
|---|---|---|
| Real unpriced bill selected | `117cdc15-a13a-4c25-ba20-f46d89667272` (`BA-202608-000005`, Sarigumba, 58 kWh) | 9 Sep 2026 |
| Typed amount submitted | `fn_post_bill_amount(bill, '658.30', '2026-09-25')` → 200 | 9 Sep 2026 |
| Bill leaves queue | `v_readings_awaiting_amount` went 5 rows → 4; Sarigumba absent | 9 Sep 2026 |
| Bill is priced | `total_amount=658.30`, `due_date=2026-09-25`, `priced_at=2026-09-09T11:44:15Z`, `status` `unpriced`→`unpaid`, `balance=658.30` | 9 Sep 2026 |
| Consumer notification queued | `64c2dd33-d30f-44e7-9c96-9611bf4c3160` — `bill_ready`, channel `push`, status `pending` | 9 Sep 2026 |

Second posting, for the consumer who has a login:
`f75463e9…` → ₱704.20 due 2026-09-30, notification
`ae3557ee-dcd1-4e27-a583-ef87c554a77d`. Queue now 3.

**Blocker found and fixed:** `notifications` had a SELECT policy and two
UPDATE policies but **no INSERT policy at all, for any role**.
`fn_queue_notification` is SECURITY INVOKER, so the alert insert ran as the
Admin and was refused with `42501`. Because the alert is queued in the same
transaction as the amount, the whole posting rolled back — the Admin could
not price a single bill.

---

### Current bill (Basio)

| Check | Evidence | Date |
|---|---|---|
| Unpriced state renders from real data | as `virgilio.busalanan`, `v_consumer_current_bill`: `total_amount=null`, `due_date=null`, `is_unpriced=true`, `status='unpriced'`, consumption 62 kWh, reading 3413→3475 | 9 Sep 2026 |
| Becomes priced after Admin posts | same query, same signed-in consumer, after the posting: `total_amount=704.20`, `due_date=2026-09-30`, `is_unpriced=false`, `status='unpaid'`, `balance=704.20` | 9 Sep 2026 |
| No hard-coded amount | the figure comes from `v_consumer_current_bill`; the screen shows no peso value while `is_unpriced` | 9 Sep 2026 |

**RLS, measured rather than assumed.** As the consumer:

| Query | Rows |
|---|---|
| `consumers` table | 1 (his own, of 6) |
| `meter_readings` table | 1 (his own, of 10) |
| `v_bill_status` | 1 (his own, of 5) |

**Blocker found and fixed:** all twelve `v_` views bypassed RLS. A Postgres
view runs as the role that *owns* it unless `security_invoker` is set, and
these are owned by `postgres`. Before the fix the consumer saw **5** rows
through `v_bill_status`, `v_consumer_current_bill` and
`v_consumer_outstanding` — four other households — while the `bills` table
underneath correctly returned 1. The app reads through the views by design,
so this was the live read path.

---

### Payment (Obiso)

| Check | Evidence | Date |
|---|---|---|
| Real outstanding bills selected | not yet — screen not built | |
| Two or more settled in one call | not yet | |
| Exactly one receipt number | not yet | |
| Row in payment_transactions | not yet | |

Two payable bills now exist to settle: `BA-202608-000001` (₱704.20) and
`BA-202608-000005` (₱658.30).

---

### Area boundary (GEN-08)

Not vacuous: 6 consumers exist, 5 in Area 3 and 1 in Area 4.

| Check | Evidence |
|---|---|
| Staff confined to their area | all three Area 3 staff see exactly the 5 Area 3 consumers; `2022-0001-TUB` (Area 4) excluded |
| Admin is an Area President, not a superuser | same Admin, same insert: into **Area 4** → `403 42501`; into **Area 3** → `201 Created` |
| `app` schema grants applied | every request across four accounts and six views authenticated cleanly; no `permission denied for schema app` |

---

### Not verified

- **On-device offline behaviour.** Everything above went over the network.
  The outbox write, surviving an app kill, and syncing on reconnect are
  covered by unit tests but have not been exercised on a phone.
- **The app's own Dart client path.** These checks used PostgREST directly —
  the same endpoint and the same policies `supabase_flutter` uses, but not
  the Dart code itself.
- **The negative half of the meter-reading RLS test** needs a local Postgres,
  or the one-line role change to run against Supabase.
