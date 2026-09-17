import 'package:billalert/presentation/auth/auth_controller.dart';
import 'package:billalert/presentation/auth/login_screen.dart';
import 'package:billalert/presentation/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';

/// "Forgot password?" used to be a link with an empty handler — the kind of
/// dead control the Phase 2 rubric's "no dead-end screens" rules out.
void main() {
  Widget signIn() => ProviderScope(
    overrides: [authControllerProvider.overrideWith(FakeAuthController.new)],
    child: MaterialApp(theme: AppTheme.light(), home: const LoginScreen()),
  );

  testWidgets('"Forgot password?" explains how to get back in', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(signIn());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();

    expect(find.text('Forgot your password?'), findsOneWidget);
    expect(
      find.text('Ask your Area President for a temporary password'),
      findsOneWidget,
    );
    // Says why there is no reset email, instead of leaving people to wait
    // for one.
    expect(find.textContaining("can't email you a reset link"), findsOneWidget);
  });

  testWidgets('"Back to sign in" returns to the form', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(signIn());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Back to sign in'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Back to sign in'));
    await tester.pumpAndSettle();

    expect(find.text('Forgot your password?'), findsNothing);
    expect(find.byType(TextField), findsNWidgets(2));
  });

  testWidgets('the link is big enough to hit with a thumb', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(signIn());
    await tester.pumpAndSettle();

    final Size link = tester.getSize(
      find.ancestor(
        of: find.text('Forgot password?'),
        matching: find.byType(TextButton),
      ),
    );

    expect(link.height, greaterThanOrEqualTo(48));
  });
}
