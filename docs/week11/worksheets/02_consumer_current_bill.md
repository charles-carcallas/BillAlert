# Worksheet 02 — Consumer · Current Bill

**Owner:** Basio
**Files you will edit:**

- `lib/data/repositories/bill_repository_impl.dart` — methods `currentBillFor` and `historyFor` only
- `lib/presentation/consumer/current_bill_controller.dart`
- `lib/presentation/consumer/current_bill_screen.dart`

**Edit only your methods in bill_repository_impl.dart; leave the others exactly as they are.**

---

### Step 1 — Understand the chain

```
reader saves reading → outbox → sync → fn_record_meter_reading
→ unpriced bill (total_amount = null) → admin posts amount
→ [ consumer sees current bill ] → consumer knows what to pay
```

**Q.** Why does the consumer see the bill *before* the cooperative sends the
amount?

<details><summary>Hint</summary>
The reader recorded a reading and a bill was born. The amount arrives days
later. What should the consumer see in between?
</details>
<details><summary>Answer</summary>
The consumer should see their consumption (kWh) immediately, with a clear
"Awaiting amount" status. Hiding the bill until the price arrives would leave
the consumer wondering whether their meter was read at all.
</details>

**Q.** Why is there no hard-coded amount anywhere on this screen?

<details><summary>Hint</summary>
Where does the amount come from?
</details>
<details><summary>Answer</summary>
The amount comes from the cooperative's printout, entered by the Admin via
`fn_post_bill_amount`. This app has no tariff and no rate table — it never
computes a peso figure.
</details>

**Q.** How does the screen know whether the bill is overdue?

<details><summary>Answer</summary>
`bill.isOverdueOn(today)` — the `Bill` entity answers the question.
The screen never compares dates itself.
</details>

**Validate:** Open `lib/domain/usecases/admin/post_bill_amount.dart`, read the
class comment and `call()`. Then open `lib/domain/entities/bill.dart` and read
every getter.

---

### Step 2 — Open the reference

Keep these three files open side-by-side for the rest of the worksheet:

- `lib/presentation/reader/reading_entry_screen.dart` — screen pattern
- `lib/presentation/reader/reading_entry_controller.dart` — controller pattern
- `lib/data/repositories/reading_repository_impl.dart` — repository pattern

---

### Step 3 — Repository: the query

**Q.** Which Supabase view holds the consumer's current bill?
  a) `v_consumer_outstanding`  b) `v_consumer_current_bill`  c) `v_bill_status`  d) `v_payment_history`

<details><summary>Hint 1</summary>
The method is called `currentBillFor`. Which view name matches?
</details>
<details><summary>Answer</summary>
`v_consumer_current_bill`. Search for it in `supabase/migrations/03_views.sql`
to see what columns it returns.
</details>

**Q.** The method returns `Result<Bill?>` — when is it null?

<details><summary>Hint</summary>
What if this is a new consumer with no readings yet?
</details>
<details><summary>Answer</summary>
Null when there is no bill for the current cycle — no reading has been taken
yet. Your screen must handle this case gracefully.
</details>

**Q.** Does `historyFor` need a WHERE clause?

<details><summary>Hint 1</summary>
Same principle as Step 3 in the cashier worksheet — look at how RLS works.
</details>
<details><summary>Hint 2</summary>
RLS scopes to the consumer's own bills automatically.
</details>
<details><summary>Answer</summary>
No explicit WHERE for the consumer. But you do need `.limit(limit)` and an
`.order('cycle', ascending: false)` to get the most recent cycles first.
</details>

**Write it** at `coach:anchor(currentBillFor)` and `coach:anchor(historyFor)`
in `lib/data/repositories/bill_repository_impl.dart`.

**Validate:** `dart analyze lib/data/repositories/bill_repository_impl.dart`

---

### Step 4 — Repository: mapping

**Q.** How does the reference map JSON rows to entities?

<details><summary>Hint</summary>
Find the `.map(...)` call pattern used by other repository implementations.
</details>
<details><summary>Answer</summary>
`rows.map((row) => Bill.fromJson(row)).toList()`. For `currentBillFor`, the
query returns a list — take `.firstOrNull` to get a `Bill?`.
</details>

**Q.** Why is `Money` not a `double`? *(Defence question.)*

<details><summary>Hint</summary>
Try `0.1 + 0.2` in a Dart REPL. You get `0.30000000000000004`.
</details>
<details><summary>Answer</summary>
Doubles cannot represent decimal fractions exactly. Over thousands of bills
the errors accumulate. `Money` stores centavos as an `int`, which is exact.
</details>

**Q.** The bill has `totalAmount` which might be null (unpriced). How does
`Bill.fromJson` handle that?

<details><summary>Answer</summary>
`Bill.fromJson` handles nullable fields internally — when `total_amount` is
null in the JSON, the entity sets `totalAmount` to null. You do NOT check for
null yourself at the mapping layer.
</details>

**Write it** — add the `.map(...)` and `.firstOrNull` calls.

**Validate:** `dart analyze lib/data/repositories/bill_repository_impl.dart`

---

### Step 5 — Repository: failures

**Q.** What is the Result pattern in this codebase?

<details><summary>Hint 1</summary>
Look at any method in `reading_repository_impl.dart` with a try/catch.
</details>
<details><summary>Answer</summary>
`try { return Ok(bill); } catch (e) { return Err(Failure('...')); }`.
Callers use `switch` with `Ok(:final value)` / `Err(:final failure)`.
</details>

**Q.** What plain-English message should the consumer see when loading fails?
*(Rubric grades error messages.)*

<details><summary>Hint</summary>
No stack traces. No class names. What would a consumer checking their bill
understand?
</details>
<details><summary>Answer</summary>
Something like "Could not load your bill. Check your connection and try
again." The wording is yours, but it must be actionable and jargon-free.
</details>

**Write it** — wrap each method in try/catch, return `Ok(...)` or `Err(...)`.

**Validate:** `dart analyze lib/data/repositories/bill_repository_impl.dart`

---

### Step 6 — Verify the provider

The four new providers are already wired in `lib/presentation/providers.dart`.

**Verify:** Open `providers.dart`, find `billRepositoryProvider`. Confirm:
abstract type on the left (`BillRepository`), impl on the right
(`BillRepositoryImpl`), injecting `appDatabaseProvider` and
`supabaseClientProvider`.

---

### Step 7 — Controller: state class

**Q.** What fields does the reference controller's state class hold?

<details><summary>Hint 1</summary>
Open `reading_entry_controller.dart` — find the class near the top.
</details>
<details><summary>Hint 2</summary>
It tracks: the data, whether something is in progress, and an optional failure.
</details>
<details><summary>Answer</summary>
Your `CurrentBillState` needs: a `Bill?` for the current bill, a
`List<Bill>` for history, a `bool isLoading`, and an optional `Failure`.
Unlike the cashier, this is a *read-only* screen — there is no submission
state.
</details>

**Q.** Why is the state class immutable?

<details><summary>Hint</summary>
Riverpod detects changes by comparing old state to new state.
</details>
<details><summary>Answer</summary>
If you mutate a field, old and new are the same object — Riverpod sees no
change and the UI does not rebuild. A `copyWith` returns a new instance.
</details>

**Write it** at `coach:anchor(state-class)` in
`lib/presentation/consumer/current_bill_controller.dart`.

**Validate:** `dart analyze lib/presentation/consumer/current_bill_controller.dart`

---

### Step 8 — Controller: the load action

**Q.** Why does the controller call the repository through the provider
instead of constructing it directly? *(Defence question.)*

<details><summary>Hint</summary>
What if you wanted to run this screen with a fake repository in a test?
</details>
<details><summary>Answer</summary>
The provider is the seam. In production it gives the real `BillRepositoryImpl`;
in a test you override it with a fake. If the controller creates its own, you
cannot substitute it.
</details>

**Q.** How do you handle the `Result` that comes back?

<details><summary>Hint 1</summary>
Find the `switch` on the Result in the reference controller's save action.
</details>
<details><summary>Answer</summary>
`switch (result) { Ok(:final value) => /* set bill, clear loading */,
Err(:final failure) => /* set failure, clear loading */ }`.
</details>

**Q.** This screen is read-only. What is the controller's `build()` method
for?

<details><summary>Answer</summary>
`build()` returns the initial state — `const CurrentBillState()` — and is
also where you kick off the initial load. The reference calls a fetch method
from `build()` so data loads as soon as the screen appears.
</details>

**Write it** at `coach:anchor(controller-class)`.

**Validate:** `dart analyze lib/presentation/consumer/current_bill_controller.dart`

---

### Step 9 — Screen: imports + declaration

**Q.** What base class does a Riverpod-aware screen use?
<details><summary>Answer</summary>
`ConsumerWidget` (if no local mutable state) or `ConsumerStatefulWidget`
(if you need `TextEditingController` or similar). This screen is read-only,
so `ConsumerWidget` is the simpler choice.
</details>

**Write it** in `current_bill_screen.dart` — replace `StatelessWidget`.

**Validate:** `dart analyze lib/presentation/consumer/current_bill_screen.dart`

---

### Steps 10–12 — Scaffold, layout, display

These are low-stakes layout steps. Reference the `_Form` widget in
`reading_entry_screen.dart` for the pattern.

**Step 10.** Keep the `Scaffold` and `AppBar` from the stub.

**Step 11.** In the body, display the current bill. Show:
- `bill.cycle.displayName` (which billing period)
- `bill.consumption.format()` (how much energy)
- `bill.statusLabelOn(today)` (status chip — "Awaiting amount" or "Unpaid" etc.)
- If priced: `bill.totalAmount!.format()`, `bill.balance.format()`,
  `bill.dueDate!.toIso()`
- If unpriced: a message like "Amount pending — the cooperative will send it soon."

**Step 12.** Below the current bill, add a simple history list showing past
cycles. Each item: `bill.cycle.displayName`, `bill.statusLabelOn(today)`,
`bill.balance.format()`.

**Validate after each:** `dart analyze lib/presentation/consumer/current_bill_screen.dart`

---

### Step 13 — Loading state

**Q.** Where does a loading spinner go when the screen first opens?

<details><summary>Hint</summary>
Find `CircularProgressIndicator` in the `loading:` callback in the reference.
</details>
<details><summary>Answer</summary>
`Center(child: CircularProgressIndicator())` — shown while the bill data is
being fetched. This is the only loading state; there is no submission since
the screen is read-only.
</details>

**Q.** What if the consumer has no bill at all?

<details><summary>Hint</summary>
`currentBillFor` returns `Bill?` — the null case.
</details>
<details><summary>Answer</summary>
Show an empty state message: "No bill for the current cycle. Your meter may
not have been read yet." Do NOT show an error — a missing bill is normal.
</details>

**Write it** — add loading and empty states.

**Validate:** `dart analyze lib/presentation/consumer/current_bill_screen.dart`

---

### Step 14 — Error state

**Q.** What component does the reference use for errors?

<details><summary>Answer</summary>
`FailureBanner` — find it in `_Form` of `reading_entry_screen.dart`. It
takes a `Failure` and renders its plain-English message.
</details>

**Q.** How does the error path differ from the cashier screen?
*(Defence question.)*

<details><summary>Hint</summary>
The cashier has two error paths (load vs. submit). How many does this
screen have?
</details>
<details><summary>Answer</summary>
Only one: the data failed to load. There is no submission, so no submission
error. Show `FailureBanner` with a retry button.
</details>

**Write it** — add `FailureBanner` for the load failure.

**Validate:** `dart analyze lib/presentation/consumer/current_bill_screen.dart`

---

### Step 15 — Status transitions

This screen does not navigate away — it *stays* and reflects changes.

**Q.** What happens when the Admin posts the bill amount while the consumer
is looking at the unpriced bill?

<details><summary>Hint</summary>
How does the data get refreshed?
</details>
<details><summary>Answer</summary>
The consumer pulls to refresh (or the controller re-fetches). The bill's
`isUnpriced` flips to false, `totalAmount` appears, and
`statusLabelOn(today)` changes from "Awaiting amount" to "Unpaid". No code
change is needed — the entity handles it.
</details>

**Write it** — add pull-to-refresh with `RefreshIndicator`.

**Validate:** `dart analyze`

---

### Step 16 — Cleanup / dispose

If you used `ConsumerWidget`, Riverpod manages the lifecycle — nothing to
dispose. If you used `ConsumerStatefulWidget`, dispose any controllers.

**Validate:** `dart analyze`

---

### Step 17 — Prove it

Open `docs/week11/evidence_log.md` and fill in the **Current bill (Basio)**
table:

| Check | How to get evidence |
|---|---|
| Unpriced state renders from real data | Screenshot showing "Awaiting amount" and kWh |
| Bill becomes priced after Admin posts | Screenshot showing amount and due date |
| No hard-coded amount anywhere | `grep -rn "1250\|₱" lib/presentation/consumer/` returns empty |
| History shows past cycles | Screenshot with ≥2 history items |

Run `tools/verify_week11.ps1` (Windows) or `tools/verify_week11.sh` (Git
Bash) to confirm automated checks pass, then collect the manual evidence.
