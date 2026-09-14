import '../../../core/result/result.dart';
import '../../entities/bill.dart';
import '../../notifications/phone_alerts.dart';
import '../../time/ph_clock.dart';
import '../../value_objects/ids.dart';
import '../../value_objects/ph_date.dart';

/// What one refresh did.
final class PhoneAlertReport {
  final int shown;
  final int remindersScheduled;

  /// The household has turned notifications off, so nothing was shown.
  final bool notificationsOff;

  const PhoneAlertReport({
    this.shown = 0,
    this.remindersScheduled = 0,
    this.notificationsOff = false,
  });
}

/// Brings the phone's notifications up to date with the server.
///
/// Runs from the background check every fifteen minutes or so, and once when
/// the household opens the app. It does two things:
///
/// 1. Shows every push notification the server queued and marks each one
///    `sent`. Posting a bill amount already queues one, so this is what turns
///    "the Admin posted my bill" into a notification without Firebase.
/// 2. Schedules a reminder for each unpaid bill, at 08:00 Philippine time,
///    `predue_reminder_days` before its due date. Android shows it at that
///    time whether or not the app is running, and whether or not there is
///    signal. Reminders for bills since paid are cancelled.
///
/// The words are chosen here, and never include an amount: a notification can
/// be read by whoever picks the phone up.
final class RefreshPhoneAlerts {
  /// Used when the server's setting cannot be read. Phase 1's figure.
  static const int fallbackReminderDays = 3;

  /// After people are up, and well before the cashier's counter closes.
  static const int reminderHourPh = 8;

  final AlertFeed feed;
  final PhoneNotifier phone;
  final PhClock clock;

  const RefreshPhoneAlerts({
    required this.feed,
    required this.phone,
    required this.clock,
  });

  Future<Result<PhoneAlertReport>> call() async {
    final ConsumerId? household;
    switch (await feed.signedInHousehold()) {
      case Err(:final failure):
        // Not knowing who is signed in — no signal, say — is not the same as
        // nobody being signed in, so nothing is cancelled on a failure.
        return Err<PhoneAlertReport>(failure);
      case Ok(:final value):
        household = value;
    }

    if (household == null) {
      // Signed out, or staff on this phone: nothing about a household's bills
      // may stay on it.
      await phone.cancelAll();
      return const Ok<PhoneAlertReport>(PhoneAlertReport());
    }

    final bool canNotify = await phone.canNotify();
    // Not shown and not marked: a notice marked sent while notifications are
    // off would be a delivery record for something nobody saw.
    final int shown = canNotify ? await _showPending(household) : 0;
    // Scheduled regardless, so they are in place the moment the household
    // turns notifications back on.
    final int scheduled = await _planReminders(household);

    return Ok<PhoneAlertReport>(
      PhoneAlertReport(
        shown: shown,
        remindersScheduled: scheduled,
        notificationsOff: !canNotify,
      ),
    );
  }

  Future<int> _showPending(ConsumerId household) async {
    final List<PendingPhoneAlert> alerts;
    switch (await feed.pendingAlerts(household)) {
      case Err():
        return 0; // The next run tries again.
      case Ok(:final value):
        alerts = value;
    }

    for (final PendingPhoneAlert alert in alerts) {
      final (String title, String body) = _wordingFor(alert.type);
      await phone.show(
        PhoneNotice(
          id: stableNoticeId('alert:${alert.id.value}'),
          title: title,
          body: body,
          payload: PhoneNoticePayload.inbox,
        ),
      );
      // Shown first, marked second. If marking fails, the next run shows it
      // again under the same id, which replaces it rather than duplicating.
      await feed.markShown(alert.id);
    }
    return alerts.length;
  }

  Future<int> _planReminders(ConsumerId household) async {
    final List<Bill> bills;
    switch (await feed.unpaidBills(household)) {
      case Err():
        // Unknown is not "paid": leave whatever is scheduled alone.
        return 0;
      case Ok(:final value):
        bills = value;
    }

    final int days = switch (await feed.reminderDaysBeforeDue()) {
      Ok(:final value) => value ?? fallbackReminderDays,
      Err() => fallbackReminderDays,
    };
    final DateTime now = clock.nowUtc();
    final Set<int> planned = <int>{};

    for (final Bill bill in bills) {
      final PhDate? due = bill.dueDate;
      if (due == null || bill.isSettled) continue;

      final DateTime at = reminderTimeFor(due, days);
      // A reminder whose moment has passed is not sent late. The bill is
      // either nearly due or overdue by then, and the server has other
      // notices for that.
      if (!at.isAfter(now)) continue;

      final int id = stableNoticeId('reminder:${bill.id.value}');
      await phone.schedule(
        PhoneNotice(
          id: id,
          title: _reminderTitle(days),
          body:
              'Your ${bill.cycle.displayName} bill is due on '
              '${_dayAndMonth(due)}. If you have already paid, you can ignore '
              'this.',
          payload: PhoneNoticePayload.bill,
        ),
        atUtc: at,
      );
      planned.add(id);
    }

    for (final int id in await phone.scheduledIds()) {
      if (!planned.contains(id)) await phone.cancel(id);
    }
    return planned.length;
  }

  /// 08:00 Philippine time, [days] before [due], as a UTC instant.
  static DateTime reminderTimeFor(PhDate due, int days) {
    final DateTime day = DateTime.utc(
      due.year,
      due.month,
      due.day,
    ).subtract(Duration(days: days));
    return DateTime.utc(
      day.year,
      day.month,
      day.day,
      reminderHourPh,
    ).subtract(PhDate.utcOffset);
  }

  static (String, String) _wordingFor(String type) => switch (type) {
    'bill_ready' => (
      'Your bill is ready',
      'The amount for your latest bill has been posted. Tap to see it.',
    ),
    'pre_due_reminder' => (
      'Bill due soon',
      'A bill is due soon. Tap to see the due date.',
    ),
    'overdue' => (
      'Bill overdue',
      'A bill is past its due date. Tap to see it.',
    ),
    'disconnection' => (
      'Disconnection notice',
      'A disconnection notice was issued for your account. Tap for details.',
    ),
    _ => ('BillAlert', 'You have a new notification. Tap to see it.'),
  };

  static String _reminderTitle(int days) => switch (days) {
    <= 0 => 'Bill due today',
    1 => 'Bill due tomorrow',
    _ => 'Bill due in $days days',
  };

  static String _dayAndMonth(PhDate date) {
    const List<String> months = <String>[
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${date.day} ${months[date.month - 1]}';
  }
}
