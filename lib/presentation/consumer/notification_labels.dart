import 'package:flutter/material.dart';

import '../../domain/value_objects/ph_date.dart';

/// How the Inbox names a notification. Shared by the list and the details
/// sheet, so a notice cannot be called one thing in the list and another
/// once it is opened.

/// The server's `notification_type` enum, in words a household would use.
String notificationTitle(String type) => switch (type) {
  'bill_ready' => 'Your bill is ready',
  'pre_due_reminder' => 'Payment reminder',
  'overdue' => 'Bill is overdue',
  'disconnection' => 'Disconnection notice served',
  _ => 'Notice',
};

IconData notificationIcon(String type) => switch (type) {
  'bill_ready' => Icons.description_outlined,
  'pre_due_reminder' => Icons.schedule_outlined,
  'overdue' => Icons.warning_amber_outlined,
  'disconnection' => Icons.power_off_outlined,
  _ => Icons.notifications_none,
};

/// The label above an alert that asks the household to act, or null.
String? notificationUrgency(String type) => switch (type) {
  'disconnection' => 'IMMEDIATE ACTION',
  'overdue' => 'ACTION NEEDED',
  _ => null,
};

bool isUrgentNotification(String type) => notificationUrgency(type) != null;

const List<String> _shortMonths = <String>[
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

const List<String> _longMonths = <String>[
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

/// "10 Sep · 4:55 AM", or "10 Sep 2026 · 4:55 AM" [withYear], in Philippine
/// time. The instant is UTC, and an alert queued at 7am in Tubod is the
/// previous day in UTC.
String phDateTimeLabel(DateTime instant, {bool withYear = false}) {
  final PhDate day = PhDate.at(instant);
  final DateTime manila = instant.toUtc().add(PhDate.utcOffset);
  final int hour24 = manila.hour;
  final int hour = hour24 % 12 == 0 ? 12 : hour24 % 12;
  final String minute = manila.minute.toString().padLeft(2, '0');
  final String date = withYear
      ? '${day.day} ${_shortMonths[day.month - 1]} ${day.year}'
      : '${day.day} ${_shortMonths[day.month - 1]}';
  return '$date · $hour:$minute ${hour24 < 12 ? 'AM' : 'PM'}';
}

/// "28 September 2026".
String friendlyPhDate(PhDate date) =>
    '${date.day} ${_longMonths[date.month - 1]} ${date.year}';
