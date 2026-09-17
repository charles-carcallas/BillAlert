import 'package:billalert/core/errors/app_failure.dart';
import 'package:billalert/domain/entities/app_user.dart';
import 'package:billalert/domain/value_objects/ids.dart';
import 'package:billalert/presentation/auth/app_lock_controller.dart';
import 'package:billalert/presentation/auth/auth_controller.dart';
import 'package:billalert/presentation/auth/login_screen.dart';
import 'package:billalert/presentation/common/failure_banner.dart';
import 'package:billalert/presentation/providers.dart';
import 'package:billalert/presentation/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';
import '../../support/fingerprint_fakes.dart';

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

/// The sign-in screen's second face: the lock over a restored session.
void main() {
  const MeterReaderUser reader = MeterReaderUser(
    id: ProfileId('reader-1'),
    username: 'ledesman.dormal',
    firstName: 'Ledesman',
    lastName: 'Dormal',
    areaId: AreaId('area-3'),
    mustChangePassword: false,
  );

  Widget screen({
    required FakeAuthController auth,
    required FakeDeviceUnlock phone,
    bool locked = true,
  }) => ProviderScope(
    overrides: [
      authControllerProvider.overrideWith(() => auth),
      if (locked)
        appLockControllerProvider.overrideWith(LockedAppLockController.new),
      deviceUnlockProvider.overrideWithValue(phone),
      fingerprintSettingProvider.overrideWithValue(
        FakeFingerprintSetting(onFor: reader.id.value),
      ),
    ],
    child: MaterialApp(theme: AppTheme.light(), home: const LoginScreen()),
  );

  testWidgets('a locked session greets the person and offers the fingerprint', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      screen(
        auth: FakeAuthController(signedInUser: reader),
        phone: FakeDeviceUnlock(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Welcome back, Ledesman'), findsOneWidget);
    expect(find.text('Unlock with fingerprint'), findsOneWidget);
    // No password form: the phone's lock is the way through, or a different
    // account.
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('a cancelled prompt says so, in plain words', (
    WidgetTester tester,
  ) async {
    const String cancelled =
        'Unlock was cancelled. Try again, or sign in with a different account.';
    final phone = FakeDeviceUnlock(failure: const AuthFailure(cancelled));

    await tester.pumpWidget(
      screen(
        auth: FakeAuthController(signedInUser: reader),
        phone: phone,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Unlock with fingerprint'));
    await tester.pumpAndSettle();

    expect(phone.prompts, 1);
    expect(find.byType(FailureBanner), findsOneWidget);
    expect(find.text(cancelled), findsOneWidget);
    // Still the lock, not the app behind it.
    expect(find.text('Welcome back, Ledesman'), findsOneWidget);
  });

  testWidgets('"Sign in with a different account" signs the session out', (
    WidgetTester tester,
  ) async {
    final auth = _RecordingAuthController(signedInUser: reader);

    await tester.pumpWidget(screen(auth: auth, phone: FakeDeviceUnlock()));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Sign in with a different account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign in with a different account'));
    await tester.pumpAndSettle();

    expect(auth.signOutCalls, 1);
  });

  testWidgets('signed out, there is no fingerprint button that does nothing', (
    WidgetTester tester,
  ) async {
    // The mockup's button sat on the signed-out form with nothing behind it.
    // With no session on the phone there is nothing for a fingerprint to
    // unlock, so it must not be offered there.
    await tester.pumpWidget(
      screen(
        auth: FakeAuthController(),
        phone: FakeDeviceUnlock(),
        locked: false,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Unlock with fingerprint'), findsNothing);
    expect(find.byType(TextField), findsNWidgets(2));
  });
}
