import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/app_user.dart';
import '../auth/auth_controller.dart';

/// The branded header shared by the Consumer's tab screens.
class ConsumerAppBar extends ConsumerWidget implements PreferredSizeWidget {
  final String title;

  const ConsumerAppBar({required this.title, super.key});

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
            'BILLALERT',
            style: TextStyle(
              color: colours.primary,
              fontSize: 10,
              height: 1.4,
              letterSpacing: 1.4,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(title),
        ],
      ),
      actions: <Widget>[
        if (user != null)
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: CircleAvatar(
              radius: 18,
              backgroundColor: colours.primary.withValues(alpha: 0.14),
              foregroundColor: colours.primary,
              child: Text(
                _initials(user),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    );
  }

  static String _initials(AppUser user) {
    final first = user.firstName.isEmpty ? '' : user.firstName[0];
    final last = user.lastName.isEmpty ? '' : user.lastName[0];
    final value = '$first$last'.toUpperCase();
    return value.isEmpty ? '?' : value;
  }
}
