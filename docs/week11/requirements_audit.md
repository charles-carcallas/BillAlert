# Requirements audit — what is built, what is not

**10 September 2026.**

## Read this first

**There is no requirements document in this repository.** This audit is
reconstructed from two sources that are in the repo:

1. The requirement codes annotated throughout `lib/` and `supabase/`.
2. The 56 test cases in `supabase/tests/06_tests.sql`, each of which names the
   requirements it covers.

That means a requirement nobody ever wrote a comment or a test for **will not
appear below at all**. If you have the real FR list from your course
documentation, paste it in and this can be checked against it properly.
Everything below is verified against the code and, where marked, against the
live database.

---

## Working end to end in the app

Driven through the running app or verified against the live database as a
real signed-in user. Not "the code exists" — the flow moves data.

| Code | What it requires | Where it lives |
|---|---|---|
| GEN-01 | Sign in with a username | `login_screen.dart` |
| GEN-04 | A temporary password locks the user to the change screen | router redirect + `change_password_screen.dart` |
| GEN-06 | Signing out destroys the local cache | sign-out flow, with a warning when readings are queued |
| GEN-08 | A role cannot reach another role's section | router `_mayVisit` **and** RLS |
| GEN-11 | Never show a cached figure without its age | "Updated 3 min ago" on the round |
| MTR-02 | A reader sees only their own area | RLS, verified per-role |
| MTR-08 | A meter does not run backwards | use case **and** DB constraint |
| MTR-11 | The reader's round for the cycle | `roster_screen.dart` |
| MTR-12 | Capture time, not sync time; a replay cannot duplicate | outbox `clientUuid`, replay verified live |
| FR-13 | Never announce an amount that does not exist yet | unpriced state on every screen |
| FR-21a | A reading creates an **unpriced** bill | `fn_record_meter_reading` |
| FR-21b | The Area President types the cooperative's amount | `post_bill_amount_screen.dart` |
| FR-23 | One reading per household per cycle | use case **and** unique index |
| FR-30 | Cash payment recorded, receipt issued | `record_payment_screen.dart` |
| CSH-02 | Households with payable bills | cashier consumers list |
| CSH-03 | Every receipt issued in this area | `receipts_screen.dart` |
| CSH-04 | The official receipt as the server issued it | `fn_record_payment` |
| CSH-05 / DOM-06 | Cash is the only method | DB constraint |
| CON-01 | The current bill, which may be unpriced | `current_bill_screen.dart` |
| CON-03 | Payment history, and the receipt behind it | `history_screen.dart` → `receipt_screen.dart` |
| CON-05 | Notifications, with a read state | `inbox_screen.dart` |
| DOM-01/02/04 | Cycle, consumption, overdue | database, single source of truth |
| DOM-05 | Disconnection notice, 48h + Sunday + window | `fn_earliest_lawful_disconnection`, served and displayed |
| ADM-03 | Create a household | `new_consumer_screen.dart` |
| ADM-17 | Record a notice outcome and close it | `notice_document_screen.dart` |
| SYS-05 | Local data unreadable without the key | SQLCipher |
| SYS-07 | The app's "now" is Philippine time | `PhDate` |

**All five original app-callable RPCs are exercised**, the fifth
(`fn_close_disconnection_notice`) as of today.

---

## Built, but never run on a device

| Code | What it requires | State |
|---|---|---|
| **NFR-05** | Work offline, sync on reconnect | **The outbox is fully built and unit-tested. It has never run on a phone.** |

This is the single most important gap in the project. It is the requirement
the whole outbox architecture exists for, and `evidence_log.md` still records
it as *not verified — needs a device*. Section 5 of the walkthrough is what
closes it.

---

## In the database, with no screen — correctly

These do not need a screen. They are reference data, constraints, or rows a
scheduled job would read.

| Code | What it is |
|---|---|
| ADM-09 / ADM-10 / DOM-07 / DOM-08 | Service areas and the fixed barangay |
| ADM-11 / ADM-15 / ADM-16 | The single settings row |
| MTR-05 | The barangay is fixed for the deployment |
| MTR-15 | Active disconnection warnings — surfaced through DOM-05's screens |
| SYS-02 / SYS-03 | Views listing bills due a reminder or an overdue notice today |

---

## Not implemented

| Code | What it requires | Why not |
|---|---|---|
| **FR-31** | Area President creates staff accounts | **SQL written today (`09_staff_accounts.sql`), not yet deployed, no UI.** This is the live one. |
| **SYS-01 / SYS-04** | Notifications are **sent** | Rows are queued in the database and the app reads them in the Inbox. **Nothing sends anything** — there is no worker, no scheduled job, no gateway. |
| **ADM-12 / ADM-13 / ADM-14** | SMS gateway, credentials, message template | No gateway integration and no screen. The schema notes credentials are deliberately not stored. |
| ADM-15 / ADM-16 | Batch sending and the reminder schedule | The settings exist; nothing runs on a schedule to act on them. |
| **MTR-04** | A consumer login is provisioned from the household record | Not automated. **One** consumer login exists in the whole database, created by hand. `AdminNewConsumerScreen` says plainly that it creates no account. |
| GEN-12 | Light/dark theme preference | The column exists; there is no UI and nothing reads it. |
| ADM-04 / ADM-07 / CON-08 | Covered by SQL tests TC-01…TC-07 only | Database behaviour verified; no app screen drives them. |

---

## The honest summary

The **core billing chain is complete and demonstrable**: reading → unpriced
bill → posted amount → cash payment → receipt → the consumer's own copy, plus
the whole disconnection-notice lifecycle.

What is missing clusters into three things, and they are all the same kind of
thing — **something that runs without a person**:

1. **Nothing sends notifications.** They are queued correctly and read
   correctly. The middle is absent.
2. **Nothing runs on a schedule.** Pre-due reminders and overdue notices have
   views ready and no job to read them.
3. **Nothing provisions accounts automatically.** Both MTR-04 and FR-31 need
   an account created, and until today that was blocked on the service-role
   key.

For a Week 11 MVP graded on whether the flows function, none of those three
is in the core chain. But they are the honest answer to "what is left", and
saying "notifications are implemented" would be wrong — **queued** is not
**sent**.
