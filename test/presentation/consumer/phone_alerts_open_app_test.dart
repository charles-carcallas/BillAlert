import 'package:billalert/domain/notifications/phone_alerts.dart';
import 'package:billalert/domain/usecases/consumer/refresh_phone_alerts.dart';
import 'package:billalert/domain/value_objects/ids.dart';
import 'package:billalert/presentation/consumer/inbox_controller.dart';
import 'package:billalert/presentation/consumer/phone_alerts_gate.dart';
import 'package:billalert/presentation/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/phone_alert_fakes.dart';

class _NotificationsOn implements NotificationPermission {
  @override
  Future<bool> isGranted() async => true;

  @override
  Future<bool> request() async => true;

  @override
  Future<void> openSettings() async {}
}

/// The Inbox, counting how often it is asked to reload.
class _CountingInbox extends InboxController {
  int loads = 0;

  @override
  InboxState build() => const InboxState();

  @override
  Future<void> load() async {
    loads++;
  }
}

/// Found on a phone: with the household's app open, a newly posted bill
/// reached the Inbox at once but the notification tray only after the next
/// background check, up to fifteen minutes later.
void main() {
  late FakeAlertFeed feed;
  late FakePhoneNotifier phone;
  late _CountingInbox inbox;

  Future<void> openApp(WidgetTester tester) async {
    feed = FakeAlertFeed();
    phone = FakePhoneNotifier();
    inbox = _CountingInbox();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          phoneNotifierProvider.overrideWithValue(phone),
          notificationPermissionProvider.overrideWithValue(_NotificationsOn()),
          backgroundAlertsProvider.overrideWithValue(FakeBackgroundAlerts()),
          refreshPhoneAlertsProvider.overrideWithValue(
            RefreshPhoneAlerts(
              feed: feed,
              phone: phone,
              clock: StoppedClock(DateTime.utc(2026, 9, 20)),
              urgentAlerts: FakeUrgentAlertsSetting(),
            ),
          ),
          inboxControllerProvider.overrideWith(() => inbox),
        ],
        child: const MaterialApp(home: PhoneAlertsGate(child: SizedBox())),
      ),
    );
    await tester.pump();
  }

  void postBill() {
    feed.pending = const <PendingPhoneAlert>[
      PendingPhoneAlert(
        id: NotificationId('n-new'),
        type: 'bill_ready',
        bill: BillId('b-new'),
      ),
    ];
  }

  testWidgets('a bill posted while the app is open reaches the tray within '
      'the minute, and the Inbox reloads', (WidgetTester tester) async {
    await openApp(tester);
    expect(phone.shown, isEmpty);

    postBill();
    await tester.pump(PhoneAlertsGate.openAppRefresh);
    await tester.pump();

    expect(phone.shown.single.title, 'Your bill is ready');
    expect(feed.markedShown.single.value, 'n-new');
    expect(inbox.loads, 1);
  });

  testWidgets('coming back to the app checks straight away', (
    WidgetTester tester,
  ) async {
    await openApp(tester);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    postBill();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(phone.shown, hasLength(1));
  });

  testWidgets('nothing new: the tray and the Inbox are left alone', (
    WidgetTester tester,
  ) async {
    await openApp(tester);

    await tester.pump(PhoneAlertsGate.openAppRefresh);
    await tester.pump();

    expect(phone.shown, isEmpty);
    expect(inbox.loads, 0);
  });
}
