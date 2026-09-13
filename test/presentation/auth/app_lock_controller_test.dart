import 'package:billalert/core/errors/app_failure.dart';
import 'package:billalert/domain/entities/app_user.dart';
import 'package:billalert/domain/value_objects/ids.dart';
import 'package:billalert/presentation/auth/app_lock_controller.dart';
import 'package:billalert/presentation/auth/auth_controller.dart';
import 'package:billalert/presentation/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';
import '../../support/fingerprint_fakes.dart';

/// When a signed-in session is held behind the phone's screen lock, and what
/// lets somebody through.
///
/// These rules decide whether the person holding a phone can see a household's
/// bills without proving who they are, so they are tested here rather than
/// discovered at a demo.
void main() {
  const MeterReaderUser reader = MeterReaderUser(
    id: ProfileId('reader-1'),
    username: 'ledesman.dormal',
    firstName: 'Ledesman',
    lastName: 'Dormal',
    areaId: AreaId('area-3'),
    mustChangePassword: false,
  );

  const CashierUser cashier = CashierUser(
    id: ProfileId('cashier-1'),
    username: 'mercedita.gales',
    firstName: 'Mercedita',
    lastName: 'Gales',
    areaId: AreaId('area-3'),
    mustChangePassword: false,
  );

  late FakeDeviceUnlock phone;
  late FakeFingerprintSetting setting;

  setUp(() {
    phone = FakeDeviceUnlock();
    setting = FakeFingerprintSetting();
  });

  ProviderContainer containerWith({FakeAuthRepository? auth}) {
    final container = ProviderContainer(
      overrides: [
        deviceUnlockProvider.overrideWithValue(phone),
        fingerprintSettingProvider.overrideWithValue(setting),
        syncServiceProvider.overrideWithValue(FakeSyncService()),
        if (auth != null) authRepositoryProvider.overrideWithValue(auth),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('a restored session', () {
    test('locks only for the person fingerprint sign-in is on for', () async {
      setting.onFor = reader.id.value;
      final container = containerWith();
      final lock = container.read(appLockControllerProvider.notifier);

      await lock.lockIfTurnedOnFor(cashier);
      expect(
        container.read(appLockControllerProvider).locked,
        isFalse,
        reason:
            'Two staff can share a phone. One person turning it on must not '
            'lock the other behind a prompt they never asked for.',
      );

      await lock.lockIfTurnedOnFor(reader);
      expect(container.read(appLockControllerProvider).locked, isTrue);
    });

    test('does not lock a phone that can no longer show the prompt', () async {
      setting.onFor = reader.id.value;
      phone.available = false;
      final container = containerWith();

      await container
          .read(appLockControllerProvider.notifier)
          .lockIfTurnedOnFor(reader);

      expect(container.read(appLockControllerProvider).locked, isFalse);
    });

    test('is already locked by the time the user is published', () async {
      // The router draws whatever the auth state says the moment it changes.
      // If the user arrived first and the lock a moment later, their home
      // screen would flash up before the lock covered it.
      setting.onFor = reader.id.value;
      final container = containerWith(auth: FakeAuthRepository(user: reader));

      final AppUser? restored = await container.read(
        authControllerProvider.future,
      );

      expect(restored, same(reader));
      expect(container.read(appLockControllerProvider).locked, isTrue);
    });
  });

  group('getting through the lock', () {
    test('the fingerprint lifts it only when the phone confirms', () async {
      setting.onFor = reader.id.value;
      final container = containerWith();
      final lock = container.read(appLockControllerProvider.notifier);
      await lock.lockIfTurnedOnFor(reader);

      phone.failure = const AuthFailure('Unlock was cancelled.');
      final AppFailure? cancelled = await lock.unlock();
      expect(cancelled?.message, 'Unlock was cancelled.');
      expect(container.read(appLockControllerProvider).locked, isTrue);

      phone.failure = null;
      expect(await lock.unlock(), isNull);
      expect(container.read(appLockControllerProvider).locked, isFalse);
      expect(phone.prompts, 2);
    });

    test('a password sign-in lifts it too', () async {
      setting.onFor = reader.id.value;
      final container = containerWith(auth: FakeAuthRepository(user: reader));
      await container.read(authControllerProvider.future);
      expect(container.read(appLockControllerProvider).locked, isTrue);

      final AppFailure? failure = await container
          .read(authControllerProvider.notifier)
          .signIn(username: 'ledesman.dormal', password: 'a real password');

      expect(failure, isNull);
      expect(container.read(appLockControllerProvider).locked, isFalse);
    });

    test('signing out leaves nothing locked behind', () async {
      setting.onFor = reader.id.value;
      final container = containerWith(auth: FakeAuthRepository(user: reader));
      await container.read(authControllerProvider.future);

      await container.read(authControllerProvider.notifier).signOut();

      expect(container.read(appLockControllerProvider).locked, isFalse);
      expect(
        setting.onFor,
        reader.id.value,
        reason:
            'Signing out ends the session, not the preference: the next '
            'password sign-in on this phone keeps using the fingerprint.',
      );
    });
  });

  group('the offer after a password sign-in', () {
    test('is made once, on a phone that can take a fingerprint', () async {
      final container = containerWith();
      final lock = container.read(appLockControllerProvider.notifier);

      await lock.afterPasswordSignIn(reader);
      expect(
        container.read(appLockControllerProvider).offerFingerprint,
        isTrue,
      );

      await lock.declineOffer(reader);
      expect(
        container.read(appLockControllerProvider).offerFingerprint,
        isFalse,
      );

      await lock.afterPasswordSignIn(reader);
      expect(
        container.read(appLockControllerProvider).offerFingerprint,
        isFalse,
        reason: '"Not now" must not become a question at every sign-in.',
      );
    });

    test('is not made on a phone with no screen lock at all', () async {
      phone.available = false;
      final container = containerWith();

      await container
          .read(appLockControllerProvider.notifier)
          .afterPasswordSignIn(reader);

      expect(
        container.read(appLockControllerProvider).offerFingerprint,
        isFalse,
      );
    });

    test(
      'turning it on confirms first, and saves nothing if that fails',
      () async {
        final container = containerWith();
        final lock = container.read(appLockControllerProvider.notifier);

        phone.failure = const AuthFailure('Unlock was cancelled.');
        expect(await lock.turnOnFor(reader), isNotNull);
        expect(setting.onFor, isNull);

        phone.failure = null;
        expect(await lock.turnOnFor(reader), isNull);
        expect(setting.onFor, reader.id.value);
        expect(setting.offeredTo, contains(reader.id.value));
      },
    );
  });
}
