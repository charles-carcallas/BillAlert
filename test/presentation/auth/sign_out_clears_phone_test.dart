import 'package:billalert/domain/entities/app_user.dart';
import 'package:billalert/domain/notifications/phone_alerts.dart';
import 'package:billalert/domain/value_objects/ids.dart';
import 'package:billalert/presentation/auth/auth_controller.dart';
import 'package:billalert/presentation/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';
import '../../support/fingerprint_fakes.dart';
import '../../support/phone_alert_fakes.dart';

/// GEN-06 on the notification tray.
///
/// Phones get shared and handed back. A household that signs out must not
/// leave reminders about its bills to go off in the next person's hand, nor a
/// background check still reading its notices.
void main() {
  test('signing out stops the background check and clears the tray', () async {
    final FakeBackgroundAlerts background = FakeBackgroundAlerts();
    final FakePhoneNotifier phone = FakePhoneNotifier();
    phone.scheduled[1] = ScheduledNotice(
      const PhoneNotice(
        id: 1,
        title: 'Bill due in 3 days',
        body: 'Your August 2026 bill is due on 28 September.',
        payload: 'bill:b-1',
      ),
      DateTime.utc(2026, 9, 25),
    );

    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(
          FakeAuthRepository(
            user: const ConsumerUser(
              id: ProfileId('consumer-profile-1'),
              username: 'virgilio.busalanan',
              firstName: 'Virgilio',
              lastName: 'Busalanan',
              mustChangePassword: false,
            ),
          ),
        ),
        syncServiceProvider.overrideWithValue(FakeSyncService()),
        deviceUnlockProvider.overrideWithValue(FakeDeviceUnlock()),
        fingerprintSettingProvider.overrideWithValue(FakeFingerprintSetting()),
        backgroundAlertsProvider.overrideWithValue(background),
        phoneNotifierProvider.overrideWithValue(phone),
      ],
    );
    addTearDown(container.dispose);

    await container.read(authControllerProvider.future);
    await container.read(authControllerProvider.notifier).signOut();

    expect(background.stops, 1);
    expect(phone.cancelAllCalls, 1);
    expect(phone.scheduled, isEmpty);
  });
}
