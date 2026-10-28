import 'package:billalert/domain/entities/app_user.dart';
import 'package:billalert/domain/outbox/outbox_entry.dart';
import 'package:billalert/domain/value_objects/ids.dart';
import 'package:billalert/presentation/auth/auth_controller.dart';
import 'package:billalert/presentation/common/profile_screen.dart';
import 'package:billalert/presentation/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/fakes.dart';

void main() {
  const users = <AppUser>[
    AdminUser(
      id: ProfileId('president'),
      username: 'president',
      firstName: 'Current',
      lastName: 'President',
      areaId: AreaId('area'),
      mustChangePassword: false,
    ),
    ConsumerUser(
      id: ProfileId('nominee'),
      username: 'nominee',
      firstName: 'Incoming',
      lastName: 'President',
      historicalRole: 'admin',
      mustChangePassword: false,
    ),
    ConsumerUser(
      id: ProfileId('consumer'),
      username: 'consumer',
      firstName: 'Ordinary',
      lastName: 'Consumer',
      mustChangePassword: false,
    ),
  ];

  for (final user in users) {
    testWidgets('Profile account actions for ${user.username}', (tester) async {
      final router = GoRouter(
        initialLocation: '/profile',
        routes: [
          GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen()),
          GoRoute(
            path: '/account/transfer',
            builder: (_, _) => const Scaffold(body: Text('Transfer details')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            consumerRepositoryProvider.overrideWithValue(
              FakeConsumerRepository([]),
            ),
            authControllerProvider.overrideWith(
              () => FakeAuthController(signedInUser: user),
            ),
            pendingOutboxProvider.overrideWith(
              (ref) => Stream.value(const <OutboxEntry>[]),
            ),
            quarantinedOutboxProvider.overrideWith((ref) async => 0),
            profileConsumerProvider.overrideWith((ref) async => null),
            fingerprintStatusProvider.overrideWith(
              (ref) async => (available: false, on: false),
            ),
            urgentAlertsStatusProvider.overrideWith(
              (ref) async => (on: true, fillsScreen: false),
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Billing schedule'),
        user is AdminUser ? findsOneWidget : findsNothing,
      );
      expect(find.text('Manage accounts'), findsNothing);
      expect(find.text('Area President transfer'), findsNothing);

      if (user.username == 'nominee') {
        expect(find.text('My president transfer'), findsOneWidget);
        await tester.tap(find.text('My president transfer'));
        await tester.pumpAndSettle();
        expect(find.text('Transfer details'), findsOneWidget);
      } else {
        expect(find.text('My president transfer'), findsNothing);
      }
    });
  }
}
