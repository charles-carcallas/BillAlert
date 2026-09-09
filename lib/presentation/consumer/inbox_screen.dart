import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/repositories/notification_repository.dart';
import '../../domain/value_objects/ph_date.dart';
import '../common/failure_banner.dart';
import 'inbox_controller.dart';

/// CON-05 — Consumer › Inbox.
///
/// Every alert this household has been sent: the bill-ready notice when the
/// Admin posts an amount, reminders before a due date, overdue warnings and
/// disconnection notices.
///
/// The app never writes one of these. They are queued server-side by the same
/// transaction that priced the bill or served the notice, which is why one
/// cannot be sent twice or go missing when the amount was saved.
class InboxScreen extends ConsumerWidget {
  const InboxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(inboxControllerProvider);
    final controller = ref.read(inboxControllerProvider.notifier);
    final TextTheme text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inbox'),
        actions: <Widget>[
          if (state.unreadCount > 0)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text('${state.unreadCount} unread', style: text.bodySmall),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: controller.load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: <Widget>[
              if (state.failure != null) ...<Widget>[
                FailureBanner(failure: state.failure!, onRetry: controller.load),
                const SizedBox(height: 12),
              ],

              if (state.isLoading && state.alerts.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (state.alerts.isEmpty && state.failure == null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 48),
                  child: Column(
                    children: <Widget>[
                      Icon(
                        Icons.notifications_none,
                        size: 40,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 12),
                      Text('No alerts yet.',
                          style: text.titleMedium, textAlign: TextAlign.center),
                      const SizedBox(height: 4),
                      Text(
                        'You will be told here as soon as your bill has an '
                        'amount.',
                        style: text.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              else
                for (final AppNotification alert in state.alerts)
                  _AlertTile(
                    alert: alert,
                    onTap: () => controller.markRead(alert),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AlertTile extends StatelessWidget {
  final AppNotification alert;
  final VoidCallback onTap;

  const _AlertTile({required this.alert, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colours = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: alert.isRead ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(_iconFor(alert.type), size: 20, color: colours.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            _titleFor(alert.type),
                            style: alert.isRead
                                ? text.titleSmall
                                : text.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                          ),
                        ),
                        if (!alert.isRead)
                          Container(
                            height: 8,
                            width: 8,
                            decoration: BoxDecoration(
                              color: colours.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(alert.message, style: text.bodyMedium),
                    const SizedBox(height: 6),
                    Text(
                      '${_when(alert.createdAt)} · ${alert.channel}',
                      style: text.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The server's `notification_type` enum, in words a household would use.
  static String _titleFor(String type) => switch (type) {
        'bill_ready' => 'Your bill is ready',
        'pre_due_reminder' => 'Due soon',
        'overdue' => 'Overdue',
        'disconnection' => 'Disconnection notice',
        _ => 'Notice',
      };

  static IconData _iconFor(String type) => switch (type) {
        'bill_ready' => Icons.description_outlined,
        'pre_due_reminder' => Icons.schedule_outlined,
        'overdue' => Icons.warning_amber_outlined,
        'disconnection' => Icons.power_off_outlined,
        _ => Icons.notifications_none,
      };

  /// The Philippine date it arrived. The instant is UTC, and an alert queued
  /// at 7am in Tubod is the previous day in UTC.
  static String _when(DateTime instant) {
    final PhDate day = PhDate.at(instant);
    final DateTime manila = instant.toUtc().add(PhDate.utcOffset);
    final int hour24 = manila.hour;
    final int hour = hour24 % 12 == 0 ? 12 : hour24 % 12;
    final String minute = manila.minute.toString().padLeft(2, '0');
    const List<String> months = <String>[
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${day.day} ${months[day.month - 1]} · '
        '$hour:$minute ${hour24 < 12 ? 'AM' : 'PM'}';
  }
}
