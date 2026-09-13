import 'package:billalert/core/errors/app_failure.dart';
import 'package:billalert/domain/entities/app_user.dart';
import 'package:billalert/domain/entities/managed_account.dart';
import 'package:billalert/domain/value_objects/ids.dart';
import 'package:billalert/presentation/admin/reset_password_screen.dart';
import 'package:billalert/presentation/auth/auth_controller.dart';
import 'package:billalert/presentation/providers.dart';
import 'package:billalert/presentation/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';

/// An Area President resetting a forgotten password — the other half of the
/// sign-in screen's "Forgot password?".
void main() {
  const AdminUser admin = AdminUser(
    id: ProfileId('admin-1'),
    username: 'mario.ombajin',
    firstName: 'Mario',
    lastName: 'Ombajin',
    areaId: AreaId('area-3'),
    mustChangePassword: false,
  );

  const ManagedAccount reader = ManagedAccount(
    id: ProfileId('reader-1'),
    firstName: 'Ledesman',
    lastName: 'Dormal',
    kind: ManagedAccountKind.meterReader,
    reference: 'ledesman.dormal',
  );

  const ManagedAccount household = ManagedAccount(
    id: ProfileId('consumer-1'),
    firstName: 'Virgilio',
    lastName: 'Busalanan',
    kind: ManagedAccountKind.consumer,
    reference: '2019-0917-TUB',
  );

  late FakeAuthRepository auth;

  setUp(() {
    auth = FakeAuthRepository()..managed = <ManagedAccount>[reader, household];
  });

  Future<void> open(WidgetTester tester, {AppUser signedIn = admin}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(
            () => FakeAuthController(signedInUser: signedIn),
          ),
          authRepositoryProvider.overrideWithValue(auth),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const AdminResetPasswordScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> fillAndSubmit(
    WidgetTester tester, {
    required String password,
    String? confirm,
  }) async {
    await tester.enterText(find.byType(TextField).at(0), password);
    await tester.enterText(find.byType(TextField).at(1), confirm ?? password);
    final Finder button = find.widgetWithText(FilledButton, 'Reset password');
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  testWidgets('lists staff and households, and search narrows it', (
    WidgetTester tester,
  ) async {
    await open(tester);

    expect(find.text('Ledesman Dormal'), findsOneWidget);
    expect(find.text('Virgilio Busalanan'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '2019-0917');
    await tester.pumpAndSettle();

    expect(find.text('Virgilio Busalanan'), findsOneWidget);
    expect(find.text('Ledesman Dormal'), findsNothing);
  });

  testWidgets(
    'a confirmed reset sets the temporary password for that account',
    (WidgetTester tester) async {
      await open(tester);

      await tester.tap(find.text('Ledesman Dormal'));
      await tester.pumpAndSettle();
      expect(find.text('Set a temporary password'), findsOneWidget);

      await fillAndSubmit(tester, password: 'Temporary-2026');

      // The final confirmation, because the current password stops working.
      expect(find.text('Reset this password?'), findsOneWidget);
      expect(auth.resetCalls, 0);

      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Reset password'),
        ),
      );
      await tester.pumpAndSettle();

      expect(auth.resetCalls, 1);
      expect(auth.resetAccount?.id.value, 'reader-1');
      expect(auth.resetTemporaryPassword, 'Temporary-2026');
      expect(
        find.text('Temporary password set for Ledesman Dormal'),
        findsOneWidget,
      );
    },
  );

  testWidgets('choosing "Review" in the confirmation resets nothing', (
    WidgetTester tester,
  ) async {
    await open(tester);
    await tester.tap(find.text('Ledesman Dormal'));
    await tester.pumpAndSettle();

    await fillAndSubmit(tester, password: 'Temporary-2026');
    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();

    expect(auth.resetCalls, 0);
    expect(find.text('Set a temporary password'), findsOneWidget);
  });

  testWidgets('a short password is refused before any confirmation', (
    WidgetTester tester,
  ) async {
    await open(tester);
    await tester.tap(find.text('Ledesman Dormal'));
    await tester.pumpAndSettle();

    await fillAndSubmit(tester, password: 'short');

    expect(find.text('Reset this password?'), findsNothing);
    expect(
      find.text('The temporary password must be at least 8 characters.'),
      findsOneWidget,
    );
    expect(auth.resetCalls, 0);
  });

  testWidgets("the server's refusal is shown, and the form stays", (
    WidgetTester tester,
  ) async {
    auth.nextResetFailure = const PermissionFailure(
      'That account is not in your service area.',
    );
    await open(tester);
    await tester.tap(find.text('Virgilio Busalanan'));
    await tester.pumpAndSettle();

    await fillAndSubmit(tester, password: 'Temporary-2026');
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Reset password'),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('That account is not in your service area.'),
      findsOneWidget,
    );
    expect(find.text('Set a temporary password'), findsOneWidget);
  });

  testWidgets('anyone but an Area President is told why, not shown a list', (
    WidgetTester tester,
  ) async {
    await open(
      tester,
      signedIn: const MeterReaderUser(
        id: ProfileId('reader-1'),
        username: 'ledesman.dormal',
        firstName: 'Ledesman',
        lastName: 'Dormal',
        areaId: AreaId('area-3'),
        mustChangePassword: false,
      ),
    );

    expect(
      find.text(
        'Only an Area President can reset a password in their service area.',
      ),
      findsOneWidget,
    );
    expect(find.text('Virgilio Busalanan'), findsNothing);
  });
}
