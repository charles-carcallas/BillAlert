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

**Posted from the running app**, not through PostgREST — the whole Dart
path, screen → controller → PostBillAmount → outbox → SyncService →
`fn_post_bill_amount`:

| Check | Evidence |
|---|---|
| Bill priced | `BA-202608-000004` (Lumayag, 55 kWh) → `total_amount=498.75`, `due_date=2026-09-23`, `priced_at=2026-09-09T12:29:37Z`, `status='unpaid'`, `balance=498.75` |
| Left the queue | `v_readings_awaiting_amount` 3 → **2**; Lumayag absent |
| Alert queued | `bill_ready`, `pending`, for Teresita Lumayag |
| Attributed to the right person | `priced_by` resolves to `mario.ombajin`, role `admin` |

One detail worth keeping: `priced_at` (12:29:37.108) is *later* than the
notification's `created_at` (12:29:36.317). That is not a bug. `priced_at`
is `p_posted_at`, which the gateway sends as the operation's `capturedAt` —
the device's clock at the moment the Admin tapped Post — while `created_at`
is the server's `now()`. The sub-second gap is browser-to-server clock skew,
and it is visible proof that capture time comes from the device rather than
from the server, which is the whole point of MTR-12.

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

Virgilio Busalanan, two unpaid months, settled in one handover.

| Check | Evidence | Date |
|---|---|---|
| Real outstanding bills selected | `BA-202607-000901` (₱566.95, July) and `BA-202608-000001` (₱704.20, August), both read from `v_bill_status` | 9 Sep 2026 |
| Two or more settled in one call | **one** call: `fn_record_payment(p_bill_ids=[july, august], p_amounts=['566.95','704.20'], p_cash_tendered='1500.00')` → transaction `0cad5f7c-d093-46b5-b1c8-a364a9b288b2` | 9 Sep 2026 |
| Exactly one receipt number | `BIEC-2026-09-004471`, verification `BIEC-4471-BU-1271`. `v_payment_history` returns 2 rows and **1** distinct receipt number | 9 Sep 2026 |
| Row in payment_transactions | `payment_transactions` 0 → **1**; `payments` 0 → **2** (one allocation line per bill) | 9 Sep 2026 |
| Money is exact | `total_collected=1271.15`, `cash_tendered=1500.00`, `change_due=228.85` — 566.95 + 704.20 to the centavo | 9 Sep 2026 |
| Both bills settled | each `amount_paid` equals its `total_amount`, `balance=0.00`, `status='paid'` | 9 Sep 2026 |
| Replay creates no second charge | same `clientUuid` replayed → **same** transaction id; counts stayed 1 and 2 | 9 Sep 2026 |
| Daily summary | `v_cashier_daily_summary`: `receipt_count=1`, `total_collected=1271.15` | 9 Sep 2026 |

**Recorded from the running app** — the whole Dart path, screen →
RecordPaymentController → RecordCashPayment → outbox → SyncService →
`fn_record_payment`. Teresita Lumayag, two months, one handover:

| Check | Evidence |
|---|---|
| One transaction | `e2e4174b-b88a-4350-8f54-317b3a290b55`; `payment_transactions` 1 → **2**, `payments` 2 → **4** |
| One receipt | **`BIEC-2026-09-004472`**, verification `BIEC-4472-LU-1005`; `v_payment_history` returns 2 rows and **1** distinct receipt number |
| Money exact | `total_collected=1004.55`, `cash_tendered=1500.00`, `change_due=495.45` — 505.80 + 498.75, and change to the centavo |
| Both months settled | `BA-202607-000904` and `BA-202608-000004` both `balance=0.00`, `status='paid'` |
| Attributed correctly | `cashier_id` resolves to `mercedita.gales`, role `cashier` |
| Idempotency key present | `client_uuid=b7163c69-7765-4609-9538-ff81ffa1ab86`, minted by the app's ClientUuidFactory and carried through the outbox — which is what makes a retried sync safe |
| Daily takings | `v_cashier_daily_summary`: `receipt_count=2`, `total_collected=2275.70` |

Teresita's August bill is the one an Admin priced from the app minutes
earlier, so this single household was carried through pricing and
collection entirely by the real client.

The same OR number against both July and August is the correct behaviour,
not a duplicate: the consumer handed over money once. That is what the
mockup's Consumer History shows and why the receipt number lives on
`payment_transactions` rather than on `payments`.

**How July got its bills.** The July cycle had five meter readings but no
bills, because the readings were seeded directly and bills are only ever
created by `fn_record_meter_reading`. One bill per July reading was inserted
as the meter reader — which `bills_mtr_insert` permits — born unpriced, then
priced through the real RPC like any other. Their due dates are live rather
than historically accurate, because `fn_post_bill_amount` refuses a due date
already in the past.

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
- **The app's Dart client path — verified for posting and for payment.**
  Both were driven from the running app, so screen → controller → use case →
  outbox → SyncService → RPC is exercised end to end for each. **Recording a
  reading has still only been driven through PostgREST**, never from the
  app itself.
- **The app was run on the web target, not Android.** Gradle could not be
  started from the agent's environment (`Unable to establish loopback
  connection`), though `flutter build apk` succeeds when run directly. So the
  screens have been seen running, but not on a phone.
- **The negative half of the meter-reading RLS test** needs a local Postgres,
  or the one-line role change to run against Supabase.

---

## 10 September 2026 — the billing cycle, and a defect it was hiding

### The cycle was defined twice, differently

`settings.cycle_start_day` was **15**, taken from the mockup's
"15 July 2026 – 14 August 2026". The Dart side never agreed with it:

```dart
// lib/domain/usecases/reader/load_area_roster.dart
final cycle = CycleLabel.of(clock.today());
// lib/domain/value_objects/cycle_label.dart
factory CycleLabel.of(PhDate date) => CycleLabel(date.year, date.month);
```

The app has always taken a cycle to be a **calendar month**. The database took
it to be the 15th to the 14th. On any day from the 1st to the 14th the two
disagreed about which cycle it was.

**What that would have done on 10 September**, the day of the demo:

| | |
|---|---|
| Roster header | "September 2026" |
| `fn_ensure_billing_cycle(now)` | day 10 < 15 → period **15 Aug – 14 Sep** = the **August** cycle |
| Every household's August reading | already recorded |
| Result | the reader opens a round for September with five households listed, and **every one is refused** by FR-23 as already read this cycle |

An unreadable round, with an error message about a cycle the screen never
mentioned. Found by asking why nothing was overdue, not by a test.

### Fixed — `08_calendar_cycles.sql`

`cycle_start_day` 1, existing cycles moved onto calendar months, readings on
the 7th of the following month and due dates on the 28th. `cycle_year` and
`cycle_month` untouched, so issued bill numbers and every `cycle_label` are
unchanged.

**Deliberate departure from the design.** The 15th–14th window is what the
Figma shows. It was overridden by the domain owner.

| Cycle | Period | Read | Due | Readings | Overdue |
|---|---|---|---|---|---|
| July 2026 | 1–31 Jul | 7 Aug | 28 Aug | 5 | **3** |
| August 2026 | 1–31 Aug | 7 Sep | 28 Sep | 5 | 0 |
| September 2026 | — | — | — | **0** | — |

The app and the database now name the same cycle on the same day, and the
September round is genuinely empty — so the reading flow and the offline test
have real subjects without a row being deleted.

### Disconnection notice (DOM-05, ADM-17)

Verified as `mario.ombajin` through PostgREST, never the SQL editor.

| Check | Evidence |
|---|---|
| Overdue condition is real | `v_consumer_outstanding` → `overdue_count` 1 for Bongcaras, Amistad, Sarigumba |
| `fn_issue_disconnection_notice` accepted | notice `fe59ec52-60de-4663-b301-01a7861ae213` → **`DN-2026-0910-0033`** |
| Notice document has every field | `notice_no`, `consumer_name`, `consumer_no`, `purok` (Purok 1), `meter_serial_no` (BIEC-08319), `reason`, `issued_by_name` (**Mario Ombajin**), `served_at`, `earliest_lawful_at`, `notice_period_elapsed`, `amount_overdue` (₱541.20) |
| The LEFT JOIN to profiles resolves | `issued_by_name` populated, not null |
| 48h + Sunday + window is server-side | served 10 Sep 04:55 PH → earliest lawful **14 Sep 08:00 PH**. 48h lands Sat 12 Sep, Sunday 13 Sep is skipped, and the time is pushed into the 08:00 disconnection window. The app never computes this. |

**Still not exercised:** `fn_close_disconnection_notice` — the last of the five
app-callable RPCs never called from anywhere. The notice document screen
(`132:2`) is what will call it.
