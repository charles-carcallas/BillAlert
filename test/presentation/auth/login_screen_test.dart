import 'dart:async';

import 'package:billalert/core/errors/app_failure.dart';
import 'package:billalert/presentation/auth/auth_controller.dart';
import 'package:billalert/presentation/auth/login_screen.dart';
import 'package:billalert/presentation/common/failure_banner.dart';
import 'package:billalert/presentation/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';

void main() {
  Widget buildTestableWidget({required FakeAuthController controller}) {
    return ProviderScope(
      overrides: [authControllerProvider.overrideWith(() => controller)],
      child: MaterialApp(theme: AppTheme.light(), home: const LoginScreen()),
    );
  }

  group('LoginScreen (R6 Widget Tests)', () {
    testWidgets('1. Both fields render', (WidgetTester tester) async {
      final fakeAuth = FakeAuthController();
      await tester.pumpWidget(buildTestableWidget(controller: fakeAuth));

      // Assert both username and password fields are present
      expect(find.byType(TextField), findsNWidgets(2));
      expect(find.text('Username'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
    });

    testWidgets('1b. The eye uncovers the password and names what it does', (
      WidgetTester tester,
    ) async {
      final fakeAuth = FakeAuthController();
      await tester.pumpWidget(buildTestableWidget(controller: fakeAuth));

      TextField passwordField() =>
          tester.widgetList<TextField>(find.byType(TextField)).elementAt(1);

      expect(passwordField().obscureText, isTrue);

      await tester.tap(find.byTooltip('Show password'));
      await tester.pumpAndSettle();
      expect(passwordField().obscureText, isFalse);

      // The tooltip now offers the opposite action, and is the only label a
      // screen reader has for this button.
      await tester.tap(find.byTooltip('Hide password'));
      await tester.pumpAndSettle();
      expect(passwordField().obscureText, isTrue);
    });

    testWidgets('2. Tapping "Sign in" calls signIn exactly once', (
      WidgetTester tester,
    ) async {
      final fakeAuth = FakeAuthController();
      await tester.pumpWidget(buildTestableWidget(controller: fakeAuth));

      final button = find.byType(FilledButton);
      expect(button, findsOneWidget);

      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(fakeAuth.signInCalls, equals(1));
    });

    testWidgets(
      '3. A double tap produces exactly ONE signIn call (the button should disable on _isSubmitting)',
      (WidgetTester tester) async {
        final pendingSignIn = Completer<void>();
        final fakeAuth = FakeAuthController(pendingSignIn: pendingSignIn);
        await tester.pumpWidget(buildTestableWidget(controller: fakeAuth));

        final button = find.byType(FilledButton);
        expect(button, findsOneWidget);

        // First tap begins submission
        await tester.tap(button);
        await tester.pump(); // Triggers setState(_isSubmitting = true)

        // Button is now disabled; second tap should do nothing
        await tester.tap(button, warnIfMissed: false);
        await tester.pump();

        // Complete the pending asynchronous sign in operation
        pendingSignIn.complete();
        await tester.pumpAndSettle();

        expect(fakeAuth.signInCalls, equals(1));
      },
    );

    testWidgets('4. A returned failure renders a FailureBanner', (
      WidgetTester tester,
    ) async {
      const failure = ValidationFailure('Invalid username or password');
      final fakeAuth = FakeAuthController(failureToReturn: failure);
      await tester.pumpWidget(buildTestableWidget(controller: fakeAuth));

      // Before submit, no FailureBanner is shown
      expect(find.byType(FailureBanner), findsNothing);

      final button = find.byType(FilledButton);
      await tester.tap(button);
      await tester.pumpAndSettle();

      // FailureBanner must now be rendered with the failure message
      expect(find.byType(FailureBanner), findsOneWidget);
      expect(find.text('Invalid username or password'), findsOneWidget);
    });
  });
}
