import 'package:billalert/domain/entities/app_user.dart';
import 'package:billalert/domain/entities/bill.dart';
import 'package:billalert/domain/outbox/outbox_entry.dart';
import 'package:billalert/domain/usecases/consumer/refresh_phone_alerts.dart';
import 'package:billalert/domain/value_objects/cycle_label.dart';
import 'package:billalert/domain/value_objects/ids.dart';
import 'package:billalert/domain/value_objects/kwh.dart';
import 'package:billalert/domain/value_objects/money.dart';
import 'package:billalert/domain/value_objects/ph_date.dart';
import 'package:billalert/presentation/auth/auth_controller.dart';
import 'package:billalert/presentation/common/profile_screen.dart';
import 'package:billalert/presentation/providers.dart';
import 'package:billalert/presentation/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';
import '../../support/phone_alert_fakes.dart';

/// The household's "Urgent due-date alerts" switch on the Profile screen.
void main() {
  const ConsumerUser household = ConsumerUser(
    id: ProfileId('consumer-profile-1'),
    username: 'virgilio.busalanan',
    firstName: 'Virgilio',
    lastName: 'Busalanan',
    mustChangePassword: false,
  );

  late FakeUrgentAlertsSetting setting;
  late FakeAlertFeed feed;
  late FakePhoneNotifier phone;

  setUp(() {
    setting = FakeUrgentAlertsSetting();
    feed = FakeAlertFeed();
    phone = FakePhoneNotifier();
  });

  Future<void> openProfile(
    WidgetTester tester, {
    required FakeFullScreenAlerts fullScreen,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(
            () => FakeAuthController(signedInUser: household),
          ),
          pendingOutboxProvider.overrideWith(
            (Ref ref) async => const <OutboxEntry>[],
          ),
          profileConsumerProvider.overrideWith((Ref ref) async => null),
          fingerprintStatusProvider.overrideWith(
            (Ref ref) async => (available: false, on: false),
          ),
          urgentAlertsSettingProvider.overrideWithValue(setting),
          fullScreenAlertsProvider.overrideWithValue(fullScreen),
          refreshPhoneAlertsProvider.overrideWithValue(
            RefreshPhoneAlerts(
              feed: feed,
              phone: phone,
              // 20 September 2026, 08:00 in Manila.
              clock: StoppedClock(DateTime.utc(2026, 9, 20)),
              urgentAlerts: setting,
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const ProfileScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Urgent due-date alerts'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  Finder urgentSwitch() => find.descendant(
    of: find
        .ancestor(
          of: find.text('Urgent due-date alerts'),
          matching: find.byType(InkWell),
        )
        .first,
    matching: find.byType(Switch),
  );

  testWidgets('is on by default, and pops up loudly on Android 13 and older', (
    WidgetTester tester,
  ) async {
    await openProfile(tester, fullScreen: FakeFullScreenAlerts());

    expect(tester.widget<Switch>(urgentSwitch()).value, isTrue);
    expect(
      find.text('Before a bill is due, the reminder pops up with a loud sound'),
      findsOneWidget,
    );
  });

  testWidgets(
    'on Android 14 it fills the screen, and turning it on asks Android first',
    (WidgetTester tester) async {
      setting.on = false;
      final FakeFullScreenAlerts fullScreen = FakeFullScreenAlerts(
        androidFourteen: true,
      );
      await openProfile(tester, fullScreen: fullScreen);

      expect(
        find.text('Before a bill is due, the reminder fills the screen'),
        findsOneWidget,
      );

      await tester.tap(urgentSwitch());
      await tester.pumpAndSettle();

      expect(setting.on, isTrue);
      expect(fullScreen.requests, 1);
      expect(find.text('Urgent due-date alerts are on.'), findsOneWidget);
    },
  );

  testWidgets('says how to allow it when Android 14 is not allowed to', (
    WidgetTester tester,
  ) async {
    setting.on = false;
    await openProfile(
      tester,
      fullScreen: FakeFullScreenAlerts(androidFourteen: true, grants: false),
    );

    await tester.tap(urgentSwitch());
    await tester.pumpAndSettle();

    // Still on: the reminder pops up until Android allows the full screen.
    expect(setting.on, isTrue);
    expect(find.textContaining('Allow full-screen alerts'), findsOneWidget);
  });

  testWidgets('an older phone is never sent to a settings page', (
    WidgetTester tester,
  ) async {
    setting.on = false;
    final FakeFullScreenAlerts fullScreen = FakeFullScreenAlerts();
    await openProfile(tester, fullScreen: fullScreen);

    await tester.tap(urgentSwitch());
    await tester.pumpAndSettle();

    expect(setting.on, isTrue);
    expect(fullScreen.requests, 0);
  });

  testWidgets('turning it off makes a waiting reminder ordinary at once', (
    WidgetTester tester,
  ) async {
    feed.unpaid = <Bill>[
      const Bill(
        id: BillId('b-1'),
        billNo: BillNumber('BA-202609-000007'),
        consumerId: ConsumerId('consumer-1'),
        cycle: CycleLabel(2026, 9),
        consumption: Kwh.fromHundredths(1500),
        totalAmount: Money.fromCentavos(10000),
        dueDate: PhDate(2026, 9, 28),
        amountPaid: Money.fromCentavos(0),
      ),
    ];
    await openProfile(tester, fullScreen: FakeFullScreenAlerts());

    await tester.tap(urgentSwitch());
    await tester.pumpAndSettle();

    expect(setting.on, isFalse);
    expect(phone.scheduled.values.single.notice.urgent, isFalse);
    expect(
      find.text(
        'Urgent due-date alerts are off. Reminders arrive as ordinary '
        'notifications.',
      ),
      findsOneWidget,
    );
  });
}
