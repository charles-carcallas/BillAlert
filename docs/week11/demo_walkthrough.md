# Demo walkthrough — all four roles on the phone

Everything in BillAlert is now built and wired. What has *not* happened is a
person holding a phone and walking the whole thing end to end. Nine of these
screens have never run on a device, and the three worst bugs of this project
so far — the missing INTERNET permission, the views that bypassed RLS, the
"you have been signed out" on a correct password — were all found by *using*
the app, not by testing it.

Work down this list. Tick as you go. Anything that misbehaves, write down what
you did and what it said, not just "broken".

---

## 0. Build the APK

```bash
flutter build apk --release --dart-define-from-file=env.json
```

`env.json` holds `SUPABASE_URL` and `SUPABASE_ANON_KEY`, generated from
`.vscode/launch.json` and gitignored. Use it rather than typing two
`--dart-define` flags: an APK built without them installs and runs perfectly,
then fails **every** sign-in with "Something went wrong on the server" — which
looks like a backend problem and is not. That mistake has already cost one
build.

The APK lands at `build/app/outputs/flutter-apk/app-release.apk`.

- [ ] Built with `--dart-define-from-file=env.json`
- [ ] Installed on the phone

---

## 1. Meter Reader — `ledesman.dormal`

- [ ] Sign in. Lands on **Readings**, not on somebody else's home screen.
- [ ] The round shows real households for Area 3 with their last reading.
- [ ] Tap a household → the entry form opens with the previous reading shown.
- [ ] Type a reading **above** the previous one → Save → confirmation.
- [ ] Go back in and try that **same household again** → refused.
      *(FR-23, one reading per household per cycle.)*
- [ ] Try a reading **below** the previous one on another household → refused.
      *(MTR-08, a meter does not run backwards.)*
- [ ] **Consumers** tab lists the area; **Profile** shows "Meter Reader".

Write down: the household you read, and the number you typed. The Admin needs
it in step 2.

---

## 2. Admin (Area President) — `mario.ombajin`

- [ ] Sign in. Lands on **Amounts**.
- [ ] The reading from step 1 is in the queue, with how long it has waited.
- [ ] Type the peso amount and a due date → Post.
      **The amount comes from the cooperative's own bill.** BillAlert never
      computes one — there is no tariff anywhere in this codebase, by design.
- [ ] It leaves the queue.

**Accounts tab — new, never run on a device:**

- [ ] Opens on the households of Area 3, with a count.
- [ ] Pull down to refresh — the list comes from the server.
- [ ] Tap **New consumer** → fill in a consumer number, first and last name →
      Create.
- [ ] Confirmation shows the name and number back.
- [ ] **Done** → you are back on the list and *the new household is in it.*
      This is the bit worth watching: the record is written to Supabase, not
      to the phone's cache, so the list refreshes from the server on the way
      back. If the new name is missing, that refresh is broken.
- [ ] Try creating one with a consumer number that already exists → it should
      say the number is in use, not "something went wrong".
- [ ] The card at the foot says staff sign-ins cannot be created here. That is
      the honest answer, not a missing screen: creating an auth user needs the
      service-role key, and that key must never be inside an app anyone can
      install.

**Notices tab:**

- [ ] Lists active notices, or says plainly there are none.
- [ ] **Serve a notice** → households with overdue bills are listed first,
      households with nothing overdue are greyed out and untappable.
- [ ] Pick an overdue one → confirm dialog → serve.
- [ ] It appears under Notices with hours remaining. That countdown comes from
      the server (48 hours from service, then past any Sunday or holiday) —
      the app never works out a legal deadline itself.

---

## 3. Cashier — `mercedita.gales`

- [ ] Sign in. Lands on the payment screen.
- [ ] Search for the household whose amount was posted in step 2.
- [ ] Its unpaid bills are listed with the real amounts.
- [ ] Select the bills, enter cash tendered → Record payment.
- [ ] A receipt number and a verification code come back, with the change due.
- [ ] **Receipts** tab shows it in today's collection.

**Write down the receipt number.** You need it in step 4.

---

## 4. Consumer — the household you just took money from

The seeded consumer logins are `virgilio.busalanan`, `teresita.lumayag`, and
so on. First sign-in forces a password change (GEN-04) unless it has been
changed already.

- [ ] Sign in. If it demands a new password, there is nowhere else to go —
      that is deliberate.
- [ ] **Bill** shows the current bill: priced, with the amount and due date, or
      an honest "waiting for the amount" if it has not been posted.
- [ ] **History** lists past months with their status.
- [ ] Tap the month that was just settled → **the receipt opens**, and the
      receipt number matches what the cashier read out in step 3. That match
      is the whole system in one glance: reader → admin → cashier → consumer.
- [ ] The verification code is printed as text. The mockup shows a QR; the
      screen says why it does not, rather than pretending.
- [ ] **Inbox** shows notifications, or says there are none.
- [ ] **Profile** → change password → change it, sign out, sign back in with
      the new one. Then put it back to the demo password.
- [ ] While in there: try changing it to the *same* password it already is.
      It must say the new password has to be different — **not** "you have
      been signed out". That bug is fixed and regression-tested; confirm it on
      the device.

---

## 5. The offline test — this is the graded one

NFR-05 and MTR-11/12. It is the only requirement with no evidence at all, and
it is the requirement this whole outbox architecture exists for. Do it last,
and do it carefully.

- [ ] Sign in as `ledesman.dormal` **with signal**, so the roster caches.
- [ ] Turn on **airplane mode**.
- [ ] Open **Consumers** — the households are still there. (From the encrypted
      cache. This is the point.)
- [ ] Record a reading on a household not yet read this cycle.
- [ ] It **saves** and says it is queued. It must not show a network error and
      it must not lose the reading.
- [ ] **Force-stop the app** from Android settings. Not just background it.
- [ ] Reopen it, still in airplane mode → the queued reading is still queued.
      *(This is the "survives restart" line in the evidence log.)*
- [ ] Turn airplane mode **off**.
- [ ] The queue drains. The reading syncs.
- [ ] Sign in as `mario.ombajin` → that household is now in the Amounts queue
      as an unpriced bill.

The time on the reading should be **when you typed it in airplane mode**, not
when it synced. That is `capturedAt`, and it is why the bill lands in the right
billing cycle even when a reader walks a whole barangay with no signal.

---

## What to record

For `evidence_log.md`, per step: what you did, what the app showed, and the
identifier it produced — bill number, receipt number, consumer number. An
identifier is what makes it evidence rather than a claim; it can be looked up
in the database afterwards.

Two lines in that log currently read **not verified — needs a device**. Step 5
is what replaces them.
