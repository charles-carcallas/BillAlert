import 'dart:typed_data';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../domain/notifications/phone_alerts.dart';

/// Android's notification tray, through flutter_local_notifications.
///
/// Every call is caught. Notifications sit on top of the Bill and Inbox tabs,
/// which show the same facts, so a phone that cannot notify must never stop
/// the household from using the app.
class AndroidPhoneNotifier
    implements PhoneNotifier, NotificationPermission, FullScreenAlerts {
  static const String _channelId = 'billalert_bills';

  /// One channel for everything, so the household has one switch in Android's
  /// settings rather than having to find several.
  static const NotificationDetails _details = NotificationDetails(
    android: AndroidNotificationDetails(
      _channelId,
      'Bills and notices',
      channelDescription:
          'New bills, due-date reminders and notices about your account.',
      importance: Importance.high,
      priority: Priority.high,
      // The lock screen says "BillAlert" and nothing more until the phone is
      // unlocked. The text carries no amount anyway, but the month and the
      // due date are still the household's business.
      visibility: NotificationVisibility.private,
    ),
  );

  /// Urgent due-date reminders have a channel of their own. Android fixes a
  /// channel's sound and vibration the first time it is used, so the loud
  /// reminder cannot share the ordinary one.
  static const String _urgentChannelId = 'billalert_due_urgent';

  static final Int64List _urgentVibration = Int64List.fromList(<int>[
    0,
    700,
    300,
    700,
    300,
    700,
  ]);

  static NotificationDetails _urgentDetails({required bool fillScreen}) =>
      NotificationDetails(
        android: AndroidNotificationDetails(
          _urgentChannelId,
          'Urgent due-date alerts',
          channelDescription:
              'The reminder before a bill is due. Turn off "Urgent due-date '
              "alerts\" in BillAlert's Profile for an ordinary notification.",
          importance: Importance.max,
          priority: Priority.max,
          visibility: NotificationVisibility.private,
          category: AndroidNotificationCategory.reminder,
          // Played as an alarm, so it is heard with the ringer on silent.
          audioAttributesUsage: AudioAttributesUsage.alarm,
          vibrationPattern: _urgentVibration,
          // Android 14 and later fill the screen while the phone is locked or
          // asleep, and pop up while it is in use. Android 13 and older pop up.
          fullScreenIntent: fillScreen,
          actions: const <AndroidNotificationAction>[
            AndroidNotificationAction(
              'view_bill',
              'View bill',
              showsUserInterface: true,
            ),
          ],
        ),
      );

  /// Whether this phone runs Android 14 or later. Read once per isolate.
  static Future<bool>? _androidFourteenOrLater;

  final FlutterLocalNotificationsPlugin _plugin;

  AndroidPhoneNotifier([FlutterLocalNotificationsPlugin? plugin])
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  @override
  Future<void> initialize({void Function(String? payload)? onTap}) async {
    try {
      // Called again whenever a new tap handler is ready, which replaces the
      // old one. A handler kept from a screen that has gone would navigate
      // from nowhere.
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
        onDidReceiveNotificationResponse: onTap == null
            ? null
            : (NotificationResponse response) => onTap(response.payload),
      );
    } catch (_) {}
  }

  @override
  Future<String?> launchPayload() async {
    try {
      final details = await _plugin.getNotificationAppLaunchDetails();
      if (details == null || !details.didNotificationLaunchApp) return null;
      return details.notificationResponse?.payload;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> canNotify() => isGranted();

  @override
  Future<bool> isGranted() async {
    try {
      // Null means this is not Android, where there is nothing to ask.
      return await _android?.areNotificationsEnabled() ?? true;
    } catch (_) {
      return true;
    }
  }

  @override
  Future<bool> request() async {
    try {
      return await _android?.requestNotificationsPermission() ?? true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> openSettings() async {
    try {
      await _android?.openAppNotificationSettings();
    } catch (_) {}
  }

  @override
  Future<bool> fillsScreen() =>
      _androidFourteenOrLater ??= _readAndroidFourteenOrLater();

  static Future<bool> _readAndroidFourteenOrLater() async {
    try {
      final AndroidDeviceInfo info = await DeviceInfoPlugin().androidInfo;
      return info.version.sdkInt >= 34;
    } catch (_) {
      // Not Android, or the version cannot be read. A pop-up needs nothing
      // from Android that might not have been allowed.
      return false;
    }
  }

  @override
  Future<bool> allow() async {
    try {
      if (!await fillsScreen()) return true;
      return await _android?.requestFullScreenIntentPermission() ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<NotificationDetails> _detailsFor(PhoneNotice notice) async =>
      notice.urgent
      ? _urgentDetails(fillScreen: await fillsScreen())
      : _details;

  @override
  Future<void> show(PhoneNotice notice) async {
    try {
      await _plugin.show(
        id: notice.id,
        title: notice.title,
        body: notice.body,
        notificationDetails: await _detailsFor(notice),
        payload: notice.payload,
      );
    } catch (_) {}
  }

  @override
  Future<void> schedule(PhoneNotice notice, {required DateTime atUtc}) async {
    try {
      await _plugin.zonedSchedule(
        id: notice.id,
        // In UTC, so the moment does not depend on the phone's own time zone
        // setting. RefreshPhoneAlerts already turned 08:00 Manila into UTC.
        scheduledDate: tz.TZDateTime.from(atUtc, tz.UTC),
        notificationDetails: await _detailsFor(notice),
        // Inexact: Android may shift a reminder by some minutes to save
        // battery, which a due-date reminder can afford. Exact alarms need a
        // permission Android 14 makes the household grant by hand.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        title: notice.title,
        body: notice.body,
        payload: notice.payload,
      );
    } catch (_) {}
  }

  @override
  Future<Set<int>> scheduledIds() async {
    try {
      return (await _plugin.pendingNotificationRequests())
          .map((PendingNotificationRequest request) => request.id)
          .toSet();
    } catch (_) {
      return <int>{};
    }
  }

  @override
  Future<void> cancel(int id) async {
    try {
      await _plugin.cancel(id: id);
    } catch (_) {}
  }

  @override
  Future<void> cancelAll() async {
    try {
      await _plugin.cancelAll();
    } catch (_) {}
  }
}
