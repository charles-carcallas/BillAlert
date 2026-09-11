# Week 11 demo walkthrough — controlled demo data

Use this walkthrough for the Week 11 MVP presentation. It runs BillAlert with
deterministic data held in memory and never connects to Supabase. You can repeat
the walkthrough without changing the live database.

Week 11 demonstrates the primary screens, navigation, validation, and core user
journeys. Live API/database integration belongs to Week 12. The production
SQLite force-stop and reconnect test remains a separate integration check; demo
mode cannot provide evidence for persistence across an app restart.

---

## 0. Start the correct build

### From VS Code

1. Open **Run and Debug**.
2. Select **BillAlert (demo data)**.
3. Press **Start Debugging**.

Do not select **BillAlert (dev)** for this walkthrough. The dev configuration
uses Supabase; the demo-data configuration supplies `DEMO_MODE=true`.

### From a terminal

```bash
flutter run --dart-define=DEMO_MODE=true
```

### Build a dedicated demo APK

```bash
flutter build apk --release --dart-define=DEMO_MODE=true
```

No Supabase URL or key is needed for a demo build. `DEMO_MODE` is a compile-time
setting, so a running demo APK cannot accidentally be switched to the live
database.

- [ ] Start the app with one of the demo commands above.
- [ ] Confirm that the diagonal **DEMO DATA** banner is visible and the login
      screen lists the controlled demo accounts.

---

## Demo accounts

Every account uses the password **`demo`**.

| Role | Username | Full-name alias also accepted |
|---|---|---|
| Meter Reader | `reader` | `ledesman.dormal` |
| Admin | `admin` | `mario.ombajin` |
| Cashier | `cashier` | `maria.canete` |
| Consumer | `consumer` | `elena.bongcaras` |

The short usernames are easier to type during the presentation.

---

## Controlled starting data

The demo clock is fixed at **10 September 2026**, so the reading round is always
**September 2026**. The seeded households are Elena Bongcaras, Bienvenido
Sarigumba, Virgilio Bacus, Teresita Daguplo, and Odelon Paredes.

The main records used in the walkthrough are:

| Record | Demo state | Used to show |
|---|---|---|
| Elena Bongcaras | July bill overdue by **₱541.20** | Consumer bill, overdue history, inbox, and notice |
| Elena's June and May bills | Paid under receipt **OR-2026-0802-0018** | Payment history and receipt document |
| Notice **DN-2026-0910-0033** | Active; earliest lawful moment is 14 Sep 2026, 08:00 PH | Notice list and document |
| Teresita Daguplo | One bill awaiting an amount | Admin Amounts queue |
| Virgilio Bacus | Existing recent receipt **OR-2026-0909-0041** | Cashier Receipts list |

All changes stay inside the running app. Closing Elena's notice, adding a
consumer, or recording a reading does not touch Supabase.

---

## 1. Meter Reader

Sign in with **`reader` / `demo`**.

- [ ] The app lands on **Readings**.
- [ ] The round says **September 2026** and shows five households.
- [ ] Open a household and confirm that the previous reading and last-reading
      date are visible.
- [ ] Enter a value below the previous reading and confirm that the app rejects
      it because a meter cannot run backwards.
- [ ] Enter a valid value above the previous reading and save it.
- [ ] Confirm that the reading is shown as queued and that the roster updates.
- [ ] Try the same household again and confirm that a second reading for the
      same cycle is refused.
- [ ] Open **Consumers** and review the household list, last-reading dates, and
      search/filter controls.
- [ ] Open **Profile** and confirm the Meter Reader identity and sign-out action.

This demonstrates the offline-first interaction at the UI/domain level. In demo
mode, the queued reading exists only in memory.

---

## 2. Admin (Area President)

Sign out, then sign in with **`admin` / `demo`**.

### Amounts

- [ ] Open **Amounts** and find Teresita Daguplo's bill waiting for an amount.
- [ ] Submit with no amount and confirm that validation explains what is needed.
- [ ] Enter an amount and due date, then post it.
- [ ] Confirm the success message.

The demo repository keeps the seeded queue visible so this screen can be
rehearsed repeatedly. The app still exercises the form, use case, validation,
outbox handoff, and success state.

### Notices

- [ ] Open **Notices** and select **DN-2026-0910-0033**.
- [ ] Confirm the document shows Elena Bongcaras, consumer number
      `2018-0442-TUB`, Purok 1, meter `BIEC-08319`, the reason, service time,
      earliest lawful moment, and **₱541.20** overdue.
- [ ] Confirm the earliest lawful moment is **14 September 2026 at 08:00 PH**.
- [ ] Read the statement that BillAlert never authorises, schedules, or executes
      a disconnection. **Referred** records a handover to cooperative personnel.
- [ ] Choose one outcome, add optional notes, review the confirmation dialog,
      and close the notice.
- [ ] Confirm the success state and the honest empty state when the closed notice
      can no longer be found.

It is safe to close this demo notice. Relaunching the demo restores it.

### Serve a notice

- [ ] Open **Serve a notice**.
- [ ] Search or select a household with an outstanding bill.
- [ ] Enter a reason, review the confirmation, and submit.
- [ ] Confirm the served-success state.

The demo confirms the presentation and handoff flow. It does not start a legal
clock or create a live notice because those results are assigned by the server.

### Accounts

- [ ] Open **Accounts** and search the five seeded households.
- [ ] Open **New consumer**, enter a unique consumer number and name, and create
      the household.
- [ ] Confirm the created-consumer result, then return to the list.
- [ ] Review the explanation that staff accounts require a trusted server and
      cannot be created from the mobile client.

---

## 3. Cashier

Sign out, then sign in with **`cashier` / `demo`**.

- [ ] The payment screen opens with searchable households and outstanding bills.
- [ ] Search for **Bienvenido Sarigumba** and review his unpaid August bill.
- [ ] Try to submit without selecting a bill and confirm the validation message.
- [ ] Select the bill and enter cash tendered below the amount due; confirm that
      the app refuses insufficient cash.
- [ ] Enter enough cash and record the payment.
- [ ] Confirm the honest queued message explaining that the official receipt
      number is issued after server synchronization.
- [ ] Open **Receipts** and inspect the seeded collection history, including
      receipt **OR-2026-0909-0041**.
- [ ] Open **Profile** and confirm the Cashier identity and sign-out action.

The seeded bills and receipts return after a relaunch. No official receipt is
minted for this action because demo mode does not call the server RPC. The
Consumer section below uses a separate seeded receipt to demonstrate the full
receipt document.

---

## 4. Consumer

Sign out, then sign in with **`consumer` / `demo`**. This account represents
**Elena Bongcaras**.

### Bill

- [ ] **Bill** shows the July 2026 balance of **₱541.20**, its due date, and its
      overdue state.
- [ ] Review the amount, consumption, and bill details.

### History

- [ ] Open **History** and switch between the **Bills** and **Payments** tabs.
- [ ] Search by month or OR number.
- [ ] Change the date sort and confirm the order changes.
- [ ] Confirm that July is presented as overdue without covering the main bill
      information.
- [ ] In Payments, open **OR-2026-0802-0018**.
- [ ] Confirm that the receipt covers the paid May and June bills, shows the
      cash/change breakdown, and includes its verification code.

### Inbox and profile

- [ ] Open **Inbox** and review the overdue and bill-ready notifications.
- [ ] Use the notification filters and mark an unread item as read.
- [ ] Open **Profile** and review the household, account, meter, and address
      sections.
- [ ] Open Change password and verify the form validation.
- [ ] Sign out.

---

## Repeat or reset the walkthrough

Demo data is recreated each time `main()` starts.

1. Stop the running app completely.
2. Start **BillAlert (demo data)** again.
3. Sign in with any demo account and repeat the walkthrough.

A VS Code **Hot Restart** also recreates the provider scope in normal debugging,
but stopping and starting the app is the clearest reset before a presentation.
You do not need to clear app storage, edit Supabase rows, recreate bills, or
protect a live notice.

---

## What demo mode does and does not prove

| Demonstrated in Week 11 demo mode | Requires later integration/device evidence |
|---|---|
| All role-based screens and navigation | Supabase connectivity and RLS |
| Seeded bills, receipts, notices, and notifications | Live RPC-generated identifiers |
| Form validation and success/empty states | Real notification delivery |
| Reading queued within the running app | Encrypted SQLite surviving force-stop |
| Safe, repeatable role walkthroughs | Reconnect, queue drain, and Admin seeing the synced reading |

Do not perform the airplane-mode force-stop test with this demo build. Its fake
outbox is intentionally in memory, so closing the process resets it. Perform the
production outbox test later with **BillAlert (dev)** or a configured integration
APK, a dedicated test household, and live Supabase.

---

## Week 11 evidence to capture

Capture screenshots or a short recording showing:

- [ ] The **BillAlert (demo data)** launch configuration or demo login state.
- [ ] Each role reaching its primary screen.
- [ ] Navigation among every major tab.
- [ ] A valid reading being accepted and a duplicate/invalid reading refused.
- [ ] The notice document and its close confirmation/success state.
- [ ] The Cashier payment flow and Receipts screen.
- [ ] The Consumer Bill, Bills/Payments History, receipt, Inbox, and Profile.

Describe the action, expected result, and observed result. Demo identifiers are
useful for matching screenshots, but they are controlled fixtures and should not
be presented as rows verified in the live database.
