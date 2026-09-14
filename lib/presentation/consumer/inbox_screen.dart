import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/repositories/notification_repository.dart';
import '../../domain/value_objects/ph_date.dart';
import '../common/failure_banner.dart';
import 'consumer_app_bar.dart';
import 'inbox_controller.dart';
import 'phone_notifications_banner.dart';

/// CON-05 — Consumer › Inbox.
///
/// Every alert this household has been sent: the bill-ready notice when the
/// Admin posts an amount, reminders before a due date, overdue warnings and
/// disconnection notices.
///
/// The app never writes one of these. They are queued server-side by the same
/// transaction that priced the bill or served the notice, which is why one
/// cannot be sent twice or go missing when the amount was saved.
enum _InboxFilter { all, unread, urgent }

class InboxScreen extends ConsumerStatefulWidget {
  const InboxScreen({super.key});

  @override
  ConsumerState<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends ConsumerState<InboxScreen> {
  _InboxFilter _filter = _InboxFilter.all;
  bool _markingAll = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(inboxControllerProvider);
    final controller = ref.read(inboxControllerProvider.notifier);
    final TextTheme text = Theme.of(context).textTheme;
    final List<AppNotification> visibleAlerts = state.alerts.where((alert) {
      return switch (_filter) {
        _InboxFilter.all => true,
        _InboxFilter.unread => !alert.isRead,
        _InboxFilter.urgent => _isUrgent(alert),
      };
    }).toList();

    return Scaffold(
      appBar: const ConsumerAppBar(title: 'Inbox'),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: controller.load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: <Widget>[
              const PhoneNotificationsBanner(),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: <Widget>[
                    _FilterChoice(
                      label: 'All notifications',
                      selected: _filter == _InboxFilter.all,
                      onSelected: () =>
                          setState(() => _filter = _InboxFilter.all),
                    ),
                    const SizedBox(width: 8),
                    _FilterChoice(
                      label: 'Unread (${state.unreadCount})',
                      selected: _filter == _InboxFilter.unread,
                      onSelected: () =>
                          setState(() => _filter = _InboxFilter.unread),
                    ),
                    const SizedBox(width: 8),
                    _FilterChoice(
                      label: 'Urgent action',
                      selected: _filter == _InboxFilter.urgent,
                      onSelected: () =>
                          setState(() => _filter = _InboxFilter.urgent),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: <InlineSpan>[
                          TextSpan(
                            text: '${state.unreadCount} unread',
                            style: text.bodySmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          TextSpan(
                            text: ' of ${state.alerts.length} notifications',
                            style: text.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (state.unreadCount > 0)
                    TextButton.icon(
                      onPressed: _markingAll
                          ? null
                          : () async {
                              setState(() => _markingAll = true);
                              await controller.markAllRead();
                              if (mounted) setState(() => _markingAll = false);
                            },
                      icon: _markingAll
                          ? const SizedBox.square(
                              dimension: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.done_all, size: 17),
                      label: const Text('Mark all read'),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (state.failure != null) ...<Widget>[
                FailureBanner(
                  failure: state.failure!,
                  onRetry: controller.load,
                ),
                const SizedBox(height: 12),
              ],

              if (state.isLoading && state.alerts.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (visibleAlerts.isEmpty && state.failure == null)
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
                      Text(
                        state.alerts.isEmpty
                            ? 'No alerts yet.'
                            : 'Nothing in this filter.',
                        style: text.titleMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        state.alerts.isEmpty
                            ? 'You will be told here as soon as your bill has '
                                  'an amount.'
                            : 'Choose another filter to see more notifications.',
                        style: text.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              else
                for (final AppNotification alert in visibleAlerts)
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

  static bool _isUrgent(AppNotification alert) =>
      alert.type == 'overdue' || alert.type == 'disconnection';
}

class _FilterChoice extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onSelected;

  const _FilterChoice({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      onSelected: (_) => onSelected(),
      visualDensity: VisualDensity.compact,
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
    final bool disconnection = alert.type == 'disconnection';
    final bool overdue = alert.type == 'overdue';
    final Color foreground = disconnection ? Colors.white : colours.onSurface;
    final Color secondary = disconnection
        ? Colors.white.withValues(alpha: 0.78)
        : colours.onSurfaceVariant;
    final Color background = disconnection
        ? const Color(0xFF7D2430)
        : overdue
        ? colours.errorContainer.withValues(alpha: 0.38)
        : colours.surfaceContainerLowest;
    final Color border = disconnection
        ? const Color(0xFF7D2430)
        : overdue
        ? colours.error.withValues(alpha: 0.30)
        : colours.outlineVariant;
    final Color accent = disconnection
        ? Colors.white
        : overdue
        ? colours.error
        : colours.primary;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: InkWell(
        onTap: alert.isRead ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: accent.withValues(
                        alpha: disconnection ? 0.18 : 0.10,
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(_iconFor(alert.type), size: 21, color: accent),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        if (disconnection || overdue) ...<Widget>[
                          Text(
                            disconnection
                                ? 'IMMEDIATE ACTION'
                                : 'ACTION NEEDED',
                            style: text.labelSmall?.copyWith(
                              color: accent,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 3),
                        ],
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                _titleFor(alert.type),
                                style: text.titleSmall?.copyWith(
                                  color: foreground,
                                  fontWeight: alert.isRead
                                      ? FontWeight.w600
                                      : FontWeight.w700,
                                ),
                              ),
                            ),
                            if (!alert.isRead)
                              Container(
                                height: 7,
                                width: 7,
                                decoration: BoxDecoration(
                                  color: accent,
                                  shape: BoxShape.circle,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          alert.message,
                          style: text.bodyMedium?.copyWith(color: secondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Divider(
                color: disconnection
                    ? Colors.white.withValues(alpha: 0.18)
                    : colours.outlineVariant,
              ),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  Text(
                    _when(alert.createdAt),
                    style: text.bodySmall?.copyWith(color: secondary),
                  ),
                  const Spacer(),
                  Icon(
                    alert.channel.toLowerCase() == 'sms'
                        ? Icons.sms_outlined
                        : Icons.notifications_none,
                    size: 14,
                    color: secondary,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    alert.channel.toUpperCase(),
                    style: text.bodySmall?.copyWith(
                      color: secondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
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
    'pre_due_reminder' => 'Payment reminder',
    'overdue' => 'Bill is overdue',
    'disconnection' => 'Disconnection notice served',
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
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${day.day} ${months[day.month - 1]} · '
        '$hour:$minute ${hour24 < 12 ? 'AM' : 'PM'}';
  }
}
