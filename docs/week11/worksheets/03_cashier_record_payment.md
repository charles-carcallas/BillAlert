# Worksheet 03 — Cashier · Record Payment

**Owner:** Obiso
**Files you will edit:**

- `lib/data/repositories/bill_repository_impl.dart` — method `payableFor` only
- `lib/data/repositories/payment_repository_impl.dart` — both methods
- `lib/presentation/cashier/record_payment_controller.dart`
- `lib/presentation/cashier/record_payment_screen.dart`

**Edit only your methods in bill_repository_impl.dart; leave the others exactly as they are.**

---

### Step 1 — Understand the chain

```
reader saves reading → outbox → sync → fn_record_meter_reading
→ unpriced bill → admin posts amount → consumer sees amount
→ [ cashier collects payment ] → receipt
```

**Q.** Why is one handover one receipt, rather than one receipt per bill?

<details><summary>Hint</summary>
`fn_record_payment` takes a *list* of bill IDs and settles them in one
database transaction. Splitting them risks orphaned partial payments.
</details>

**Q.** Why can an unpriced bill never appear in this list?

<details><summary>Hint</summary>
`bill.isPayable` is false when `total_amount` is null. The view
`v_consumer_outstanding` filters these out at the DB level.
</details>

**Q.** What stops a double-tap on Confirm from recording two payments?

<details><summary>Hint</summary>
Each call mints a `clientUuid`. The server function is idempotent on that
key — a replayed call returns the same receipt.
</details>

**Validate:** Open `lib/domain/usecases/cashier/record_cash_payment.dart`,
read the constructor and `call()` method.

---

### Step 2 — Open the reference

Keep these three files open side-by-side for the rest of the worksheet:

- `lib/presentation/reader/reading_entry_screen.dart` — screen pattern
- `lib/presentation/reader/reading_entry_controller.dart` — controller pattern
- `lib/data/repositories/reading_repository_impl.dart` — repository pattern

---

### Step 3 — Repository: the query

**Q.** Which Supabase view holds outstanding payable bills?
  a) `v_bill_status`  b) `v_consumer_current_bill`  c) `v_consumer_outstanding`  d) `v_payment_history`

<details><summary>Hint 1</summary>
"Outstanding" = unpaid or partially paid. Which view name says that?
</details>
<details><summary>Answer</summary>
`v_consumer_outstanding`. Search for it in `supabase/migrations/03_views.sql`
to see the WHERE clause.
</details>

**Q.** Do you write a WHERE clause to scope to this consumer?

<details><summary>Hint 1</summary>
Look at how `reading_repository_impl.dart` queries — does it pass a user ID?
</details>
<details><summary>Hint 2</summary>
Row Level Security (RLS) filters rows automatically based on the JWT.
</details>
<details><summary>Answer</summary>
No. Call `_client.from('v_consumer_outstanding').select()` and RLS returns
only rows this consumer can see.
</details>

**Q.** Why can an unpriced bill never appear in this list? *(Defence question.)*

<details><summary>Answer</summary>
The view's WHERE clause excludes rows where `total_amount IS NULL`. Your
Dart code never checks for this — the database guarantees it.
</details>

**Write it** at `coach:anchor(payableFor)` in `lib/data/repositories/bill_repository_impl.dart`.

**Validate:** `dart analyze lib/data/repositories/bill_repository_impl.dart`

---

### Step 4 — Repository: mapping

**Q.** How does the reference map JSON rows to entities?

<details><summary>Hint 1</summary>
Find the `.map(...)` call in `reading_repository_impl.dart`.
</details>
<details><summary>Answer</summary>
`rows.map((row) => Bill.fromJson(row)).toList()`. The entity's `fromJson`
handles all parsing internally.
</details>

**Q.** Why is `Money` not a `double`? *(Defence question.)*

<details><summary>Hint</summary>
Try `0.1 + 0.2` in a Dart REPL. You get `0.30000000000000004`.
</details>
<details><summary>Answer</summary>
Doubles cannot represent decimal fractions exactly. Over thousands of bills
the errors accumulate. `Money` stores centavos as an `int`, which is exact.
</details>

**Q.** How do you parse money from the JSON the server sends?

<details><summary>Answer</summary>
The server sends strings like `"1250.00"`. `Bill.fromJson` calls
`Money.tryParse` internally — never route through `double`.
</details>

**Write it** at `coach:anchor(payableFor)` — add the `.map(...)` call.

**Validate:** `dart analyze lib/data/repositories/bill_repository_impl.dart`

---

### Step 5 — Repository: failures

**Q.** What is the Result pattern in this codebase?

<details><summary>Hint 1</summary>
Look at any method in `reading_repository_impl.dart` with a try/catch.
</details>
<details><summary>Answer</summary>
`try { return Ok(bills); } catch (e) { return Err(Failure('...')); }`.
Callers use `switch` with `Ok(:final value)` / `Err(:final failure)`.
</details>

**Q.** What plain-English message should the cashier see when the network
fails? *(Rubric grades error messages.)*

<details><summary>Hint</summary>
No stack traces. No class names. What would a cashier at a counter
understand?
</details>
<details><summary>Answer</summary>
Something like "Could not load outstanding bills. Check your connection and
try again." The wording is yours, but it must be actionable and jargon-free.
</details>

**Q.** Why does the controller use `switch` on the Result instead of
try/catch?

<details><summary>Answer</summary>
The repository already caught the exception. The Result is a sealed value —
pattern matching forces you to handle both `Ok` and `Err` at compile time.
</details>

**Write it** at `coach:anchor(payableFor)` — wrap in try/catch, return
`Ok(...)` or `Err(...)`.

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
It tracks: data being submitted, whether a save is in progress, an optional
failure, and the result after success.
</details>
<details><summary>Answer</summary>
Your `RecordPaymentState` needs: selected `Bill` objects, an `isSubmitting`
flag, an optional `Failure`, and an optional receipt number.
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
`lib/presentation/cashier/record_payment_controller.dart`.

**Validate:** `dart analyze lib/presentation/cashier/record_payment_controller.dart`

---

### Step 8 — Controller: the action

**Q.** Why does the controller call the use case instead of Supabase
directly? *(Defence question.)*

<details><summary>Hint</summary>
What happens if two screens both need to record payments?
</details>
<details><summary>Answer</summary>
The use case centralises business logic (minting `clientUuid`, writing to
the outbox). Without it, every caller duplicates that logic and any bug fix
must be applied in every copy.
</details>

**Q.** What parameters does `RecordCashPayment.call()` expect?

<details><summary>Hint</summary>
Open `lib/domain/usecases/cashier/record_cash_payment.dart` and read the
`call()` signature. Do not guess — read it.
</details>

**Q.** How do you handle the `Result` that comes back?

<details><summary>Hint 1</summary>
Find the `switch` on the Result in the reference controller's save action.
</details>
<details><summary>Answer</summary>
`switch (result) { Ok(:final value) => /* set receipt, clear submitting */,
Err(:final failure) => /* set failure, clear submitting */ }`.
</details>

**Q.** What stops a double-tap from recording two payments?

<details><summary>Answer</summary>
Guard: `if (state.isSubmitting) return;`. Set `isSubmitting = true`
immediately. The `clientUuid` is a second line of defence server-side.
</details>

**Write it** at `coach:anchor(controller-class)`.

**Validate:** `dart analyze lib/presentation/cashier/record_payment_controller.dart`

---

### Step 9 — Screen: imports + declaration

**Q.** What base class does a Riverpod-aware screen use?
<details><summary>Answer</summary>
`ConsumerStatefulWidget` (if you need local mutable state) or
`ConsumerWidget` (if you don't). Check the reference.
</details>

**Write it** in `record_payment_screen.dart` — replace `StatelessWidget`.

**Validate:** `dart analyze lib/presentation/cashier/record_payment_screen.dart`

---

### Steps 10–12 — Scaffold, layout, selection

These are low-stakes layout steps. Reference the `_Form` widget in
`reading_entry_screen.dart` for the pattern.

**Step 10.** Add a `Scaffold` with `AppBar` and `body` at `coach:anchor(scaffold)`.

**Step 11.** In the body, display each payable bill showing `bill.balance.format()`.

**Step 12.** Add a selection mechanism (checkboxes or selectable tiles) and a
Confirm `ElevatedButton`. The cashier does NOT type an amount — the total
comes from the selected bills' balances.

**Validate after each:** `dart analyze lib/presentation/cashier/record_payment_screen.dart`

---

### Step 13 — Loading state

**Q.** Where does a loading spinner go when the cashier taps Confirm?

<details><summary>Hint</summary>
Find `CircularProgressIndicator` with `strokeWidth: 2` inside the
`ElevatedButton` of `_Form` in the reference.
</details>
<details><summary>Answer</summary>
Inside the button, replacing its text. Also disable the button and the bill
list — if the cashier deselects mid-submission, the UI and server disagree.
</details>

**Q.** How does `AsyncValue.when` handle the *initial* data load?

<details><summary>Answer</summary>
`loading: () => Center(child: CircularProgressIndicator())` — this is for
fetching the bill list, separate from the submit spinner.
</details>

**Write it** — add spinners for both initial load and submission.

**Validate:** `dart analyze lib/presentation/cashier/record_payment_screen.dart`

---

### Step 14 — Error state

**Q.** What component does the reference use for errors?

<details><summary>Answer</summary>
`FailureBanner` — find it in `_Form` of `reading_entry_screen.dart`. It
takes a `Failure` and renders its plain-English message.
</details>

**Q.** What are the two different error paths? *(Defence question.)*

<details><summary>Hint</summary>
Initial load failure vs. submission failure.
</details>
<details><summary>Answer</summary>
1. `AsyncValue.when(error: ...)` — the bill list failed to load. Show
   `FailureBanner` with a retry.
2. `state.failure != null` — the payment submission failed. Show
   `FailureBanner` in the form area.
</details>

**Write it** — add `FailureBanner` for both paths.

**Validate:** `dart analyze lib/presentation/cashier/record_payment_screen.dart`

---

### Step 15 — Success state + navigation

When `state.receiptNumber` is not null, navigate to a confirmation showing
the receipt number. Reference: `_SavedConfirmation` in
`reading_entry_screen.dart`.

**Write it.** **Validate:** `dart analyze`

---

### Step 16 — Cleanup / dispose

If you used `ConsumerStatefulWidget`, dispose any controllers in `dispose()`.
If `ConsumerWidget`, Riverpod manages the lifecycle — nothing to dispose.

**Validate:** `dart analyze`

---

### Step 17 — Prove it

Open `docs/week11/evidence_log.md` and fill in the **Payment (Obiso)** table:

| Check | How to get evidence |
|---|---|
| Real outstanding bills selected | Screenshot of bill list before Confirm |
| Two or more settled in one call | Screenshot showing ≥2 bills selected |
| Exactly one receipt number | Screenshot of confirmation screen |
| Row in `payment_transactions` | Supabase dashboard → `payment_transactions` table |

Run `tools/verify_week11.ps1` (Windows) or `tools/verify_week11.sh` (Git
Bash) to confirm automated checks pass, then collect the manual evidence.
