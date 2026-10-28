import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'inbox_controller.dart';

/// The household bell shared by the Bill header and household tab app bars.
class InboxButton extends ConsumerWidget {
  const InboxButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(
      inboxControllerProvider.select((state) => state.unreadCount),
    );
    return IconButton(
      tooltip: 'Open inbox',
      onPressed: () => context.go('/consumer/inbox'),
      icon: Badge(
        isLabelVisible: unread > 0,
        label: Text('$unread'),
        child: Icon(
          unread > 0 ? Icons.notifications : Icons.notifications_none_outlined,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
    );
  }
}
