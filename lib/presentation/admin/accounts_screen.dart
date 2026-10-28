import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../common/staff_app_bar.dart';
import '../router.dart';

/// A task menu; forms and account records open on their own screens.
class AdminAccountsScreen extends StatelessWidget {
  const AdminAccountsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: const StaffAppBar(title: 'Accounts'),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
              children: [
                Text(
                  'People & households',
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  'Add someone new, or look after the accounts in your area.',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 28),
                const _ActionGroup(
                  children: [
                    _AccountAction(
                      title: 'Create account',
                      description: 'Add a staff member or a consumer.',
                      icon: Icons.person_add_alt_1_outlined,
                      route: '/admin/accounts/create',
                      prominent: true,
                    ),
                    _AccountAction(
                      title: 'Manage accounts',
                      description:
                          'Assign staff, manage people and link households.',
                      icon: Icons.manage_accounts_outlined,
                      route: '/admin/accounts/manage',
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                Text('Account support', style: theme.textTheme.titleMedium),
                const SizedBox(height: 12),
                const _ActionGroup(
                  children: [
                    _AccountAction(
                      title: 'Reset password',
                      description: 'Help someone get back into their account.',
                      icon: Icons.lock_reset_outlined,
                      route: Routes.resetAccountPassword,
                    ),
                    _AccountAction(
                      title: 'Area President transfer',
                      description:
                          'Prepare and review a handover to your successor.',
                      icon: Icons.swap_horiz_rounded,
                      route: '/admin/accounts/transfer',
                    ),
                    _AccountAction(
                      title: 'Account activity',
                      description: 'Review recorded account changes.',
                      icon: Icons.history_rounded,
                      route: '/admin/accounts/activity',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionGroup extends StatelessWidget {
  const _ActionGroup({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth >= 640
          ? (constraints.maxWidth - 16) / 2
          : constraints.maxWidth;
      return Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          for (final child in children) SizedBox(width: width, child: child),
        ],
      );
    },
  );
}

class _AccountAction extends StatelessWidget {
  const _AccountAction({
    required this.title,
    required this.description,
    required this.icon,
    required this.route,
    this.prominent = false,
  });
  final String title;
  final String description;
  final IconData icon;
  final String route;
  final bool prominent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Material(
      color: prominent ? colors.primaryContainer : colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: prominent
              ? colors.primary.withValues(alpha: 0.3)
              : colors.outlineVariant,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(route),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: prominent
                      ? colors.onPrimaryContainer.withValues(alpha: 0.08)
                      : colors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  icon,
                  color: prominent ? colors.onPrimaryContainer : colors.primary,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: prominent
                            ? colors.onPrimaryContainer
                            : colors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      description,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: prominent
                            ? colors.onPrimaryContainer
                            : colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                color: prominent
                    ? colors.onPrimaryContainer
                    : colors.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
