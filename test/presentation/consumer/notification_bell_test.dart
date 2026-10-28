import 'package:billalert/domain/entities/app_user.dart';
import 'package:billalert/domain/notifications/phone_alerts.dart';
import 'package:billalert/domain/outbox/outbox_entry.dart';
import 'package:billalert/domain/repositories/notification_repository.dart';
import 'package:billalert/domain/value_objects/ids.dart';
import 'package:billalert/domain/value_objects/ph_date.dart';
import 'package:billalert/presentation/auth/auth_controller.dart';
import 'package:billalert/presentation/common/profile_screen.dart';
import 'package:billalert/presentation/consumer/current_bill_controller.dart';
import 'package:billalert/presentation/consumer/current_bill_screen.dart';
import 'package:billalert/presentation/consumer/history_controller.dart';
import 'package:billalert/presentation/consumer/history_screen.dart';
import 'package:billalert/presentation/consumer/inbox_controller.dart';
import 'package:billalert/presentation/consumer/inbox_screen.dart';
import 'package:billalert/presentation/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/fakes.dart';

class _Inbox extends InboxController {
  @override
  InboxState build() => InboxState(
    alerts: [
      AppNotification(
        id: const NotificationId('unread'),
        type: 'bill_ready',
        channel: 'push',
        message: 'Your bill is ready.',
        isRead: false,
        createdAt: DateTime.utc(2026, 10, 2),
      ),
    ],
  );
}

class _CurrentBill extends CurrentBillController {
  @override
  CurrentBillState build() => const CurrentBillState();
}

class _History extends HistoryController {
  @override
  HistoryState build() => const HistoryState();
}

class _Permission implements NotificationPermission {
  @override
  Future<bool> isGranted() async => true;
  @override
  Future<bool> request() async => true;
  @override
  Future<void> openSettings() async {}
}

void main() {
  const admin = AdminUser(
    id: ProfileId('admin'),
    username: 'admin',
    firstName: 'Area',
    lastName: 'President',
    areaId: AreaId('area'),
    mustChangePassword: false,
  );
  const consumer = ConsumerUser(
    id: ProfileId('consumer'),
    username: 'consumer',
    firstName: 'Household',
    lastName: 'Owner',
    mustChangePassword: false,
  );
  const reader = MeterReaderUser(
    id: ProfileId('reader'),
    username: 'reader',
    firstName: 'Meter',
    lastName: 'Reader',
    areaId: AreaId('area'),
    mustChangePassword: false,
  );

  Future<void> open(WidgetTester tester, AppUser user, String path) async {
    final router = GoRouter(
      initialLocation: path,
      routes: [
        GoRoute(
          path: '/consumer',
          builder: (_, _) => const CurrentBillScreen(),
        ),
        GoRoute(
          path: '/consumer/history',
          builder: (_, _) => const HistoryScreen(),
        ),
        GoRoute(
          path: '/consumer/inbox',
          builder: (_, _) => const InboxScreen(),
        ),
        GoRoute(
          path: '/consumer/profile',
          builder: (_, _) => const ProfileScreen(),
        ),
        GoRoute(
          path: '/admin/profile',
          builder: (_, _) => const ProfileScreen(),
        ),
        GoRoute(
          path: '/admin/alerts',
          builder: (_, _) => const Scaffold(body: Text('Work notifications')),
        ),
        GoRoute(
          path: '/reader/profile',
          builder: (_, _) => const ProfileScreen(),
        ),
        GoRoute(
          path: '/reader/alerts',
          builder: (_, _) => const Scaffold(body: Text('Work notifications')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(
            () => FakeAuthController(signedInUser: user),
          ),
          inboxControllerProvider.overrideWith(_Inbox.new),
          currentBillControllerProvider.overrideWith(_CurrentBill.new),
          historyControllerProvider.overrideWith(_History.new),
          notificationPermissionProvider.overrideWithValue(_Permission()),
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
          phClockProvider.overrideWithValue(
            FixedPhClock.onPhDate(const PhDate(2026, 10, 2)),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final user in [admin, consumer]) {
    for (final path in [
      '/consumer',
      '/consumer/history',
      '/consumer/inbox',
      '/consumer/profile',
    ]) {
      testWidgets('${user.roleCode} household bell opens Inbox from $path', (
        tester,
      ) async {
        await open(tester, user, path);
        final bell = find.byTooltip('Open inbox');
        expect(bell, findsOneWidget);
        expect(find.byTooltip('Staff notifications'), findsNothing);
        final badge = tester.widget<Badge>(
          find.descendant(of: bell, matching: find.byType(Badge)),
        );
        expect(badge.isLabelVisible, isTrue);
        expect((badge.label! as Text).data, '1');
        await tester.tap(bell);
        await tester.pumpAndSettle();
        expect(find.byType(InboxScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final user in [admin, reader]) {
    testWidgets('${user.roleCode} Work Profile bell opens work notifications', (
      tester,
    ) async {
      await open(tester, user, '${user.homeRoute}/profile');
      expect(find.byTooltip('Open inbox'), findsNothing);
      await tester.tap(find.byTooltip('Staff notifications'));
      await tester.pumpAndSettle();
      expect(find.text('Work notifications'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
