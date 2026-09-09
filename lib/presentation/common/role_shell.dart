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
          for (final AppTab tab in tabs) _destinationFor(tab),
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

  static NavigationDestination _destinationFor(AppTab tab) {
    final ({IconData outlined, IconData filled}) glyphs = _glyphsFor(tab.icon);

    return NavigationDestination(
      icon: Icon(glyphs.outlined),
      // The selected tab is drawn filled. Weight and colour already change
      // in the theme, but a filled glyph survives a bright screen outdoors
      // and colour blindness, and neither of those is unusual for a meter
      // reader holding this at midday.
      selectedIcon: Icon(glyphs.filled),
      label: tab.label,
    );
  }

  /// The pair of glyphs for a named slot: outlined when the tab is not the
  /// current one, filled when it is.
  ///
  /// Both come from one `switch` with no default, so a new [NavIcon] makes
  /// the compiler name this line — and there is no way to add the outlined
  /// glyph and forget the filled one.
  static ({IconData outlined, IconData filled}) _glyphsFor(NavIcon icon) =>
      switch (icon) {
        NavIcon.readings => (
            outlined: Icons.speed_outlined,
            filled: Icons.speed,
          ),
        NavIcon.consumers => (
            outlined: Icons.people_outline,
            filled: Icons.people,
          ),
        NavIcon.amounts => (
            outlined: Icons.request_quote_outlined,
            filled: Icons.request_quote,
          ),
        NavIcon.disconnections => (
            outlined: Icons.power_off_outlined,
            filled: Icons.power_off,
          ),
        NavIcon.accounts => (
            outlined: Icons.person_add_alt,
            filled: Icons.person_add,
          ),
        NavIcon.receipts => (
            outlined: Icons.receipt_long_outlined,
            filled: Icons.receipt_long,
          ),
        NavIcon.bill => (
            outlined: Icons.description_outlined,
            filled: Icons.description,
          ),
        NavIcon.history => (
            outlined: Icons.history_outlined,
            filled: Icons.history,
          ),
        NavIcon.inbox => (
            outlined: Icons.notifications_outlined,
            filled: Icons.notifications,
          ),
        NavIcon.profile => (
            outlined: Icons.person_outline,
            filled: Icons.person,
          ),
      };
}
