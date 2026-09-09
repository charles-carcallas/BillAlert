import 'package:billalert/domain/entities/app_user.dart';
import 'package:billalert/domain/value_objects/ids.dart';
import 'package:billalert/presentation/auth/auth_controller.dart';
import 'package:billalert/presentation/common/role_shell.dart';
import 'package:billalert/presentation/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/fakes.dart';

/// The shell is one widget for all four roles, driven entirely by the tabs
/// the signed-in user reports. These tests are what stops it quietly growing
/// a `switch` on the role.
void main() {
  const AreaId area3 = AreaId('11111111-0000-0000-0000-00000000000a');

  const cashier = CashierUser(
    id: ProfileId('cashier-1'),
    username: 'mercedita.gales',
    firstName: 'Mercedita',
    lastName: 'Gales',
    areaId: area3,
    mustChangePassword: false,
  );

  const reader = MeterReaderUser(
    id: ProfileId('reader-1'),
    username: 'ledesman.dormal',
    firstName: 'Ledesman',
    lastName: 'Dormal',
    areaId: area3,
    mustChangePassword: false,
  );

  /// A miniature router with the same shape as the real one: a ShellRoute
  /// wrapping one plain panel per tab of [user].
  Widget shellUnderTest({required AppUser user, required String at}) {
    final router = GoRouter(
      initialLocation: at,
      routes: <RouteBase>[
        ShellRoute(
          builder: (_, _, Widget child) => RoleShell(child: child),
          routes: <RouteBase>[
            for (final AppTab tab in user.permittedTabs)
              GoRoute(
                path: tab.route,
                builder: (_, _) => Scaffold(
                  body: Center(child: Text('panel:${tab.label}')),
                ),
              ),
          ],
        ),
      ],
    );

    return ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(
          () => FakeAuthController(signedInUser: user),
        ),
      ],
      child: MaterialApp.router(
        theme: AppTheme.light(),
        routerConfig: router,
      ),
    );
  }

  NavigationBar barOf(WidgetTester tester) =>
      tester.widget<NavigationBar>(find.byType(NavigationBar));

  // The pair below is the point of the whole class: the same widget, given
  // two different users, produces two different bars. Kept as two tests
  // rather than one, because swapping the router underneath a live tree
  // tests the harness rather than the shell.
  testWidgets('a cashier gets their three tabs', (WidgetTester tester) async {
    await tester.pumpWidget(shellUnderTest(user: cashier, at: '/cashier'));
    await tester.pumpAndSettle();

    // Three, matching CashierNav. Payment is not a tab: it is a step reached
    // from Consumers, so there is no way to tab away mid-payment.
    expect(barOf(tester).destinations.length, 3);
    for (final String label in <String>['Consumers', 'Receipts', 'Profile']) {
      expect(find.text(label), findsOneWidget, reason: 'missing tab $label');
    }
    expect(find.text('Payment'), findsNothing);
  });

  testWidgets('a meter reader gets their three, from the same widget',
      (WidgetTester tester) async {
    await tester.pumpWidget(shellUnderTest(user: reader, at: '/reader'));
    await tester.pumpAndSettle();

    expect(barOf(tester).destinations.length, 3);
    expect(find.text('Readings'), findsOneWidget);
    expect(find.text('Consumers'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
    // Nothing of the cashier's leaks in.
    expect(find.text('Receipts'), findsNothing);
  });

  testWidgets('the longest matching route wins, not the first',
      (WidgetTester tester) async {
    // Every cashier route begins with "/cashier", so a first-match search
    // would light up Consumers while the Payment screen is on show.
    await tester.pumpWidget(
      shellUnderTest(user: cashier, at: '/cashier/receipts'),
    );
    await tester.pumpAndSettle();

    expect(find.text('panel:Receipts'), findsOneWidget);
    expect(barOf(tester).selectedIndex, 1);
  });

  testWidgets('the home route selects the first tab', (WidgetTester tester) async {
    await tester.pumpWidget(shellUnderTest(user: cashier, at: '/cashier'));
    await tester.pumpAndSettle();

    expect(find.text('panel:Consumers'), findsOneWidget);
    expect(barOf(tester).selectedIndex, 0);
  });

  testWidgets('tapping a tab moves to it and moves the selection',
      (WidgetTester tester) async {
    await tester.pumpWidget(shellUnderTest(user: cashier, at: '/cashier'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();

    expect(find.text('panel:Profile'), findsOneWidget);
    expect(barOf(tester).selectedIndex, 2);
  });

  testWidgets('every tab a role offers can actually be reached',
      (WidgetTester tester) async {
    // A tab in the bar with no route behind it is a dead end, and the bar is
    // built from the same list the routes are - so this catches the two
    // drifting apart.
    for (final AppUser user in <AppUser>[cashier, reader]) {
      for (final AppTab tab in user.permittedTabs) {
        await tester.pumpWidget(shellUnderTest(user: user, at: tab.route));
        await tester.pumpAndSettle();

        expect(
          find.text('panel:${tab.label}'),
          findsOneWidget,
          reason: '${user.roleLabel} cannot reach ${tab.route}',
        );
      }
    }
  });
}
