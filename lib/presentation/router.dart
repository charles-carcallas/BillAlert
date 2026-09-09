import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../domain/entities/app_user.dart';
import 'admin/disconnections_screen.dart';
import 'admin/post_bill_amount_screen.dart';
import 'admin/serve_notice_screen.dart';
import 'auth/auth_controller.dart';
import 'auth/change_password_screen.dart';
import 'auth/login_screen.dart';
import 'cashier/receipts_screen.dart';
import 'cashier/record_payment_screen.dart';
import 'common/profile_screen.dart';
import 'common/role_shell.dart';
import 'common/splash_screen.dart';
import 'common/unbuilt_tab.dart';
import 'consumer/current_bill_screen.dart';
import 'consumer/history_screen.dart';
import 'consumer/inbox_screen.dart';
import 'consumer/receipt_screen.dart';
import 'reader/consumers_screen.dart';
import 'reader/reading_entry_screen.dart';
import 'reader/roster_screen.dart';

class Routes {
  const Routes._();

  static const String splash = '/';
  static const String login = '/login';
  static const String changePassword = '/change-password';

  /// The VOLUNTARY change-password screen, reached from a Profile tab.
  ///
  /// A separate path from [changePassword] on purpose. The redirect below
  /// bounces a signed-in user off that one to their home route — which is
  /// exactly what carries somebody out after a forced change — so a
  /// deliberate visit could never land there. This path is not in that bounce
  /// list, so it can.
  static const String accountPassword = '/account/password';

  /// Serving a disconnection notice. Outside the tab shell, like the reading
  /// form: it is a task with a confirmation at the end, not somewhere to
  /// wander in and out of.
  static const String serveNotice = '/admin/disconnections/serve';

  /// One receipt, as the household's own copy. Keyed by receipt number rather
  /// than passed as an object, so it opens from a link and not only from a
  /// tap - and RLS still decides whether the number belongs to the caller.
  static const String consumerReceipt = '/consumer/receipt/:receiptNo';

  /// The same path with a number in it, so callers never rebuild the string.
  static String consumerReceiptFor(String receiptNo) =>
      '/consumer/receipt/$receiptNo';

  // Each role's section. The first entry of that role's `permittedTabs` is
  // this same path, which is what makes the correct tab light up on arrival.
  static const String reader = '/reader';
  static const String readingEntry = '/reader/entry/:consumerId';
  static const String admin = '/admin';
  static const String cashier = '/cashier';
  static const String consumer = '/consumer';
}

/// Routing, with the role decision made by the user object rather than here.
///
/// The redirect below never asks "is this an admin?". It asks the signed-in
/// [AppUser] for its `homeRoute`, and each subclass answers for itself. That
/// is the whole reason AppUser is a sealed class with four subclasses instead
/// of a role string: this switch would otherwise have to be repeated, and
/// kept in step, in every place that cares where somebody belongs.
///
/// The tab panels live inside a [ShellRoute], so the bottom bar is built once
/// and the panels swap underneath it. Anything that is a full task rather
/// than a tab - the reading entry form - sits outside that shell on purpose:
/// somebody halfway through recording a reading should not be offered four
/// tabs to wander off into.
final routerProvider = Provider<GoRouter>((Ref ref) {
  // go_router re-runs `redirect` when this notifier fires. Bumping it on
  // every auth change is what makes signing out move the app to the login
  // screen without any screen having to push a route itself.
  final refresh = ValueNotifier<int>(0);
  ref.listen(authControllerProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: refresh,
    routes: <RouteBase>[
      GoRoute(
        path: Routes.splash,
        builder: (_, _) => const SplashScreen(),
      ),
      GoRoute(
        path: Routes.login,
        builder: (_, _) => const LoginScreen(),
      ),
      GoRoute(
        path: Routes.changePassword,
        builder: (_, _) => const ChangePasswordScreen(),
      ),

      // Outside the shell: full-screen tasks, no bottom navigation.
      GoRoute(
        path: Routes.accountPassword,
        builder: (_, _) => const ChangePasswordScreen(),
      ),
      GoRoute(
        path: Routes.consumerReceipt,
        builder: (_, GoRouterState state) => ConsumerReceiptScreen(
          receiptNo: state.pathParameters['receiptNo']!,
        ),
      ),
      GoRoute(
        path: Routes.serveNotice,
        builder: (_, _) => const ServeNoticeScreen(),
      ),
      GoRoute(
        path: Routes.readingEntry,
        builder: (_, GoRouterState state) => ReadingEntryScreen(
          consumerId: state.pathParameters['consumerId']!,
        ),
      ),

      ShellRoute(
        builder: (_, _, Widget child) => RoleShell(child: child),
        routes: <RouteBase>[
          // ---- Meter Reader ------------------------------------------
          GoRoute(
            path: Routes.reader,
            builder: (_, _) => const RosterScreen(),
          ),
          GoRoute(
            path: '/reader/consumers',
            builder: (_, _) => const ReaderConsumersScreen(),
          ),
          GoRoute(
            path: '/reader/profile',
            builder: (_, _) => const ProfileScreen(),
          ),

          // ---- Admin (Area President) --------------------------------
          GoRoute(
            path: Routes.admin,
            builder: (_, _) => const PostBillAmountScreen(),
          ),
          GoRoute(
            path: '/admin/disconnections',
            builder: (_, _) => const DisconnectionsScreen(),
          ),
          GoRoute(
            path: '/admin/accounts',
            builder: (_, _) => const UnbuiltTab(
              title: 'Accounts',
              willShow: 'Creating a staff account or a new consumer for this '
                  'service area.',
              figmaNode: '70:1436 and 70:6009',
            ),
          ),
          GoRoute(
            path: '/admin/profile',
            builder: (_, _) => const ProfileScreen(),
          ),

          // ---- Cashier -----------------------------------------------
          // Consumers, the payment and the receipt are three steps of ONE
          // screen, because they are one task: find the household, take the
          // cash, hand over the receipt. CashierNav has no Payment tab.
          GoRoute(
            path: Routes.cashier,
            builder: (_, _) => const RecordPaymentScreen(),
          ),
          GoRoute(
            path: '/cashier/receipts',
            builder: (_, _) => const ReceiptsScreen(),
          ),
          GoRoute(
            path: '/cashier/profile',
            builder: (_, _) => const ProfileScreen(),
          ),

          // ---- Consumer ----------------------------------------------
          GoRoute(
            path: Routes.consumer,
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
        ],
      ),
    ],
    redirect: (BuildContext context, GoRouterState state) {
      final auth = ref.read(authControllerProvider);
      final location = state.matchedLocation;

      // Still restoring a saved session at startup: hold on the splash screen
      // rather than flashing the login form at somebody already signed in.
      //
      // `!auth.hasValue` is what limits this to startup. Without it, any
      // later loading state — a sign-in attempt, say — would bounce the user
      // to splash and back, rebuilding whatever screen they were on and
      // wiping its local state. That is a whole class of bug, not one:
      // whoever adds a loading state to AuthController next should not have
      // to discover it again.
      if (auth.isLoading && !auth.hasValue) {
        return location == Routes.splash ? null : Routes.splash;
      }

      final user = auth.value;

      if (user == null) {
        return location == Routes.login ? null : Routes.login;
      }

      // GEN-04: a temporary password locks the user to one screen. Not a
      // banner asking nicely — there is nowhere else to go.
      if (user.mustChangePassword) {
        return location == Routes.changePassword ? null : Routes.changePassword;
      }

      // Signed in, password fine, but sitting on a screen that is now behind
      // them. The user says where it belongs.
      if (location == Routes.login ||
          location == Routes.splash ||
          location == Routes.changePassword) {
        return user.homeRoute;
      }

      // GEN-08, courtesy layer: keep a role out of another role's section.
      // Row-Level Security is what actually stops them reading the data; this
      // just avoids an empty screen and a confusing error.
      if (!_mayVisit(user, location)) {
        return user.homeRoute;
      }

      return null;
    },
  );
});

/// True when [location] belongs to this user's own section of the app.
bool _mayVisit(AppUser user, String location) {
  const sections = <String>[
    Routes.reader,
    Routes.admin,
    Routes.cashier,
    Routes.consumer,
  ];

  for (final String section in sections) {
    if (location == section || location.startsWith('$section/')) {
      return user.homeRoute == section;
    }
  }
  // Anything outside the four role sections is not restricted here.
  return true;
}
