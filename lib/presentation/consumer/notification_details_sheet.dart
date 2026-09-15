import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/bill.dart';
import '../../domain/repositories/notice_repository.dart';
import '../../domain/repositories/notification_repository.dart';
import '../../domain/usecases/consumer/load_notification_details.dart';
import '../../domain/value_objects/ph_date.dart';
import '../providers.dart';
import 'bill_details_sheet.dart';
import 'notification_details_controller.dart';
import 'notification_labels.dart';

/// Opens one Inbox notification.
Future<void> showNotificationDetails(
  BuildContext context, {
  required AppNotification alert,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => NotificationDetailsSheet(alert: alert),
);

/// CON-05 — one notification, opened.
///
/// The list says what arrived. This says what it is about: the whole
/// message, when it came and whether it reached the phone or the mobile
/// number, and the bill or disconnection notice behind it. Every fact is one
/// the server recorded or computed; nothing here is worked out on the phone.
class NotificationDetailsSheet extends ConsumerWidget {
  final AppNotification alert;

  const NotificationDetailsSheet({required this.alert, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TextTheme text = Theme.of(context).textTheme;
    final PhDate today = ref.watch(phClockProvider).today();
    final bool hasRelated = alert.billId != null || alert.noticeId != null;
    final AsyncValue<NotificationDetails> details = ref.watch(
      notificationDetailsProvider(alert),
    );

    return FractionallySizedBox(
      heightFactor: 0.82,
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 12, 12),
            child: Row(
              children: <Widget>[
                Expanded(child: Text('Notification', style: text.titleLarge)),
                IconButton(
                  tooltip: 'Close notification',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              children: <Widget>[
                _MessageCard(alert: alert),
                const SizedBox(height: 12),
                _DeliveryCard(alert: alert),
                if (hasRelated) ...<Widget>[
                  const SizedBox(height: 12),
                  details.when(
                    loading: () => _LoadingCard(
                      label: alert.noticeId != null
                          ? 'Loading the notice…'
                          : 'Loading your bill…',
                    ),
                    error: (Object _, StackTrace _) => _Unavailable(
                      aboutNotice: alert.noticeId != null,
                      onRetry: () =>
                          ref.invalidate(notificationDetailsProvider(alert)),
                    ),
                    data: (NotificationDetails value) => _Related(
                      details: value,
                      today: today,
                      onRetry: () =>
                          ref.invalidate(notificationDetailsProvider(alert)),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The bill or notice behind the notification, or why it cannot be shown.
class _Related extends StatelessWidget {
  final NotificationDetails details;
  final PhDate today;
  final VoidCallback onRetry;

  const _Related({
    required this.details,
    required this.today,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final Bill? bill = details.bill;
    final ActiveNotice? notice = details.notice;

    if (bill != null) return _BillCard(bill: bill, today: today);
    if (notice != null) return _NoticeCard(notice: notice);
    if (details.relatedFailure != null) {
      return _Unavailable(
        aboutNotice: details.notification.noticeId != null,
        onRetry: onRetry,
      );
    }
    if (details.noticeNoLongerActive) {
      return const _Note(
        icon: Icons.task_alt,
        message:
            'This disconnection notice is no longer active. Ask your Area '
            'President if you need to know how it was closed.',
      );
    }
    return const _Note(
      icon: Icons.info_outline,
      message:
          'The bill this was about is no longer available on this account.',
    );
  }
}

/// What arrived: the whole message, under the title the list showed.
class _MessageCard extends StatelessWidget {
  final AppNotification alert;

  const _MessageCard({required this.alert});

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colours = Theme.of(context).colorScheme;
    final String? urgency = notificationUrgency(alert.type);
    final Color accent = urgency == null ? colours.primary : colours.error;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: urgency == null
            ? colours.surfaceContainerLowest
            : colours.errorContainer.withValues(alpha: 0.38),
        border: Border.all(
          color: urgency == null
              ? colours.outlineVariant
              : colours.error.withValues(alpha: 0.30),
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              _IconTile(icon: notificationIcon(alert.type), colour: accent),
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
                      const SizedBox(height: 2),
                    ],
                    Text(
                      notificationTitle(alert.type),
                      style: text.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SelectableText(alert.message, style: text.bodyLarge),
        ],
      ),
    );
  }
}

/// When it came, how, and whether it got through.
class _DeliveryCard extends StatelessWidget {
  final AppNotification alert;

  const _DeliveryCard({required this.alert});

  @override
  Widget build(BuildContext context) {
    final ColorScheme colours = Theme.of(context).colorScheme;
    final bool sms = alert.channel.toLowerCase() == 'sms';
    final bool failed = alert.status == 'failed';
    final DateTime? sentAt = alert.sentAt;

    final String status = switch (alert.status) {
      'sent' => sms ? 'Sent to your mobile number' : 'Shown on your phone',
      'failed' => sms ? 'Text message not sent' : 'Not shown on your phone',
      'pending' => sms ? 'Waiting to be sent' : 'Waiting to be shown',
      _ => 'In your Inbox',
    };

    final String? statusNote = failed
        ? alert.failedReason
        : alert.status == 'sent' && sentAt != null
        ? phDateTimeLabel(sentAt, withYear: true)
        : null;

    return _SectionCard(
      title: 'DELIVERY',
      child: Column(
        children: <Widget>[
          _DetailRow(
            icon: Icons.schedule,
            label: 'Received',
            value: phDateTimeLabel(alert.createdAt, withYear: true),
          ),
          const Divider(height: 20),
          _DetailRow(
            icon: sms ? Icons.sms_outlined : Icons.notifications_none,
            label: 'Sent as',
            value: sms ? 'Text message (SMS)' : 'Phone notification',
          ),
          const Divider(height: 20),
          _DetailRow(
            icon: failed ? Icons.error_outline : Icons.check_circle_outline,
            iconColour: failed ? colours.error : null,
            label: 'Status',
            value: status,
            note: statusNote,
            noteIsWarning: failed,
          ),
        ],
      ),
    );
  }
}

/// The bill a bill-ready, reminder or overdue alert is about.
class _BillCard extends StatelessWidget {
  final Bill bill;
  final PhDate today;

  const _BillCard({required this.bill, required this.today});

  @override
  Widget build(BuildContext context) {
    final bool overdue = bill.isOverdueOn(today);

    return _SectionCard(
      title: 'ABOUT YOUR BILL',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _DetailRow(
            icon: Icons.calendar_month_outlined,
            label: 'Billing month',
            value: bill.cycle.displayName,
          ),
          const Divider(height: 20),
          // An unpriced bill has no figure, so it says so in words rather
          // than printing a zero that looks like a bill.
          _DetailRow(
            icon: Icons.payments_outlined,
            label: bill.isUnpriced ? 'Amount' : 'Remaining balance',
            value: bill.isUnpriced ? 'Not posted yet' : bill.balance.format(),
          ),
          const Divider(height: 20),
          _DetailRow(
            icon: overdue ? Icons.event_busy : Icons.event_outlined,
            iconColour: overdue ? Theme.of(context).colorScheme.error : null,
            label: 'Due date',
            value: bill.dueDate == null
                ? 'Not assigned yet'
                : friendlyPhDate(bill.dueDate!),
            note: bill.statusLabelOn(today),
            noteIsWarning: overdue,
          ),
          const Divider(height: 20),
          _DetailRow(
            icon: Icons.tag,
            label: 'Bill number',
            value: bill.billNo.value,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () =>
                showConsumerBillDetails(context, bill: bill, today: today),
            icon: const Icon(Icons.receipt_long_outlined, size: 18),
            label: const Text('View full bill'),
          ),
        ],
      ),
    );
  }
}

/// The disconnection notice a disconnection alert announces.
class _NoticeCard extends StatelessWidget {
  final ActiveNotice notice;

  const _NoticeCard({required this.notice});

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colours = Theme.of(context).colorScheme;

    return _SectionCard(
      title: 'DISCONNECTION NOTICE',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _DetailRow(
            icon: Icons.tag,
            label: 'Notice number',
            value: notice.noticeNo,
          ),
          const Divider(height: 20),
          _DetailRow(
            icon: Icons.payments_outlined,
            iconColour: colours.error,
            label: 'Amount overdue',
            value: notice.amountOverdue.format(),
          ),
          const Divider(height: 20),
          _DetailRow(
            icon: Icons.event_note_outlined,
            label: 'Served',
            value: phDateTimeLabel(notice.servedAt, withYear: true),
          ),
          const Divider(height: 20),
          // Computed by the server from when the notice was served, past
          // Sundays and holidays. The phone only shows it.
          _DetailRow(
            icon: Icons.power_off_outlined,
            iconColour: colours.error,
            label: 'Earliest lawful disconnection',
            value: phDateTimeLabel(notice.earliestLawfulAt, withYear: true),
            note: notice.periodElapsed
                ? 'The notice period has ended.'
                : 'Your electricity may not be disconnected before this.',
            noteIsWarning: notice.periodElapsed,
          ),
          const Divider(height: 20),
          _DetailRow(
            icon: Icons.info_outline,
            label: 'Reason',
            value: notice.reason,
          ),
          const SizedBox(height: 16),
          Text(
            'Paying the amount overdue at your area’s cashier is how this '
            'notice is settled. Keep the receipt the cashier gives you.',
            style: text.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  final String label;

  const _LoadingCard({required this.label});

  @override
  Widget build(BuildContext context) => _SectionCard(
    title: 'DETAILS',
    child: Row(
      children: <Widget>[
        const SizedBox.square(
          dimension: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 12),
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
      ],
    ),
  );
}

/// The bill or notice could not be read, most often for want of signal.
class _Unavailable extends StatelessWidget {
  final bool aboutNotice;
  final VoidCallback onRetry;

  const _Unavailable({required this.aboutNotice, required this.onRetry});

  @override
  Widget build(BuildContext context) => _SectionCard(
    title: 'DETAILS',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          aboutNotice
              ? 'The notice couldn’t be loaded right now. Check your '
                    'connection and try again.'
              : 'Your bill couldn’t be loaded right now. Check your '
                    'connection and try again.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Try again'),
        ),
      ],
    ),
  );
}

class _Note extends StatelessWidget {
  final IconData icon;
  final String message;

  const _Note({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) => _SectionCard(
    title: 'DETAILS',
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(
          icon,
          size: 20,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(message, style: Theme.of(context).textTheme.bodyMedium),
        ),
      ],
    ),
  );
}

/// A label above its value, so a long value — a failure reason, a notice
/// reason — wraps instead of being squeezed beside its label.
class _DetailRow extends StatelessWidget {
  final IconData icon;
  final Color? iconColour;
  final String label;
  final String value;
  final String? note;
  final bool noteIsWarning;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.iconColour,
    this.note,
    this.noteIsWarning = false,
  });

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colours = Theme.of(context).colorScheme;
    final String? note = this.note;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _IconTile(icon: icon, colour: iconColour ?? colours.primary, size: 36),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(label, style: text.bodySmall),
              const SizedBox(height: 2),
              Text(
                value,
                style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
              if (note != null) ...<Widget>[
                const SizedBox(height: 2),
                Text(
                  note,
                  style: text.bodySmall?.copyWith(
                    color: noteIsWarning ? colours.error : null,
                    fontWeight: noteIsWarning ? FontWeight.w600 : null,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _IconTile extends StatelessWidget {
  final IconData icon;
  final Color colour;
  final double size;

  const _IconTile({required this.icon, required this.colour, this.size = 40});

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: colour.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Icon(icon, size: size * 0.5, color: colour),
  );
}

/// A white card with an uppercase section label, in the bill sheet's style.
class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colours = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colours.surfaceContainerLowest,
        border: Border.all(color: colours.outlineVariant),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: text.labelMedium?.copyWith(
              color: colours.onSurfaceVariant,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
