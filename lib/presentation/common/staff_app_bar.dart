import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/entities/app_user.dart';
import '../auth/auth_controller.dart';
import 'account_view_menu.dart';

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
        if (user != null)
          IconButton(
            tooltip: 'Staff notifications',
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () => context.push('${user.homeRoute}/alerts'),
          ),
        const Padding(
          padding: EdgeInsets.only(right: 16),
          child: AccountViewMenu(),
        ),
      ],
    );
  }
}
