import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../domain/entities/app_user.dart';
import 'admin/admin_home_screen.dart';
import 'auth/auth_controller.dart';
import 'auth/change_password_screen.dart';
import 'auth/login_screen.dart';
import 'cashier/cashier_home_screen.dart';
import 'common/splash_screen.dart';
import 'consumer/consumer_home_screen.dart';
import 'reader/reading_entry_screen.dart';
import 'reader/roster_screen.dart';

class Routes {
  const Routes._();

  static const String splash = '/';
  static const String login = '/login';
  static const String changePassword = '/change-password';
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
      GoRoute(
        path: Routes.reader,
        builder: (_, _) => const RosterScreen(),
        routes: <RouteBase>[
          GoRoute(
            path: 'entry/:consumerId',
            builder: (_, GoRouterState state) => ReadingEntryScreen(
              consumerId: state.pathParameters['consumerId']!,
            ),
          ),
        ],
      ),
      GoRoute(
        path: Routes.admin,
        builder: (_, _) => const AdminHomeScreen(),
      ),
      GoRoute(
        path: Routes.cashier,
        builder: (_, _) => const CashierHomeScreen(),
      ),
      GoRoute(
        path: Routes.consumer,
        builder: (_, _) => const ConsumerHomeScreen(),
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
