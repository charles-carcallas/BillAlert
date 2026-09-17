import 'package:billalert/domain/entities/app_user.dart';
import 'package:billalert/domain/value_objects/ids.dart';
import 'package:billalert/presentation/auth/auth_controller.dart';
import 'package:billalert/presentation/auth/change_password_screen.dart';
import 'package:billalert/presentation/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';

/// A household signing in for the first time is pinned on this screen and has
/// to type a password it cannot see, twice, before anything will let it past.
/// Without the eye there is no way to find out which of the two boxes was
/// mistyped.
void main() {
  const ConsumerUser firstLogin = ConsumerUser(
    id: ProfileId('profile-elena'),
    username: 'elena.montano',
    firstName: 'Elena',
    lastName: 'Montano',
    mustChangePassword: true,
  );

  Widget screen() => ProviderScope(
    overrides: [
      authControllerProvider.overrideWith(
        () => FakeAuthController(signedInUser: firstLogin),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: const ChangePasswordScreen(),
    ),
  );

  bool obscuredAt(WidgetTester tester, int index) => tester
      .widgetList<TextField>(find.byType(TextField))
      .elementAt(index)
      .obscureText;

  testWidgets('both boxes start covered on a first login', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();

    expect(find.textContaining('Welcome, Elena'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
    expect(obscuredAt(tester, 0), isTrue);
    expect(obscuredAt(tester, 1), isTrue);
  });

  testWidgets('the eye uncovers one box and covers it again', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Show New password'));
    await tester.pumpAndSettle();
    expect(obscuredAt(tester, 0), isFalse);

    // The icon now offers the opposite action, which is how the household
    // knows what the next tap will do.
    expect(find.byTooltip('Hide New password'), findsOneWidget);

    await tester.tap(find.byTooltip('Hide New password'));
    await tester.pumpAndSettle();
    expect(obscuredAt(tester, 0), isTrue);
  });

  testWidgets('uncovering the password leaves the confirmation covered', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Show New password'));
    await tester.pumpAndSettle();

    // Two switches, not one: a confirmation you can read off the screen
    // above it is a copy, not a check.
    expect(obscuredAt(tester, 0), isFalse);
    expect(obscuredAt(tester, 1), isTrue);

    await tester.tap(find.byTooltip('Show Type it again'));
    await tester.pumpAndSettle();
    expect(obscuredAt(tester, 1), isFalse);
  });
}
