import 'package:billalert/domain/entities/app_user.dart';
import 'package:billalert/domain/value_objects/ids.dart';
import 'package:billalert/presentation/auth/app_lock_controller.dart';
import 'package:billalert/presentation/auth/auth_controller.dart';
import 'package:billalert/presentation/auth/login_screen.dart';
import 'package:billalert/presentation/providers.dart';
import 'package:billalert/presentation/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../support/fakes.dart';
import '../support/fingerprint_fakes.dart';

/// Every tab must lead somewhere, and every constant in [Routes] must name a
/// route that exists.
///
/// This exists because the failure it catches is invisible until somebody
/// taps: a tab whose route was never declared shows an empty screen with no
/// error, and `flutter analyze` is perfectly happy — the tab list and the
/// route table are two String literals that agree only by hand. On a demo
/// that is a dead tab in front of the instructor.
void main() {
  const AreaId area3 = AreaId('11111111-0000-0000-0000-00000000000a');

  const users = <AppUser>[
    AdminUser(
      id: ProfileId('admin-1'),
      username: 'mario.lofranco',
      firstName: 'Mario',
      lastName: 'Lofranco',
      areaId: area3,
      mustChangePassword: false,
    ),
    MeterReaderUser(
      id: ProfileId('reader-1'),
      username: 'ledesman.dormal',
      firstName: 'Ledesman',
      lastName: 'Dormal',
      areaId: area3,
      mustChangePassword: false,
    ),
    CashierUser(
      id: ProfileId('cashier-1'),
      username: 'mercedita.gales',
      firstName: 'Mercedita',
      lastName: 'Gales',
      areaId: area3,
      mustChangePassword: false,
    ),
    ConsumerUser(
      id: ProfileId('consumer-1'),
      username: 'lumayag',
      firstName: 'Teofila',
      lastName: 'Lumayag',
      mustChangePassword: false,
    ),
  ];

  /// Every path the router declares, including inside the [ShellRoute].
  ///
  /// Each route in this app is declared with its full path rather than a
  /// segment, so these are the strings a caller passes to `go` or `push`.
  Set<String> declaredPaths(List<RouteBase> routes) {
    final paths = <String>{};
    for (final RouteBase route in routes) {
      if (route is GoRoute) paths.add(route.path);
      paths.addAll(declaredPaths(route.routes));
    }
    return paths;
  }

  Set<String> pathsOfRealRouter() {
    final container = ProviderContainer(
      overrides: [
        // The router only asks the auth controller where the user belongs, so
        // a fake with nobody signed in is enough to build the route table.
        authControllerProvider.overrideWith(FakeAuthController.new),
      ],
    );
    addTearDown(container.dispose);
    return declaredPaths(container.read(routerProvider).configuration.routes);
  }

  test('every tab of every role leads to a declared route', () {
    final Set<String> paths = pathsOfRealRouter();

    for (final AppUser user in users) {
      expect(
        paths,
        contains(user.homeRoute),
        reason: '${user.roleLabel} is sent to ${user.homeRoute} after signing '
            'in, and nothing is declared there.',
      );

      for (final AppTab tab in user.permittedTabs) {
        expect(
          paths,
          contains(tab.route),
          reason: "The ${user.roleLabel}'s ${tab.label} tab points at "
              '${tab.route}, and nothing is declared there. The tab would be '
              'tappable and blank.',
        );
      }
    }
  });

  test('the full-screen tasks are declared too', () {
    final Set<String> paths = pathsOfRealRouter();

    // These are reached by `push` from a constant, never by typing, so a
    // rename in one place and not the other is silent until somebody taps.
    for (final String route in <String>[
      Routes.login,
      Routes.splash,
      Routes.changePassword,
      Routes.accountPassword,
      Routes.serveNotice,
      Routes.newConsumer,
      Routes.resetAccountPassword,
      Routes.householdLogin,
      Routes.noticeDocument,
      Routes.consumerReceipt,
      Routes.readingEntry,
    ]) {
      expect(paths, contains(route));
    }
  });

  test('a receipt path is built from the constant, not assembled by hand', () {
    expect(
      Routes.consumerReceiptFor('BIEC-2026-09-004471'),
      '/consumer/receipt/BIEC-2026-09-004471',
    );
    // And it matches the pattern the router declares.
    expect(Routes.consumerReceipt, '/consumer/receipt/:receiptNo');

    expect(
      Routes.noticeDocumentFor('fe59ec52-60de-4663-b301-01a7861ae213'),
      '/admin/notice/fe59ec52-60de-4663-b301-01a7861ae213',
    );
  });

  test('the notice document does not sit where "serve" could be read as an id',
      () {
    // /admin/disconnections/serve is a literal. Had the document been put at
    // /admin/disconnections/:noticeId, only go_router's declaration order
    // would stop "serve" matching as a notice id — and reordering routes is
    // exactly the kind of tidying that looks harmless.
    expect(Routes.noticeDocument.startsWith('/admin/disconnections/'), isFalse);
    expect(Routes.serveNotice, '/admin/disconnections/serve');
  });

  testWidgets('a locked session is held on the sign-in screen, not its home', (
    WidgetTester tester,
  ) async {
    // The meter reader's session is restored, and fingerprint sign-in is on.
    // Without this redirect the router would open their round — a household
    // list — for whoever happens to be holding the phone.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(
            () => FakeAuthController(signedInUser: users[1]),
          ),
          appLockControllerProvider.overrideWith(LockedAppLockController.new),
          deviceUnlockProvider.overrideWithValue(FakeDeviceUnlock()),
        ],
        child: Consumer(
          builder: (BuildContext context, WidgetRef ref, Widget? _) =>
              MaterialApp.router(routerConfig: ref.watch(routerProvider)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('Unlock with fingerprint'), findsOneWidget);

    final GoRouter router = ProviderScope.containerOf(
      tester.element(find.byType(LoginScreen)),
    ).read(routerProvider);
    expect(router.routerDelegate.currentConfiguration.uri.path, Routes.login);
  });
}
