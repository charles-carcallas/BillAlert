import 'package:billalert/core/errors/app_failure.dart';
import 'package:billalert/domain/entities/app_user.dart';
import 'package:billalert/domain/outbox/outbox_entry.dart';
import 'package:billalert/domain/value_objects/ids.dart';
import 'package:billalert/presentation/auth/auth_controller.dart';
import 'package:billalert/presentation/common/profile_screen.dart';
import 'package:billalert/presentation/providers.dart';
import 'package:billalert/presentation/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';
import '../../support/fingerprint_fakes.dart';

/// The Profile screen's fingerprint sign-in switch — the only way to turn
/// the lock off once it is on.
void main() {
  const MeterReaderUser reader = MeterReaderUser(
    id: ProfileId('reader-1'),
    username: 'ledesman.dormal',
    firstName: 'Ledesman',
    lastName: 'Dormal',
    areaId: AreaId('area-3'),
    mustChangePassword: false,
  );

  Future<void> openProfile(
    WidgetTester tester, {
    required FakeDeviceUnlock phone,
    required FakeFingerprintSetting setting,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(
            () => FakeAuthController(signedInUser: reader),
          ),
          pendingOutboxProvider.overrideWith(
            (Ref ref) async => const <OutboxEntry>[],
          ),
          deviceUnlockProvider.overrideWithValue(phone),
          fingerprintSettingProvider.overrideWithValue(setting),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const ProfileScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Fingerprint sign-in'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('turning it on asks the phone before saving', (
    WidgetTester tester,
  ) async {
    final phone = FakeDeviceUnlock();
    final setting = FakeFingerprintSetting();
    await openProfile(tester, phone: phone, setting: setting);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(phone.prompts, 1);
    expect(setting.onFor, reader.id.value);
    expect(
      find.text('Fingerprint sign-in is on for this phone.'),
      findsOneWidget,
    );
  });

  testWidgets('turning it off asks too, and a cancelled prompt leaves it on', (
    WidgetTester tester,
  ) async {
    // Turning it off removes the lock. Whoever picks up an open phone must
    // not be able to do that without the phone's own confirmation.
    final phone = FakeDeviceUnlock(
      failure: const AuthFailure('Unlock was cancelled.'),
    );
    final setting = FakeFingerprintSetting(onFor: reader.id.value);
    await openProfile(tester, phone: phone, setting: setting);

    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(phone.prompts, 1);
    expect(setting.onFor, reader.id.value);
    expect(find.text('Unlock was cancelled.'), findsOneWidget);
  });

  testWidgets('a confirmed prompt turns it off', (WidgetTester tester) async {
    final phone = FakeDeviceUnlock();
    final setting = FakeFingerprintSetting(onFor: reader.id.value);
    await openProfile(tester, phone: phone, setting: setting);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(setting.onFor, isNull);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
  });

  testWidgets(
    'a phone with no screen lock shows the switch disabled, with the reason',
    (WidgetTester tester) async {
      await openProfile(
        tester,
        phone: FakeDeviceUnlock(available: false),
        setting: FakeFingerprintSetting(),
      );

      expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
      expect(
        find.text('This phone has no screen lock to unlock BillAlert with'),
        findsOneWidget,
      );
    },
  );
}
