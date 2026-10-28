import 'package:billalert/domain/entities/app_user.dart';
import 'package:billalert/domain/value_objects/ids.dart';
import 'package:billalert/presentation/admin/disconnections_screen.dart';
import 'package:billalert/presentation/auth/auth_controller.dart';
import 'package:billalert/presentation/auth/linked_household_provider.dart';
import 'package:billalert/presentation/common/profile_screen.dart';
import 'package:billalert/presentation/common/saved_list_time.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/fakes.dart';

void main() {
  for (final width in [320.0, 390.0, 1200.0]) {
    testWidgets('both notice shortcuts are accessible at width $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const admin = AdminUser(
        id: ProfileId('admin'),
        username: 'admin',
        firstName: 'Test',
        lastName: 'President',
        areaId: AreaId('area'),
        mustChangePassword: false,
      );
      final router = GoRouter(
        initialLocation: '/admin/disconnections',
        routes: [
          GoRoute(
            path: '/admin/disconnections',
            builder: (_, _) => const Scaffold(
              body: DisconnectionsScreen(),
              bottomNavigationBar: SizedBox(
                height: 80,
                child: Center(child: Text('Role navigation')),
              ),
            ),
          ),
          GoRoute(
            path: '/admin/disconnections/history',
            builder: (_, _) => const Scaffold(body: Text('History opened')),
          ),
          GoRoute(
            path: '/admin/overdue',
            builder: (_, _) => const Scaffold(body: Text('Approvals opened')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authControllerProvider.overrideWith(
              () => FakeAuthController(signedInUser: admin),
            ),
            linkedHouseholdProvider.overrideWith((ref) async => null),
            activeNoticesProvider.overrideWith((ref) async => []),
            pendingOutboxProvider.overrideWith((ref) => Stream.value([])),
            savedListTimeProvider.overrideWith(
              (ref, key) => Stream.value(null),
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      for (final entry in {
        'Overdue collection approvals': 'Approvals opened',
        'Closed notice history': 'History opened',
      }.entries) {
        final shortcut = find.text(entry.key);
        expect(shortcut.hitTestable(), findsOneWidget);
        await tester.tap(shortcut);
        await tester.pumpAndSettle();
        expect(find.text(entry.value), findsOneWidget);
        router.pop();
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
    });
  }
}
