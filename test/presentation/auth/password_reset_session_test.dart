import 'package:billalert/core/errors/app_failure.dart';
import 'package:billalert/core/result/result.dart';
import 'package:billalert/domain/entities/app_user.dart';
import 'package:billalert/domain/value_objects/ids.dart';
import 'package:billalert/presentation/auth/auth_controller.dart';
import 'package:billalert/presentation/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';
import '../../support/fingerprint_fakes.dart';
import '../../support/phone_alert_fakes.dart';

/// Found on a phone: an Area President reset a household's password while it
/// was still signed in. The app opened the compulsory change-password screen,
/// and saving said "You have been signed out", but left the household on a
/// screen with no way out. Supabase Auth had ended the session; only the app
/// had not noticed.
void main() {
  const ConsumerUser elena = ConsumerUser(
    id: ProfileId('consumer-profile-elena'),
    username: 'elena.bongcaras',
    firstName: 'Elena',
    lastName: 'Bongcaras',
    mustChangePassword: true,
  );

  late FakeAuthRepository auth;
  late ProviderContainer container;

  setUp(() {
    auth = FakeAuthRepository(user: elena);
    container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        syncServiceProvider.overrideWithValue(FakeSyncService()),
        deviceUnlockProvider.overrideWithValue(FakeDeviceUnlock()),
        fingerprintSettingProvider.overrideWithValue(FakeFingerprintSetting()),
        backgroundAlertsProvider.overrideWithValue(FakeBackgroundAlerts()),
        phoneNotifierProvider.overrideWithValue(FakePhoneNotifier()),
      ],
    );
    addTearDown(container.dispose);
  });

  AppUser? signedIn() => container.read(authControllerProvider).value;
  String? notice() => container.read(signInNoticeProvider);

  group('changing the password', () {
    test('refused because the session ended: signs out and says why', () async {
      await container.read(authControllerProvider.future);
      auth.nextChangePasswordFailure = const AuthFailure(
        'You were signed out on this phone, usually because your password '
        'was reset. Please sign in again.',
      );

      final AppFailure? failure = await container
          .read(authControllerProvider.notifier)
          .changePassword(
            newPassword: 'ElenaNew2026',
            confirmPassword: 'ElenaNew2026',
          );

      expect(failure, isA<AuthFailure>());
      // Signed out, so the router takes the household to sign in instead of
      // leaving it on a screen it can neither finish nor leave.
      expect(signedIn(), isNull);
      expect(notice(), contains('temporary one from your Area President'));
    });

    test('refused for what was typed: stays signed in', () async {
      await container.read(authControllerProvider.future);
      auth.nextChangePasswordFailure = const ValidationFailure(
        'That password is too easy to guess. Please choose a longer one.',
      );

      await container
          .read(authControllerProvider.notifier)
          .changePassword(
            newPassword: 'ElenaNew2026',
            confirmPassword: 'ElenaNew2026',
          );

      expect(signedIn(), isNotNull);
      expect(notice(), isNull);
    });
  });

  group('checking the session when the app opens or comes back', () {
    test('the server says it ended: signs out and says why', () async {
      await container.read(authControllerProvider.future);
      auth.sessionCheck = const Err<void>(AuthFailure());

      await container.read(authControllerProvider.notifier).confirmSession();

      expect(signedIn(), isNull);
      expect(notice(), contains('password was reset'));
    });

    test('no signal: keeps working from the phone', () async {
      // The meter reader is out of signal for hours by design. Not being able
      // to ask is not a reason to sign anybody out.
      await container.read(authControllerProvider.future);
      auth.sessionCheck = const Err<void>(NetworkFailure());

      await container.read(authControllerProvider.notifier).confirmSession();

      expect(signedIn(), isNotNull);
      expect(notice(), isNull);
    });
  });

  group('who ended the session', () {
    test('the server, on its own: the sign-in screen says why', () async {
      await container.read(authControllerProvider.future);

      auth.endSessionFromServer();
      await Future<void>.delayed(Duration.zero);

      expect(signedIn(), isNull);
      expect(notice(), contains('password was reset'));
    });

    test('the person, from Profile: no explanation needed', () async {
      await container.read(authControllerProvider.future);

      await container.read(authControllerProvider.notifier).signOut();
      await Future<void>.delayed(Duration.zero);

      expect(signedIn(), isNull);
      expect(notice(), isNull);
    });
  });
}
