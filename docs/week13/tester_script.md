# BillAlert beta — what each tester does

One page. Four people, four phones, one run through the whole month of work
a barangay does with BillAlert. The database starts empty, so **the order
matters**: nothing exists until the Area President creates it.

Ask the testers to say out loud what they see. Where it is confusing, that is
the finding, and it should be written down rather than smoothed over.

---

## Before you start

- Everyone installs BillAlert from the **Firebase App Distribution** email
  invitation. Any older BillAlert must be **uninstalled first**.
- The Area President has the only account that already exists.
- One phone should have a real SIM, so the bill text can be seen arriving.
- Tester 4's household needs a **contact number** to get that text.

| Who | Role | Gets their account from |
|---|---|---|
| Tester 1 | Area President (Admin) | Already exists: Mario Ombajin |
| Tester 2 | Meter Reader | Tester 1 creates it in step 1 |
| Tester 3 | Cashier | Tester 1 creates it in step 2 |
| Tester 4 | Consumer (household) | Tester 1 creates it in steps 3 and 4 |

---

## Step 1 — Area President creates the Meter Reader

**Accounts** tab → **Staff account** → fill in the name and pick
**Meter Reader** → confirm.

BillAlert shows a **username and a temporary password**. Write them down and
give them to Tester 2; they are shown once.

> Tester 2: sign in, and change the password when asked.

## Step 2 — Area President creates the Cashier

The same screen, this time choosing **Cashier**. Hand the username and
temporary password to Tester 3, who signs in and changes the password.

## Step 3 — Area President creates the household

**Accounts** tab → **Consumer account**. Fill in:

- Account number, for example `2026-1234-TUB`
- First and last name
- **Contact number** — use Tester 4's real number, so the text arrives
- Purok, and the meter number

Confirm. This is the household, not yet a login.

## Step 4 — Area President gives that household a sign-in

Straight after creating it, choose **Create a sign-in for this household**,
or **Accounts → Consumer account → household login**. Confirm the username.

Hand the username and temporary password to Tester 4, who signs in, changes
the password, and sets up the fingerprint if their phone offers it.

---

## Step 5 — Meter Reader records the reading

**Readings** tab → the household → type the current meter figure → save.

- It saves on the phone first, so it works with no signal.
- **No alert goes out yet.** The household is told when the amount is posted,
  not when the meter is read. Say so if a tester expects one.

## Step 6 — Area President posts the amount

**Amounts** tab → the waiting household → enter the amount from the
cooperative's statement, **including centavos**, for example `529.40`, and a
**due date in the future**.

- The household is billed the **rounded** figure, `530.00`. The difference is
  the Meter Reader's pay, and only the Cashier sees it.
- The due date does **not** change which month the bill belongs to. That comes
  from the reading date.

Confirm the posting. This is the moment the household is told.

## Step 7 — Consumer sees the bill

Tester 4, on their phone:

- The **Bill** tab shows the amount and the due date.
- The **Inbox** shows the alert.
- Within about a minute, a **text message** arrives with the amount and due
  date. It goes to every household, including ones with a keypad phone.

Ask them: is the amount clear? Do they know when and where to pay?

## Step 8 — Cashier takes the payment

Tester 3: **Consumers** tab → the household → **take payment** → enter the
cash handed over → confirm.

A receipt is issued, with a number and a verification code. Show the receipt
to Tester 4.

## Step 9 — Consumer checks their history

Tester 4: **History** tab. The bill now shows as paid, with the receipt
against it. Opening it shows the meter readings behind the figure.

## Step 10 — the month's money

**Cashier → Remit:** the amount to hand over to BOHECO, the rounding, the
Meter Reader's pay (₱300 at most), what is saved in the fund, and what is
still unpaid. **Mark as handed over** records giving the money to the Meter
Reader.

**Meter Reader → Remit:** the same month, showing only what to carry to the
BOHECO office and what is still unpaid. The reader is never shown the
rounding or their own pay.

---

## What to write down

For each tester, in their own words:

1. Anything they could not find, and where they looked first.
2. Anything that made them hesitate, or that they read twice.
3. Any word that did not match how they say it in the barangay.
4. Anything that felt slow.
5. One thing they liked.

Honest answers are the point. "It worked fine" from four people is not
feedback, and the instructor will ask them directly.

---

## If something goes wrong

- **A text does not arrive:** the household may have no contact number, or the
  gateway phone may be off. Check the Area President's account list.
- **A notification does not appear:** open the app; it checks straight away
  when opened, and only every 15 minutes in the background.
- **"No connection":** the work is saved on the phone and sent when the signal
  is back. Nothing is lost. This is worth demonstrating deliberately: turn on
  aeroplane mode, record a reading, turn it off again, and watch it sync.
