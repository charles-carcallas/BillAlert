import 'package:billalert/domain/entities/app_user.dart';
import 'package:billalert/domain/entities/area_roster.dart';
import 'package:billalert/domain/value_objects/cycle_label.dart';
import 'package:billalert/domain/value_objects/ids.dart';
import 'package:billalert/domain/value_objects/ph_date.dart';
import 'package:billalert/presentation/auth/auth_controller.dart';
import 'package:billalert/presentation/common/account_view_menu.dart';
import 'package:billalert/presentation/common/staff_alerts.dart';
import 'package:billalert/presentation/providers.dart';
import 'package:billalert/presentation/reader/consumers_screen.dart';
import 'package:billalert/presentation/reader/remittance_screen.dart';
import 'package:billalert/presentation/reader/roster_controller.dart';
import 'package:billalert/presentation/reader/roster_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/fakes.dart';

class _Roster extends RosterController {
  @override
  Future<RosterView> build() async => const RosterView(
    roster: AreaRoster(
      areaId: AreaId('area'),
      cycle: CycleLabel(2026, 10),
      entries: [],
    ),
  );
}

void main() {
  const reader = MeterReaderUser(
    id: ProfileId('reader'),
    username: 'reader',
    firstName: 'Meter',
    lastName: 'Reader',
    areaId: AreaId('area'),
    mustChangePassword: false,
  );

  for (final path in ['/reader', '/reader/consumers', '/reader/remittance']) {
    testWidgets('reader opens staff alerts and switches household from $path', (
      tester,
    ) async {
      final router = GoRouter(
        initialLocation: path,
        routes: [
          GoRoute(path: '/reader', builder: (_, _) => const RosterScreen()),
          GoRoute(
            path: '/reader/consumers',
            builder: (_, _) => const ReaderConsumersScreen(),
          ),
          GoRoute(
            path: '/reader/remittance',
            builder: (_, _) => const RemittanceScreen(),
          ),
          GoRoute(
            path: '/reader/alerts',
            builder: (_, _) => const StaffAlertsScreen(),
          ),
          GoRoute(
            path: '/consumer',
            builder: (_, _) => Scaffold(
              appBar: AppBar(actions: const [AccountViewMenu()]),
              body: const Text('Own household'),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authControllerProvider.overrideWith(
              () => FakeAuthController(signedInUser: reader),
            ),
            consumerRepositoryProvider.overrideWithValue(
              FakeConsumerRepository([])
                ..me = household(id: 'reader-home', areaId: 'area'),
            ),
            rosterControllerProvider.overrideWith(_Roster.new),
            staffAlertsProvider.overrideWith((ref) async => []),
            readerHouseholdsProvider.overrideWith((ref) async => []),
            monthCollectionsProvider.overrideWith((ref, month) async => []),
            monthCollectionsSavedAtProvider.overrideWith(
              (ref, month) async => null,
            ),
            monthUnpaidProvider.overrideWith(
              (ref, month) async => MonthUnpaid.none,
            ),
            phClockProvider.overrideWithValue(
              FixedPhClock.onPhDate(const PhDate(2026, 10, 2)),
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      final menu = find.byKey(const ValueKey('account-view-menu'));
      expect(menu, findsOneWidget);
      if (path == '/reader') {
        expect(find.text('View reading sheet'), findsOneWidget);
      }
      expect(find.byTooltip('Open inbox'), findsNothing);
      await tester.tap(find.byTooltip('Staff notifications'));
      await tester.pumpAndSettle();
      expect(find.byType(StaffAlertsScreen), findsOneWidget);
      expect(
        GoRouterState.of(
          tester.element(find.byType(StaffAlertsScreen)),
        ).uri.path,
        '/reader/alerts',
      );
      router.pop();
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, path);
      await tester.tap(menu);
      await tester.pumpAndSettle();
      await tester.tap(find.text('My household'));
      await tester.pumpAndSettle();
      expect(find.text('Own household'), findsOneWidget);
      await tester.tap(menu);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Work'));
      await tester.pumpAndSettle();
      expect(find.byType(RosterScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final role in ['consumer', 'meter_reader', 'admin']) {
    testWidgets('household-only account with history $role has no switch', (
      tester,
    ) async {
      final user = ConsumerUser(
        id: const ProfileId('household-only'),
        username: 'household-only',
        firstName: 'Household',
        lastName: 'Only',
        mustChangePassword: false,
        historicalRole: role,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authControllerProvider.overrideWith(
              () => FakeAuthController(signedInUser: user),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(appBar: AppBar(actions: const [AccountViewMenu()])),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('account-view-menu')), findsNothing);
      await tester.tap(find.byType(CircleAvatar));
      await tester.pumpAndSettle();
      expect(find.text('Work'), findsNothing);
      expect(find.text('My household'), findsNothing);
    });
  }
}
