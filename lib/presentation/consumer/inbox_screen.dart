import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/repositories/notification_repository.dart';
import '../../domain/value_objects/ids.dart';
import '../common/failure_banner.dart';
import 'consumer_app_bar.dart';
import 'inbox_controller.dart';
import 'inbox_focus.dart';
import 'notification_details_sheet.dart';
import 'notification_labels.dart';
import 'phone_notifications_banner.dart';

/// CON-05 — Consumer › Inbox.
///
/// Every alert this household has been sent: the bill-ready notice when the
/// Admin posts an amount, reminders before a due date, overdue warnings and
/// disconnection notices. Tapping one opens it, with the bill or notice it is
/// about.
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

  /// Read while mounted, because Riverpod does not allow `ref` in dispose.
  late final InboxFocusController _focus = ref.read(
    inboxFocusProvider.notifier,
  );

  @override
  void initState() {
    super.initState();
    _focus;
  }

  @override
  void dispose() {
    // Leaving the Inbox ends the pointing. Deferred, because a provider may
    // not change while the widget tree is being torn down.
    final InboxFocusController focus = _focus;
    Future<void>.microtask(focus.clear);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(inboxControllerProvider);
    final controller = ref.read(inboxControllerProvider.notifier);
    final TextTheme text = Theme.of(context).textTheme;

    // Opened from a tapped phone notification: point at that notice, and say
    // plainly when it is not one of this household's. The list below comes
    // from this household's rows only, so absence from it is the check.
    final InboxFocus focus = ref.watch(inboxFocusProvider);
    final NotificationId? highlight = focus.highlight;
    final bool highlightMissing =
        highlight != null &&
        !state.isLoading &&
        state.failure == null &&
        !state.alerts.any(
          (AppNotification alert) => alert.id.value == highlight.value,
        );
    final String? focusMessage =
        focus.explanation ??
        (highlightMissing ? "That notification isn't on this account." : null);

    final List<AppNotification> visibleAlerts = state.alerts.where((alert) {
      // The notice a tapped notification points at stays in view whatever
      // the filter says.
      if (highlight != null && alert.id.value == highlight.value) return true;
      return switch (_filter) {
        _InboxFilter.all => true,
        _InboxFilter.unread => !alert.isRead,
        _InboxFilter.urgent => isUrgentNotification(alert.type),
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
              if (focusMessage != null) ...<Widget>[
                _FocusMessage(
                  message: focusMessage,
                  onDismiss: () =>
                      ref.read(inboxFocusProvider.notifier).clear(),
                ),
                const SizedBox(height: 14),
              ],
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
                    onTap: () => _open(alert),
                    highlighted:
                        highlight != null && alert.id.value == highlight.value,
                  ),
            ],
          ),
        ),
      ),
    );
  }

  /// Opening a notification is reading it, so an unread one is marked read
  /// as its details open. A read one still opens.
  void _open(AppNotification alert) {
    if (!alert.isRead) {
      unawaited(ref.read(inboxControllerProvider.notifier).markRead(alert));
    }
    unawaited(showNotificationDetails(context, alert: alert));
  }
}

/// Why a tapped notification landed here, or that its notice is not here.
class _FocusMessage extends StatelessWidget {
  final String message;
  final VoidCallback onDismiss;

  const _FocusMessage({required this.message, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final ColorScheme colours = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
      decoration: BoxDecoration(
        color: colours.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.info_outline, size: 20, color: colours.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message, style: Theme.of(context).textTheme.bodyMedium),
          ),
          IconButton(
            tooltip: 'Dismiss',
            onPressed: onDismiss,
            icon: const Icon(Icons.close, size: 18),
          ),
        ],
      ),
    );
  }
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

  /// Opens the notification's details.
  final VoidCallback onTap;

  /// The notice a tapped phone notification opened the Inbox at.
  final bool highlighted;

  const _AlertTile({
    required this.alert,
    required this.onTap,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colours = Theme.of(context).colorScheme;
    final bool disconnection = alert.type == 'disconnection';
    final bool overdue = alert.type == 'overdue';
    final String? urgency = notificationUrgency(alert.type);
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
      key: highlighted ? const ValueKey<String>('inbox-highlighted') : null,
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: background,
        border: Border.all(
          color: highlighted ? colours.primary : border,
          width: highlighted ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: InkWell(
        onTap: onTap,
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
                    child: Icon(
                      notificationIcon(alert.type),
                      size: 21,
                      color: accent,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        if (urgency != null) ...<Widget>[
                          Text(
                            urgency,
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
                                notificationTitle(alert.type),
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
                        // The whole message is one tap away, so the list
                        // keeps each alert to a readable preview.
                        Text(
                          alert.message,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
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
                    phDateTimeLabel(alert.createdAt),
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
                  const SizedBox(width: 6),
                  Icon(Icons.chevron_right, size: 18, color: secondary),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
