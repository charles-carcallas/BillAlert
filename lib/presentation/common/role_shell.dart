import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/entities/app_user.dart';
import '../auth/auth_controller.dart';

/// The bottom navigation every signed-in role sits inside.
///
/// There is one of these, not four. It asks the signed-in [AppUser] for its
/// `permittedTabs` and builds the bar from the answer, so the Admin's four
/// tabs and the Meter Reader's three are the same widget with different data.
/// A `switch` on the role here would be a second copy of a decision the user
/// object already makes, and the two would drift.
///
/// The domain names its icons ([NavIcon]) but cannot draw them - `domain/`
/// imports nothing, Flutter included - so the mapping from name to glyph is
/// here, which is the only place that knows what a Material icon is.
class RoleShell extends ConsumerWidget {
  /// The tab panel go_router matched.
  final Widget child;

  const RoleShell({required this.child, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppUser? user = ref.watch(authControllerProvider).value;

    // Signed out. The router's redirect is already moving to the login
    // screen; showing a bar of tabs on the way out would only flicker.
    if (user == null) return child;

    final List<AppTab> tabs = user.permittedTabs;
    final String location = GoRouterState.of(context).matchedLocation;
    final int selected = _indexFor(tabs, location);

    return Scaffold(
      // Each panel brings its own Scaffold and AppBar, so this one supplies
      // only the bar along the bottom and the surface behind it.
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selected,
        onDestinationSelected: (int index) {
          final String route = tabs[index].route;
          // `go`, not `push`: tapping a tab replaces where you are rather
          // than stacking another copy of it behind you. Otherwise the back
          // button walks you through every tab you have ever tapped.
          if (route != location) context.go(route);
        },
        destinations: <NavigationDestination>[
          for (final AppTab tab in tabs)
            NavigationDestination(
              icon: Icon(_glyphFor(tab.icon)),
              label: tab.label,
            ),
        ],
      ),
    );
  }

  /// Which tab owns [location].
  ///
  /// Longest match wins, and that is the whole subtlety: every cashier route
  /// starts with `/cashier`, so a first-match search would light up the
  /// Consumers tab while the Payment screen is on show. `/cashier/payment`
  /// is a longer match than `/cashier`, so it takes it.
  static int _indexFor(List<AppTab> tabs, String location) {
    var best = 0;
    var bestLength = -1;

    for (var i = 0; i < tabs.length; i++) {
      final String route = tabs[i].route;
      final bool matches = location == route || location.startsWith('$route/');
      if (matches && route.length > bestLength) {
        best = i;
        bestLength = route.length;
      }
    }

    return best;
  }

  /// The glyph for a named slot. A `switch` with no default on purpose: add a
  /// [NavIcon] and the compiler names this line as the place to finish the job.
  static IconData _glyphFor(NavIcon icon) => switch (icon) {
        NavIcon.readings => Icons.speed_outlined,
        NavIcon.consumers => Icons.people_outline,
        NavIcon.amounts => Icons.request_quote_outlined,
        NavIcon.disconnections => Icons.power_off_outlined,
        NavIcon.accounts => Icons.person_add_alt_outlined,
        NavIcon.payment => Icons.payments_outlined,
        NavIcon.receipts => Icons.receipt_long_outlined,
        NavIcon.bill => Icons.description_outlined,
        NavIcon.history => Icons.history_outlined,
        NavIcon.inbox => Icons.notifications_outlined,
        NavIcon.profile => Icons.person_outline,
      };
}
