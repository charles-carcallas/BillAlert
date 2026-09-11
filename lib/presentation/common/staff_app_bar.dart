import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/app_user.dart';
import '../auth/auth_controller.dart';

/// The branded header used by staff tab screens.
class StaffAppBar extends ConsumerWidget implements PreferredSizeWidget {
  final String title;

  const StaffAppBar({required this.title, super.key});

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppUser? user = ref.watch(authControllerProvider).value;
    final colours = Theme.of(context).colorScheme;

    return AppBar(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            'BILLALERT  ·  ${user?.roleLabel.toUpperCase() ?? 'STAFF'}',
            style: TextStyle(
              color: colours.primary,
              fontSize: 10,
              height: 1.4,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(title),
        ],
      ),
      actions: <Widget>[
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colours.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Text(
              _initials(user),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: colours.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }

  static String _initials(AppUser? user) {
    if (user == null) return '?';
    final String first = user.firstName.isEmpty ? '' : user.firstName[0];
    final String last = user.lastName.isEmpty ? '' : user.lastName[0];
    final String initials = '$first$last'.toUpperCase();
    return initials.isEmpty ? '?' : initials;
  }
}
