import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/auth_controller.dart';
import '../auth/linked_household_provider.dart';

/// Keeps the current identity while switching between work and household tabs.
class AccountViewMenu extends ConsumerWidget {
  const AccountViewMenu({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).value;
    if (user == null) return const SizedBox.shrink();
    final colours = Theme.of(context).colorScheme;
    final initials =
        '${user.firstName.isEmpty ? '' : user.firstName[0]}'
                '${user.lastName.isEmpty ? '' : user.lastName[0]}'
            .toUpperCase();
    final avatar = CircleAvatar(
      radius: 18,
      backgroundColor: colours.primary.withValues(alpha: 0.12),
      foregroundColor: colours.primary,
      child: Text(
        initials.isEmpty ? '?' : initials,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      ),
    );
    if (!user.hasWorkAccess) return avatar;
    final linked = ref.watch(linkedHouseholdProvider);
    if (linked.isLoading || linked.hasError || linked.value == null) {
      return avatar;
    }
    return PopupMenuButton<bool>(
      key: const ValueKey('account-view-menu'),
      tooltip: 'Switch Work or My household',
      position: PopupMenuPosition.under,
      offset: const Offset(0, 8),
      elevation: 8,
      color: colours.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      constraints: const BoxConstraints(minWidth: 280, maxWidth: 300),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: colours.outlineVariant),
      ),
      menuPadding: const EdgeInsets.all(8),
      onSelected: (household) {
        final current = ref.read(authControllerProvider).value;
        if (current == null ||
            !current.hasWorkAccess ||
            current.accessScope != user.accessScope) {
          return;
        }
        final currentLink = ref.read(linkedHouseholdProvider);
        if (household &&
            (currentLink.isLoading ||
                currentLink.hasError ||
                currentLink.value == null)) {
          return;
        }
        context.go(household ? '/consumer' : current.homeRoute);
      },
      itemBuilder: (context) {
        final location = GoRouterState.of(context).matchedLocation;
        final household =
            location == '/consumer' || location.startsWith('/consumer/');
        return [
          PopupMenuItem<bool>(
            enabled: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${user.firstName} ${user.lastName}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Choose a view',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colours.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          _viewItem(
            context,
            value: false,
            selected: !household,
            icon: Icons.work_outline,
            title: 'Work',
            subtitle: 'Your ${user.roleLabel.toLowerCase()} tasks',
          ),
          _viewItem(
            context,
            value: true,
            selected: household,
            icon: Icons.home_outlined,
            title: 'My household',
            subtitle: 'Your bills and payment history',
          ),
        ];
      },
      child: Padding(padding: const EdgeInsets.all(6), child: avatar),
    );
  }

  PopupMenuItem<bool> _viewItem(
    BuildContext context, {
    required bool value,
    required bool selected,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return PopupMenuItem<bool>(
      value: value,
      padding: EdgeInsets.zero,
      child: Semantics(
        selected: selected,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(
            color: selected ? colors.secondaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 22,
                color: selected
                    ? colors.onSecondaryContainer
                    : colors.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: selected
                            ? colors.onSecondaryContainer
                            : colors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: selected
                            ? colors.onSecondaryContainer
                            : colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (selected)
                Icon(
                  Icons.check_rounded,
                  size: 20,
                  color: colors.onSecondaryContainer,
                )
              else
                const SizedBox(width: 20),
            ],
          ),
        ),
      ),
    );
  }
}
