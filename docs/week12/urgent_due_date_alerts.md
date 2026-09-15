# Urgent due-date alerts

**The request (instructor, 15 September 2026):** alert households with an
emergency alert (WEA / cell broadcast) 3 days before a bill is due. If that is
not possible, find another way.

**Decision:** cell broadcast is not possible for BillAlert. The app instead
makes its existing 3-day reminder as hard to miss as Android allows: **full
screen on Android 14 and later**, and a **loud pop-up on Android 13 and older**.
Households can switch it off in Profile.

---

## Why not an emergency alert

In the Philippines, emergency alerts to phones go through the **Emergency Cell
Broadcast System (ECBS)**:

- The system exists under **Republic Act 10639**, the Free Mobile Disaster
  Alerts Act, and is meant for natural and man-made disasters and calamities.
- The **NDRRMC** writes the alerts, with input from other government agencies,
  and the **telcos** broadcast them.
- There is no way for an app or a private system to send one, and using the
  channel for anything but disaster warnings has drawn public criticism from
  government.

A bill reminder is not a disaster warning, so this channel is closed to
BillAlert both technically and legally.

Sources:
[Emergency Cell Broadcast System (Wikipedia)](https://en.wikipedia.org/wiki/Emergency_Cell_Broadcast_System) ·
[IRR of RA 10639, Supreme Court E-Library](https://elibrary.judiciary.gov.ph/thebookshelf/showdocs/10/72097) ·
[OCD, Comelec hit alert system misuse (Inquirer)](https://www.inquirer.net/435322/ocd-comelec-hit-alert-system-misuse/)

---

## What BillAlert does instead

An emergency alert does two things: it reaches the phone whatever the person
is doing, and it can't be missed. Android's **full-screen notification** is the
closest thing an app is allowed. It is what alarm clocks and incoming calls use.

| | Android 14 and later | Android 13 and older |
|---|---|---|
| **When** | 08:00 Philippine time, `settings.predue_reminder_days` (3) days before the due date, for every unpaid bill | same |
| **Phone locked or asleep** | The screen wakes, and BillAlert asks for the phone's own unlock straight away. The bill only shows after unlocking. | A pop-up with the alarm sound and a strong vibration pattern |
| **Phone in use** | A pop-up (Android's rule for full-screen alerts) | same pop-up |
| **Permission** | Android reserves full screen for alarm and calling apps, so the household allows it once. Profile opens Android's page when the switch is turned on. Until then it's a pop-up. | none needed |
| **Buttons** | *View bill* opens the bill; swiping away dismisses it | same |

- **Profile switch:** "Urgent due-date alerts" under Notifications, **on by
  default**. Turning it off makes reminders ordinary notifications again,
  including ones already scheduled.
- **Separate channel:** the alert uses its own Android channel, "Urgent
  due-date alerts", so it doesn't change how new-bill notices behave.
- **Who gets it:** smartphone households with the app. The team decided on
  15 September that the 3-day reminder is app-only. Keypad-phone households get
  the bill by text when the amount is posted (`14_bill_sms.sql`), with no
  3-day text.

**Privacy.** A full-screen alert shows above the lock screen. BillAlert only
lets itself show there for the alert that woke the phone, and asks for the
phone's unlock at once. Nobody holding a locked phone sees a bill or an
amount. The notification text never includes an amount.

---

## Where it lives in the code

| Part | File |
|---|---|
| The rule: due-date reminders are urgent while the switch is on | `lib/domain/usecases/consumer/refresh_phone_alerts.dart` |
| The switch, stored on the phone (on unless turned off) | `lib/data/notifications/secure_urgent_alerts_setting.dart` |
| Full screen vs pop-up, by Android version | `lib/data/notifications/android_phone_notifier.dart` |
| Waking the screen and asking for the unlock | `android/app/src/main/kotlin/com/example/billalert/MainActivity.kt` |
| Permission | `USE_FULL_SCREEN_INTENT` in `android/app/src/main/AndroidManifest.xml` |
| Profile switch | `lib/presentation/common/profile_screen.dart` |

---

## Limits to know

- **Timing:** the reminder is scheduled as an inexact alarm, so Android may
  show it some minutes after 08:00 to save battery.
- **Do Not Disturb:** it can still hold the sound back, depending on the
  phone's settings.
- **Google Play:** Play only lets alarm and calling apps keep the full-screen
  permission. The beta goes out through Firebase App Distribution, so this does
  not apply now, but it would if BillAlert were published on Play.

## How to see it

The team's test phone, a Samsung Galaxy A31, runs **Android 12**, so it shows
the **loud pop-up**. Seeing the full screen needs a phone on Android 14 or
later.

To see it tomorrow instead of 3 days before a real due date, bring the
reminder forward, open BillAlert as the household so it reschedules, lock the
phone, and wait for 08:00. Then put the setting back:

```sql
-- e.g. a bill due 29 September: 13 days before is 16 September
update settings set predue_reminder_days = 13;
-- afterwards
update settings set predue_reminder_days = 3;
```
