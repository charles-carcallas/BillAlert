import 'package:billalert/core/errors/app_failure.dart';
import 'package:billalert/data/security/secure_password_verifier.dart';
import 'package:billalert/domain/entities/app_user.dart';
import 'package:billalert/domain/value_objects/ids.dart';
import 'package:billalert/presentation/auth/app_lock_controller.dart';
import 'package:billalert/presentation/auth/auth_controller.dart';
import 'package:billalert/presentation/auth/login_screen.dart';
import 'package:billalert/presentation/providers.dart';
import 'package:billalert/presentation/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';
import '../../support/fingerprint_fakes.dart';

/// Fingerprint sign-in is on, the app was closed, and it is reopened with no
/// signal. Choosing the password instead of the fingerprint must still get
/// the same person back in, without throwing away the session and the data
/// saved on the phone.
void main() {
  const MeterReaderUser reader = MeterReaderUser(
    id: ProfileId('reader-1'),
    username: 'ledesman.dormal',
    firstName: 'Ledesman',
    lastName: 'Dormal',
    areaId: AreaId('area-3'),
    mustChangePassword: false,
  );

  late FakeAuthRepository server;
  late FakePasswordVerifier verifier;

  setUp(() {
    server = FakeAuthRepository(user: reader);
    verifier = FakePasswordVerifier();
  });

  ProviderContainer locked() {
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(server),
        passwordVerifierProvider.overrideWithValue(verifier),
        appLockControllerProvider.overrideWith(LockedAppLockController.new),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('unlockWithPassword', () {
    test('with signal, the server checks it and the lock lifts', () async {
      final container = locked();

      final failure = await container
          .read(appLockControllerProvider.notifier)
          .unlockWithPassword(reader, 'correct-horse');

      expect(failure, isNull);
      expect(container.read(appLockControllerProvider).locked, isFalse);
      // And the phone can now check it offline next time.
      expect(verifier.accepted[reader.id.value], 'correct-horse');
    });

    test(
      'with no signal, the password the server last accepted works',
      () async {
        verifier.accepted[reader.id.value] = 'correct-horse';
        server.nextSignInFailure = const NetworkFailure();
        final container = locked();

        final failure = await container
            .read(appLockControllerProvider.notifier)
            .unlockWithPassword(reader, 'correct-horse');

        expect(failure, isNull);
        expect(container.read(appLockControllerProvider).locked, isFalse);
      },
    );

    test('with no signal, a wrong password is refused', () async {
      verifier.accepted[reader.id.value] = 'correct-horse';
      server.nextSignInFailure = const NetworkFailure();
      final container = locked();

      final failure = await container
          .read(appLockControllerProvider.notifier)
          .unlockWithPassword(reader, 'wrong');

      expect(failure, isA<AuthFailure>());
      expect(container.read(appLockControllerProvider).locked, isTrue);
    });

    test('with no signal, guessing stops after five tries', () async {
      verifier.accepted[reader.id.value] = 'correct-horse';
      server.nextSignInFailure = const NetworkFailure();
      final container = locked();
      final lock = container.read(appLockControllerProvider.notifier);

      for (int i = 0; i < AppLockController.maxOfflinePasswordTries; i++) {
        await lock.unlockWithPassword(reader, 'guess-$i');
      }
      final failure = await lock.unlockWithPassword(reader, 'correct-horse');

      expect(failure, isA<AuthFailure>());
      expect(failure!.message, contains('Too many tries'));
      expect(container.read(appLockControllerProvider).locked, isTrue);
    });

    test('with no signal and nothing saved, it says why', () async {
      server.nextSignInFailure = const NetworkFailure();
      final container = locked();

      final failure = await container
          .read(appLockControllerProvider.notifier)
          .unlockWithPassword(reader, 'correct-horse');

      expect(failure, isA<NetworkFailure>());
      expect(failure!.message, contains('fingerprint'));
      expect(container.read(appLockControllerProvider).locked, isTrue);
    });

    test('with signal, a wrong password is the server\'s answer', () async {
      server.nextSignInFailure = const AuthFailure();
      final container = locked();

      final failure = await container
          .read(appLockControllerProvider.notifier)
          .unlockWithPassword(reader, 'wrong');

      expect(failure, isA<AuthFailure>());
      expect(container.read(appLockControllerProvider).locked, isTrue);
    });
  });

  group('the lock screen', () {
    Widget screen(FakeAuthController auth) => ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(() => auth),
        appLockControllerProvider.overrideWith(LockedAppLockController.new),
        authRepositoryProvider.overrideWithValue(server),
        passwordVerifierProvider.overrideWithValue(verifier),
        deviceUnlockProvider.overrideWithValue(FakeDeviceUnlock()),
        fingerprintSettingProvider.overrideWithValue(
          FakeFingerprintSetting(onFor: reader.id.value),
        ),
      ],
      child: MaterialApp(theme: AppTheme.light(), home: const LoginScreen()),
    );

    testWidgets('"Use username and password" keeps the session and asks '
        'for the password', (WidgetTester tester) async {
      final auth = _RecordingAuthController(signedInUser: reader);
      await tester.pumpWidget(screen(auth));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Use username and password'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use username and password'));
      await tester.pumpAndSettle();

      expect(auth.signOutCalls, 0);
      expect(find.text('ledesman.dormal'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('unlock-password')),
        findsOneWidget,
      );
    });

    testWidgets('offline, the saved password opens the app', (
      WidgetTester tester,
    ) async {
      verifier.accepted[reader.id.value] = 'correct-horse';
      server.nextSignInFailure = const NetworkFailure();
      await tester.pumpWidget(screen(FakeAuthController(signedInUser: reader)));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Use username and password'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use username and password'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey<String>('unlock-password')),
        'correct-horse',
      );
      await tester.ensureVisible(find.text('Unlock'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(LoginScreen)),
      );
      expect(container.read(appLockControllerProvider).locked, isFalse);
    });

    testWidgets('"Sign in with a different account" still signs out', (
      WidgetTester tester,
    ) async {
      final auth = _RecordingAuthController(signedInUser: reader);
      await tester.pumpWidget(screen(auth));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Sign in with a different account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign in with a different account'));
      await tester.pumpAndSettle();

      expect(auth.signOutCalls, 1);
    });
  });

  test('the phone keeps a hash, and it checks the password correctly', () {
    // RFC 7914 §11 test vector for PBKDF2-HMAC-SHA256, one iteration.
    final List<int> key = SecurePasswordVerifier.pbkdf2Sha256(
      'passwd'.codeUnits,
      'salt'.codeUnits,
      1,
    );
    expect(
      key.take(8).map((int b) => b.toRadixString(16).padLeft(2, '0')).join(),
      '55ac046e56e3089f',
    );
  });
}

/// Records sign-outs instead of reaching Supabase.
class _RecordingAuthController extends FakeAuthController {
  int signOutCalls = 0;

  _RecordingAuthController({super.signedInUser});

  @override
  Future<AppFailure?> signOut() async {
    signOutCalls++;
    return null;
  }
}
