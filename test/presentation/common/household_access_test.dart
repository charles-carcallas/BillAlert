import 'dart:async';

import 'package:billalert/core/errors/app_failure.dart';
import 'package:billalert/core/result/result.dart';
import 'package:billalert/domain/entities/app_user.dart';
import 'package:billalert/domain/entities/consumer.dart' as domain;
import 'package:billalert/domain/repositories/consumer_repository.dart';
import 'package:billalert/domain/value_objects/ids.dart';
import 'package:billalert/presentation/auth/auth_controller.dart';
import 'package:billalert/presentation/auth/linked_household_provider.dart';
import 'package:billalert/presentation/common/account_view_menu.dart';
import 'package:billalert/presentation/providers.dart';
import 'package:billalert/presentation/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/fakes.dart';

class _ChangingAuth extends FakeAuthController {
  _ChangingAuth(AppUser user) : super(signedInUser: user);
  void replace(AppUser user) => state = AsyncData(user);
}

class _DelayedHouseholds implements ConsumerRepository {
  final replies = <Completer<Result<domain.Consumer?>>>[];
  @override
  Future<Result<domain.Consumer?>> signedInConsumer() {
    final reply = Completer<Result<domain.Consumer?>>();
    replies.add(reply);
    return reply.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const staff = <AppUser>[
    AdminUser(
      id: ProfileId('admin'),
      username: 'admin',
      firstName: 'Area',
      lastName: 'President',
      areaId: AreaId('area'),
      mustChangePassword: false,
    ),
    MeterReaderUser(
      id: ProfileId('reader'),
      username: 'reader',
      firstName: 'Meter',
      lastName: 'Reader',
      areaId: AreaId('area'),
      mustChangePassword: false,
    ),
    CashierUser(
      id: ProfileId('cashier'),
      username: 'cashier',
      firstName: 'Test',
      lastName: 'Cashier',
      areaId: AreaId('area'),
      mustChangePassword: false,
    ),
  ];
  const householdPaths = [
    '/consumer',
    '/consumer/history',
    '/consumer/inbox',
    '/consumer/profile',
    '/consumer/receipt/TEST-001',
  ];

  Future<ProviderContainer> mount(
    WidgetTester tester,
    AppUser user,
    ConsumerRepository households,
  ) async {
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(() => _ChangingAuth(user)),
        consumerRepositoryProvider.overrideWithValue(households),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authControllerProvider.future);
    final router = GoRouter(
      initialLocation: user.homeRoute,
      routes: [
        for (final path in ['/admin', '/reader', '/cashier'])
          GoRoute(
            path: path,
            builder: (_, _) =>
                const Scaffold(appBar: _Header(), body: Text('Work screen')),
          ),
        GoRoute(
          path: '/consumer',
          builder: (_, _) =>
              const Scaffold(appBar: _Header(), body: Text('Household screen')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  Future<String?> redirect(
    WidgetTester tester,
    ProviderContainer container,
    String path,
  ) {
    final router = container.read(routerProvider);
    final state = GoRouterState(
      router.configuration,
      uri: Uri.parse(path),
      matchedLocation: path,
      fullPath: path,
      pathParameters: const {},
      pageKey: ValueKey(path),
    );
    return Future.value(
      router.configuration.topRedirect(
        tester.element(find.byType(AccountViewMenu)),
        state,
      ),
    );
  }

  for (final user in staff) {
    testWidgets(
      '${user.roleCode} without a link has no household switch or routes',
      (tester) async {
        final container = await mount(tester, user, FakeConsumerRepository([]));
        expect(find.byKey(const ValueKey('account-view-menu')), findsNothing);
        for (final path in householdPaths) {
          expect(await redirect(tester, container, path), user.homeRoute);
        }
        expect(
          await redirect(tester, container, '${user.homeRoute}/profile'),
          isNull,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '${user.roleCode} with a linked household can switch and visit its routes',
      (tester) async {
        final container = await mount(
          tester,
          user,
          FakeConsumerRepository([])..me = household(),
        );
        for (final path in householdPaths) {
          expect(await redirect(tester, container, path), isNull);
        }
        await tester.tap(find.byKey(const ValueKey('account-view-menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('My household'));
        await tester.pumpAndSettle();
        expect(find.text('Household screen'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'failed verification leaves work accessible and household unavailable',
    (tester) async {
      final container = await mount(
        tester,
        staff[1],
        FakeConsumerRepository([])
          ..signedInFailure = const NetworkFailure('No saved household link.'),
      );
      expect(find.byKey(const ValueKey('account-view-menu')), findsNothing);
      expect(await redirect(tester, container, '/consumer'), '/reader');
      expect(await redirect(tester, container, '/reader'), isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a new identity cannot reuse the previous household while loading',
    (tester) async {
      final households = _DelayedHouseholds();
      final container = await mount(tester, staff[1], households);
      expect(find.byKey(const ValueKey('account-view-menu')), findsNothing);
      households.replies.single.complete(Ok(household()));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('account-view-menu')), findsOneWidget);
      (container.read(authControllerProvider.notifier) as _ChangingAuth)
          .replace(staff[2]);
      await tester.pumpAndSettle();
      expect(households.replies.length, 2);
      expect(find.byKey(const ValueKey('account-view-menu')), findsNothing);
      households.replies.last.complete(const Ok(null));
      await tester.pumpAndSettle();
      expect(
        await redirect(tester, container, '/consumer/history'),
        '/cashier',
      );
    },
  );

  testWidgets('a removed link blocks an already-open household menu', (
    tester,
  ) async {
    final households = FakeConsumerRepository([])..me = household();
    final container = await mount(tester, staff[1], households);
    await tester.tap(find.byKey(const ValueKey('account-view-menu')));
    await tester.pumpAndSettle();
    households.me = null;
    container.invalidate(linkedHouseholdProvider);
    await tester.pumpAndSettle();
    await tester.tap(find.text('My household'));
    await tester.pumpAndSettle();
    expect(find.text('Work screen'), findsOneWidget);
    expect(find.text('Household screen'), findsNothing);
    expect(await redirect(tester, container, '/consumer'), '/reader');
  });
}

class _Header extends StatelessWidget implements PreferredSizeWidget {
  const _Header();
  @override
  Size get preferredSize => const Size.fromHeight(56);
  @override
  Widget build(BuildContext context) =>
      AppBar(actions: const [AccountViewMenu()]);
}
