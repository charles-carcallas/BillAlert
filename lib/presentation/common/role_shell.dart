import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/entities/app_user.dart';
import '../auth/auth_controller.dart';
import '../theme.dart';

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
      // Built directly rather than with NavigationBar. Material 3 draws its
      // selection indicator behind the ICON only and gives no way to extend
      // it around the label, so the selected tab read as a highlighted glyph
      // with some ordinary text underneath it.
      bottomNavigationBar: Material(
        color: AppTheme.surfaceWhite,
        child: SafeArea(
          top: false,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppTheme.outlineVariant)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: <Widget>[
                  for (int i = 0; i < tabs.length; i++)
                    Expanded(
                      child: RoleTab(
                        tab: tabs[i],
                        selected: i == selected,
                        onTap: () {
                          final String route = tabs[i].route;
                          // `go`, not `push`: tapping a tab replaces where
                          // you are rather than stacking another copy behind
                          // you. Otherwise the back button walks you through
                          // every tab you have ever tapped.
                          if (route != location) context.go(route);
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
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

/// One tab in the bottom bar.
///
/// The selected state is a filled shape around BOTH the icon and the label,
/// not a pill behind the glyph. That is the whole reason this exists instead
/// of a NavigationDestination.
///
/// Public because [RoleShell]'s tests assert on it: how many tabs a role
/// gets, and which one reports itself selected.
class RoleTab extends StatelessWidget {
  final AppTab tab;
  final bool selected;
  final VoidCallback onTap;

  const RoleTab({
    required this.tab,
    required this.selected,
    required this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme colours = Theme.of(context).colorScheme;
    final ({IconData outlined, IconData filled}) glyphs =
        RoleShell._glyphsFor(tab.icon);

    // Three signals, never colour alone: the filled shape, the brand colour,
    // and a filled glyph. A meter reader reads this at midday on a bright
    // screen, and colour blindness is not unusual.
    final Color foreground = selected ? colours.primary : AppTheme.textSecondary;

    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            color: selected
                ? colours.primary.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                selected ? glyphs.filled : glyphs.outlined,
                size: 22,
                color: foreground,
              ),
              const SizedBox(height: 4),
              Text(
                tab.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  height: 16 / 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: foreground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
