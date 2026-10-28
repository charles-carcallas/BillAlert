import 'package:billalert/presentation/admin/accounts_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  for (final width in [390.0, 1200.0]) {
    testWidgets('Accounts menu destinations work at width $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const destinations = {
        'Create account': '/admin/accounts/create',
        'Manage accounts': '/admin/accounts/manage',
        'Reset password': '/admin/accounts/reset',
        'Area President transfer': '/admin/accounts/transfer',
        'Account activity': '/admin/accounts/activity',
      };
      final router = GoRouter(
        initialLocation: '/admin/accounts',
        routes: [
          GoRoute(
            path: '/admin/accounts',
            builder: (_, _) => const AdminAccountsScreen(),
          ),
          for (final entry in destinations.entries)
            GoRoute(
              path: entry.value,
              builder: (_, _) => Scaffold(body: Text('Opened ${entry.key}')),
            ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(child: MaterialApp.router(routerConfig: router)),
      );
      await tester.pumpAndSettle();
      for (final entry in destinations.entries) {
        final target = find.text(entry.key);
        await tester.scrollUntilVisible(target, 180);
        await tester.tap(target);
        await tester.pumpAndSettle();
        expect(find.text('Opened ${entry.key}'), findsOneWidget);
        router.pop();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    });
  }
}
