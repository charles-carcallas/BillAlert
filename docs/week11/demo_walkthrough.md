# Demo walkthrough — all four roles on the phone

Every screen is built and routed. What has *not* happened is a person holding
a phone and walking the whole thing end to end. The three worst bugs of this
project — the missing INTERNET permission, the views that bypassed RLS, and
the billing cycle the app and database disagreed about — were all found by
*using* the app or its data, not by testing it.

Work down this list in order. Anything that misbehaves, write down what you
did and what it said, not just "broken".

---

## 0. Before you build

- [ ] `supabase/migrations/03_views.sql` re-run — the `amount_overdue` fix.
      Without it the notice document overstates what a household owes.

```bash
flutter build apk --release --dart-define-from-file=env.json
```

`env.json` holds `SUPABASE_URL` and `SUPABASE_ANON_KEY`, generated from
`.vscode/launch.json` and gitignored. Use it rather than two `--dart-define`
flags: an APK built without them installs and runs perfectly, then fails
**every** sign-in with "Something went wrong on the server" — which looks like
a backend problem and is not. That has already cost one build.

- [ ] Built and installed

---

## The data you are walking into

| Household | State | Used for |
|---|---|---|
| **Virgilio Busalanan** | paid in full, **the only household that can sign in** | the whole live chain |
| Elena Bongcaras | overdue ₱541.20, **active notice DN-2026-0910-0033** | the notice document |
| Rodel Amistad | overdue ₱612.35, no notice | serving a notice live |
| B. Sarigumba | overdue ₱533.45, Aug bill ₱658.30 unpaid | cashier collection |
| Teresita Lumayag | paid in full | the eligibility guard |

The **September cycle is empty** — no household has been read. That is what
steps 1 and 5 need.

### Read BUSALANAN's meter in step 1

`virgilio.busalanan` is the only consumer login that exists. Every other
household has `profile_id` null and cannot sign in, so a receipt handed to
any of them can never be opened by a consumer.

Read his meter, post his amount, collect his payment — and step 4 signs in
as him and watches the receipt appear. That is the entire system in one
unbroken pass, and it needs no new account.

He already has one receipt from earlier — `BIEC-2026-09-004471`, settling
two months on one number. After step 3 he will have two, which also shows
History with more than a single row in it.

---

## 1. Meter Reader — `ledesman.dormal`

- [ ] Sign in. Lands on **Readings**.
- [ ] The round says **September 2026** and lists all five households unread.
- [ ] Tap **Virgilio Busalanan** (2019-0917-TUB) → the form opens with his
      previous reading, 3475.
- [ ] Type a reading **above** it — 3538 gives 63 kWh — → Save → confirmation.

**Read ONE household only, and make it Busalanan.** He is the only consumer
who can sign in, so he is the only one who can open the receipt in step 4.
Step 5 needs unread households left, and once a household is read this cycle
FR-23 will not let you read it again.

- [ ] Go back into that same household → refused. *(FR-23.)*
- [ ] On a different household, try a reading **below** the previous → refused.
      *(MTR-08, a meter does not run backwards.)*
- [ ] **Consumers** tab lists the area; **Profile** says "Meter Reader".

Write down which household you read and the number you typed.

---

## 2. Admin (Area President) — `mario.ombajin`

**Amounts:**

- [ ] The reading from step 1 is in the queue with how long it has waited.
- [ ] Type the peso amount and a due date → Post. **The amount comes from the
      cooperative's bill.** BillAlert computes no amount — there is no tariff
      anywhere in this codebase, by design.
- [ ] It leaves the queue.

**Accounts:**

- [ ] Opens on the households of Area 3, with a count.
- [ ] Pull down to refresh.
- [ ] **New consumer** → consumer number, first and last name → Create.
- [ ] Confirmation shows the name and number back.
- [ ] **Done** → back on the list, and *the new household is in it.* If it is
      missing, the server refresh on return is broken.
- [ ] Try a consumer number that already exists → it should say the number is
      in use, not "something went wrong".
- [ ] The foot of the tab says staff sign-ins cannot be created here. That is
      the honest answer, not a missing screen — it needs the service-role key,
      which must never be inside an app anyone can install.

**Notices:**

- [ ] Elena's notice is listed with hours remaining.
- [ ] **Tap it** → the notice document opens: notice number, her address and
      meter serial, the reason, when it was served, the earliest lawful
      moment, and what she owes.
- [ ] Check the amount reads **₱541.20** — her overdue balance, not her total
      unpaid. If it shows more, `03_views.sql` was not re-run.
- [ ] Read the line saying BillAlert never authorises, schedules, or executes
      a disconnection. "Referred" records a handover to the cooperative.
- [ ] **Do not close Elena's notice yet** — closing it removes it from the
      list, and you want it there if you demo this twice.
- [ ] Back → **Serve a notice** → Rodel and Sarigumba are listed first;
      Busalanan and Lumayag are greyed out with "nothing overdue".
- [ ] Serve one on **Rodel** → confirm → it appears in the list.
- [ ] Open Rodel's document → record the outcome as **settled** → it leaves
      the list. That is `fn_close_disconnection_notice`, the last RPC.

The countdown is worked out server-side: 48 hours from service, then past any
Sunday or holiday, then into the 08:00 window. Elena's was served 10 Sep
04:55 and is lawful from **14 Sep 08:00** — Saturday skipped, Sunday skipped.
The app never computes that.

---

## 3. Cashier — `mercedita.gales`

- [ ] Sign in. Lands on the payment screen.
- [ ] Search for **Busalanan** — the household whose amount you posted in step 2.
- [ ] Its unpaid bills are listed with real amounts.
- [ ] Select the bills, enter cash tendered → Record payment.
- [ ] A receipt number, a verification code, and the change due come back.
- [ ] **Receipts** tab shows it in today's collection.

**Write down the receipt number.**

---

## 4. Consumer — `virgilio.busalanan`

The only consumer login that exists, which is why steps 1 to 3 were all done
against his household.

- [ ] Sign in. If it demands a new password, there is nowhere else to go —
      that is deliberate (GEN-04).
- [ ] **Bill** shows the current bill, or an honest "waiting for the amount".
- [ ] **History** lists **three** months now: July and August settled on
      receipt `BIEC-2026-09-004471`, and September on the receipt you just
      created.
- [ ] Tap the September row → **the receipt opens**, and its number matches
      what the cashier read out. Reader → Admin → Cashier → Consumer, in one
      glance.
- [ ] Tap the July row → the OLDER receipt opens, and July and August share
      one number. That is correct: the money changed hands once, so there is
      one receipt covering both months.
- [ ] The verification code is text, not a QR, and the screen says why.
- [ ] **Inbox** shows notifications, or says there are none.
- [ ] **Profile** → change password → sign out → sign back in → change it back.
- [ ] Try changing it to the password it already is. It must say the new one
      has to be different — **not** "you have been signed out".

---

## 5. The offline test — this is the graded one

NFR-05 and MTR-11/12. The only requirement with no evidence at all, and the
reason the outbox exists. Do it last, and carefully.

- [ ] Sign in as `ledesman.dormal` **with signal**, so the roster caches.
- [ ] Turn on **airplane mode**.
- [ ] Open **Consumers** — the households are still there. From the encrypted
      cache. This is the point.
- [ ] Record a reading on a household you did **not** read in step 1.
- [ ] It **saves** and says it is queued. No network error, no lost reading.
- [ ] **Force-stop the app** from Android settings. Not just background it.
- [ ] Reopen, still in airplane mode → the reading is still queued.
      *(This replaces "survives restart — not verified" in the evidence log.)*
- [ ] Turn airplane mode **off**.
- [ ] The queue drains and the reading syncs.
- [ ] Sign in as `mario.ombajin` → that household is in the Amounts queue.

The reading's time should be **when you typed it in airplane mode**, not when
it synced. That is `capturedAt`, and it is why a reading lands in the right
billing cycle when a reader walks a whole barangay with no signal.

---

## What to record

For `evidence_log.md`, per step: what you did, what the app showed, and the
identifier it produced — bill number, receipt number, notice number, consumer
number. An identifier is what makes it evidence rather than a claim, because
it can be looked up in the database afterwards.

Two lines in that log still read **not verified — needs a device**. Step 5 is
what replaces them.
