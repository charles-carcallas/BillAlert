# BillAlert — Architecture

Five minutes. Read this before you write a screen.

## The four layers

```
presentation/   screens, view models, routing        (Flutter, Riverpod, go_router)
      |  calls
domain/         entities, value objects, use cases,   (pure Dart — no packages)
      |         abstract repositories
      |  implemented by
data/           repository implementations,           (Supabase, Drift, SQLCipher)
                DTOs, sync engine
core/           Result, AppFailure, AppConfig         (pure Dart)
```

## The dependency rule

**Arrows point inward. `domain/` imports nothing.**

Not Flutter, not Supabase, not Drift, not `http`, not even `intl`. `Money.format()`
inserts its own thousands separators by hand for exactly this reason.

`domain/` may import `core/`, because `core/` is pure Dart too. Nothing else.

This is not a style preference and it is not on trust —
`test/architecture/domain_has_no_dependencies_test.dart` fails the build if
anyone breaks it. A comment saying "keep the domain clean" drifts out of date
in a fortnight; a test does not.

What the rule buys you: `RecordMeterReading` is tested against hand-written
fakes in `test/support/fakes.dart` with no network, no database and no Flutter
binding. If a use case ever stops being testable that way, something has been
imported that should not have been.

## Which way a call goes

```
Screen  ->  View model  ->  Use case  ->  Repository (abstract)
                                              ^
                                              |  implements
                                       Repository impl  ->  Supabase / Drift
```

- A **screen** reads a view model and calls its methods. It never calls a use
  case, a repository or Supabase. If your widget file imports
  `supabase_flutter`, the layering is broken.
- A **view model** (`Notifier` / `AsyncNotifier`) calls use cases and turns
  `Result` into `AsyncValue`. It never calls a repository directly.
- A **use case** is one class, one `call` method, named after what a person
  does: `RecordMeterReading`, `PostBillAmount`, `RecordCashPayment`. It takes
  its repositories through the constructor and returns a `Result`.
- A **repository** is abstract in `domain/`, implemented in `data/`. The
  interface speaks in entities; the implementation deals in JSON and SQL.

The wiring is in `lib/presentation/providers.dart`. Look at the type on the
left of each repository provider: it is the abstract class. That single detail
is what makes the arrows point inward.

## Where a new feature goes

Adding "Admin posts a bill amount", start to finish:

1. `domain/usecases/admin/post_bill_amount.dart` — already written. Read it.
2. `domain/repositories/bill_repository.dart` — already written, not yet
   implemented.
3. `data/repositories/bill_repository_impl.dart` — **you write this.** Read
   `v_readings_awaiting_amount`; map errors through `FailureMapper`.
4. `presentation/admin/post_amount_controller.dart` — **you write this.** An
   `AsyncNotifier` calling the use case.
5. `presentation/admin/post_amount_screen.dart` — **you write this.** Widgets
   only.
6. Register the repository in `providers.dart`, as the abstract type.

If a step makes you want to call Supabase from step 5, go back to step 3.

## Why money is not a double

`0.1 + 0.2 != 0.3` in binary floating point. Adding 0.10 ten times gives
0.9999999999999999, not 1.00. Not a rounding curiosity — a wrong number.

BillAlert adds peso amounts: a cashier settles June, July and August on one
receipt, and `v_cashier_daily_summary` totals a day's takings. A `double`
there is a correctness bug even on the days the number happens to look right.

So `Money` holds an **`int` of centavos**. ₱1,975.35 is `197535`. Parsing goes
through the string a `numeric(12,2)` column returned, never through
`double.parse` — PostgREST sends a JSON number, and turning that into a Dart
`double` on the way in would reintroduce the problem the class exists to solve.
`test/domain/money_test.dart` has the failing-double case written out beside
the passing one.

`Kwh` is the same idea in hundredths, matching `numeric(12,2)` on
`meter_readings`.

**And notice what `Money` does not have: multiplication or division.** The app
never derives a bill amount. The cooperative sends a peso figure about seven
days after the reading and the Area President types it in. If you find
yourself multiplying kWh by anything, stop — you have misunderstood the domain.

## Why the bill has nulls, and why no screen may look at them

A bill is created **unpriced**: consumption recorded, `total_amount` null,
`due_date` null. The database enforces that all three pricing columns are null
together or set together (`bills_pricing_consistent`), so there is no
half-priced state.

Screens ask `bill.isUnpriced`, never `bill.totalAmount == null`. The first says
what the null *means* — the cooperative has not sent the figure yet, and this
is the seven-day window the whole application exists to cover. The second is a
null check that anyone can get backwards.

## Why `Result` instead of exceptions

Every layer boundary in this app crosses a network or a database, and both fail
routinely — the meter reader has no signal for hours at a time. An exception
can be forgotten; a `Result<T>` is in the return type, so the compiler makes
every caller say what happens when it fails.

`AppFailure` is sealed, and every failure carries a `message` written for a
meter reader or a consumer. The Postgres code lives in `debugDetail`, which is
logged and never rendered. `PostgrestException(code: 23505)` on screen loses
marks, and deserves to.

**`data/supabase/failure_mapper.dart` is the only file allowed to know what a
`PostgrestException` is.** New error to handle? Handle it there.

## Offline-first

The meter reader works with no signal, and cashiers and admins queue work too.

**Every mutating use case writes to the outbox first, synchronously, and
returns. The screen confirms from that local write, not from the network.**
There is no "if online, upload; else queue" — the offline path is the only
path, so it cannot rot from disuse and break silently in Week 14.

Three things make it correct:

- **`clientUuid`** is minted once when the operation is created and never
  again on retry. Every Postgres function looks it up first, so uploading the
  same reading twice returns the original bill instead of creating a second.
- **`capturedAt`** is the moment of capture, not of sync, and is sent to the
  server. The 48-hour disconnection period is counted from it, so this has
  legal meaning.
- **`outbox_reading_keys`** has `UNIQUE (consumer_id, cycle_label)`, so a
  second queued reading for the same household and month is impossible. The
  reader is told at the meter, not an hour later at sync.

A rejected item is marked `failed` with the server's reason and stays visible.
It is never silently dropped.

## Why `OutboxOperation` is a sealed class

`SyncService._drain()` loops over the queue and calls `operation.submit(gateway)`.
There is **no switch on an operation string** in the sync loop — each subclass
knows which Postgres function it belongs to. Adding a fifth kind of queued
action means writing one new subclass, not editing a switch in three files and
hoping you found them all.

One honest caveat, and it will be asked about: reading a row *back* out of
SQLite needs one `switch`, because all that comes out is a string and some
JSON. That is `data/sync/outbox_codec.dart`, and it is the only one. A sealed
hierarchy removes the dispatch switches; it does not remove the single decode
point, and pretending otherwise would be dishonest.

The same argument applies twice more:

- **`AppUser`** is sealed with four subclasses, each exposing `homeRoute` and
  `permittedTabs`. The router asks the user where it belongs. Written as a
  role-string switch, that decision gets copied into every place that cares
  and they drift apart. `data/dto/profile_dto.dart` is its one decode point.
- **`AppFailure`** and **`Result`** are sealed so a `switch` over them is
  exhaustive and the compiler names every place that must change.

Inheritance is used in those three places and nowhere else. There is no
`BaseScreen`, no `BaseController`, no `BaseModel`. Inheritance that exists only
to share a field cannot be defended in an oral exam, and should not be.

## Never reimplement a Postgres function in Dart

`fn_record_payment` settles several bills in one transaction. A Dart loop doing
three updates is not the same thing and will corrupt data the first time the
network drops mid-loop. `fn_post_bill_amount` posts the amount *and* queues the
consumer's notification together. `fn_record_meter_reading` finds the previous
reading, creates the billing cycle, refuses a duplicate and creates the
unpriced bill.

`data/sync/supabase_outbox_gateway.dart` is four four-line methods. That is
what it should look like.

Row-Level Security is the real access boundary. The client holds an anon key
and talks to PostgREST directly, so anyone with that key and `curl` bypasses
every guard written in Dart. The router's role check is a courtesy that avoids
a confusing empty screen; `04_rls.sql` is the enforcement.

## Two deliberate departures from the written schema

Both need the team's agreement, and both are noted where they occur.

1. **`local_cache_schema.sql` declares money and readings as `real`.** `real`
   is a double. The Drift port in `data/local/tables.dart` uses INTEGER
   centavos and INTEGER hundredths instead, matching `Money` and `Kwh`. The SQL
   file should be updated to match.
2. **`v_local_reading_progress` uses `strftime('%Y-%m','now','localtime')`.**
   That reads the phone's clock and timezone, which can disagree with the
   server's Philippine date and file a reading into the wrong cycle. The app
   computes `CycleLabel` in Dart from `PhDate` (a fixed UTC+8) and passes it in
   as a bound value. The view is not used.

## Encryption

The local cache is SQLCipher, keyed with 32 secure-random bytes held in
`flutter_secure_storage` (Android Keystore) and never in source.

`sqlcipher_flutter_libs` is **deprecated** — version 0.7.0 contains no code at
all. Encryption now comes from selecting the SQLCipher build of
`package:sqlite3` in `pubspec.yaml`:

```yaml
hooks:
  user_defines:
    sqlite3:
      source: sqlcipher
```

Delete that block and the app silently writes plaintext, which is why
`test/data/encryption_test.dart` checks that the file on disk is not readable
as plain SQLite and that a wrong key cannot open it.
