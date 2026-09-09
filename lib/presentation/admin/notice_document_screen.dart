import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/repositories/notice_repository.dart';
import '../../domain/value_objects/ph_date.dart';
import '../common/failure_banner.dart';
import 'notice_document_controller.dart';

/// DOM-05 — the document for one active disconnection notice.
///
/// `noticeId` comes from `/admin/notice/:noticeId`. The document renders the
/// server's lawful moment and elapsed flag as received; it never derives a
/// second deadline from the device clock.
class NoticeDocumentScreen extends ConsumerStatefulWidget {
  final String noticeId;

  const NoticeDocumentScreen({required this.noticeId, super.key});

  @override
  ConsumerState<NoticeDocumentScreen> createState() =>
      _NoticeDocumentScreenState();
}

class _NoticeDocumentScreenState extends ConsumerState<NoticeDocumentScreen> {
  @override
  Widget build(BuildContext context) {
    final NoticeDocumentState state = ref.watch(
      noticeDocumentControllerProvider(widget.noticeId),
    );
    final NoticeDocumentController controller = ref.read(
      noticeDocumentControllerProvider(widget.noticeId).notifier,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Disconnection Notice')),
      body: SafeArea(
        child: _body(state: state, controller: controller),
      ),
    );
  }

  Widget _body({
    required NoticeDocumentState state,
    required NoticeDocumentController controller,
  }) {
    if (state.closedOutcome case final NoticeOutcome outcome) {
      return _ClosedNotice(outcome: outcome);
    }

    if (state.isLoading && state.notice == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.notice == null && state.failure != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: FailureBanner(failure: state.failure!, onRetry: controller.load),
      );
    }

    final ActiveNotice? notice = state.notice;
    if (notice == null) {
      return _InactiveNotice(onRefresh: controller.load);
    }

    return RefreshIndicator(
      onRefresh: controller.load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: <Widget>[
          _NoticeBanner(noticeNo: notice.noticeNo),
          const SizedBox(height: 14),
          _LawfulMoment(notice: notice),
          const SizedBox(height: 14),
          _NoticeDetails(notice: notice),
          const SizedBox(height: 14),
          _HowToSettle(notice: notice),
          const SizedBox(height: 14),
          _ScopeStatement(periodElapsed: notice.periodElapsed),
          if (state.failure != null) ...<Widget>[
            const SizedBox(height: 14),
            FailureBanner(failure: state.failure!),
          ],
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: state.isClosing
                ? null
                : () => _showCloseDialog(controller),
            icon: state.isClosing
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.task_alt),
            label: Text(
              state.isClosing ? 'Recording outcome…' : 'Close this notice',
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showCloseDialog(NoticeDocumentController controller) async {
    final TextEditingController notes = TextEditingController();
    NoticeOutcome? selected;

    final _CloseChoice? choice = await showDialog<_CloseChoice>(
      context: context,
      builder: (BuildContext dialogContext) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setDialogState) {
          return AlertDialog(
            title: const Text('Close this notice?'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const Text(
                    'Choose the outcome that cooperative records support. '
                    'This is an online-only action and cannot be queued.',
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      for (final NoticeOutcome outcome in NoticeOutcome.values)
                        ChoiceChip(
                          label: Text(_outcomeTitle(outcome)),
                          selected: selected == outcome,
                          onSelected: (bool chosen) {
                            setDialogState(
                              () => selected = chosen ? outcome : null,
                            );
                          },
                        ),
                    ],
                  ),
                  if (selected == NoticeOutcome.referred) ...<Widget>[
                    const SizedBox(height: 12),
                    Text(
                      'Referred records a handover to cooperative personnel. '
                      'It does not authorise, schedule, or execute a '
                      'disconnection.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: 16),
                  TextField(
                    controller: notes,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Notes (optional)',
                      hintText: 'Record supporting details',
                    ),
                  ),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: selected == null
                    ? null
                    : () => Navigator.of(
                        dialogContext,
                      ).pop(_CloseChoice(selected!, notes.text)),
                child: const Text('Confirm outcome'),
              ),
            ],
          );
        },
      ),
    );

    notes.dispose();
    if (choice == null || !mounted) return;
    await controller.close(outcome: choice.outcome, notes: choice.notes);
  }
}

final class _CloseChoice {
  final NoticeOutcome outcome;
  final String notes;

  const _CloseChoice(this.outcome, this.notes);
}

class _NoticeBanner extends StatelessWidget {
  final String noticeNo;

  const _NoticeBanner({required this.noticeNo});

  @override
  Widget build(BuildContext context) {
    final ColorScheme colours = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: colours.error,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'DISCONNECTION NOTICE',
            style: text.labelMedium?.copyWith(
              color: colours.onError,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 4),
          SelectableText(
            noticeNo,
            style: text.titleSmall?.copyWith(color: colours.onError),
          ),
        ],
      ),
    );
  }
}

class _LawfulMoment extends StatelessWidget {
  final ActiveNotice notice;

  const _LawfulMoment({required this.notice});

  @override
  Widget build(BuildContext context) {
    final ColorScheme colours = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: colours.errorContainer,
        border: Border.all(color: colours.error, width: 1.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Earliest lawful disconnection',
            style: text.labelMedium?.copyWith(color: colours.error),
          ),
          const SizedBox(height: 3),
          Text(
            _phStamp(notice.earliestLawfulAt),
            style: text.titleLarge?.copyWith(color: colours.onErrorContainer),
          ),
          const SizedBox(height: 4),
          Text(
            notice.periodElapsed
                ? 'The server records the notice period as elapsed.'
                : 'The server records the notice period as not elapsed. '
                      '${notice.hoursRemaining} hours remain.',
            style: text.bodySmall?.copyWith(color: colours.onErrorContainer),
          ),
        ],
      ),
    );
  }
}

class _NoticeDetails extends StatelessWidget {
  final ActiveNotice notice;

  const _NoticeDetails({required this.notice});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _Fact(term: 'Household', value: notice.consumerLabel),
            _Fact(
              term: 'Consumer number',
              value: notice.consumerNo ?? 'Not recorded',
            ),
            _Fact(term: 'Address', value: notice.addressLine),
            _Fact(
              term: 'Meter serial',
              value: notice.meterSerialNo ?? 'Not recorded',
            ),
            _Fact(term: 'Reason', value: notice.reason),
            _Fact(term: 'Served', value: _phStamp(notice.servedAt)),
            _Fact(
              term: 'Served by',
              value: notice.issuedByName ?? 'Not available',
            ),
            _Fact(
              term: 'Amount overdue',
              value: notice.amountOverdue.format(),
              emphasize: true,
              last: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  final String term;
  final String value;
  final bool emphasize;
  final bool last;

  const _Fact({
    required this.term,
    required this.value,
    this.emphasize = false,
    this.last = false,
  });

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colours = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(term, style: text.bodySmall),
          const SizedBox(height: 2),
          SelectableText(
            value,
            style: text.bodyMedium?.copyWith(
              color: emphasize ? colours.error : colours.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _HowToSettle extends StatelessWidget {
  final ActiveNotice notice;

  const _HowToSettle({required this.notice});

  @override
  Widget build(BuildContext context) {
    final ColorScheme colours = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: colours.primaryContainer.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'How to stop this',
            style: text.labelMedium?.copyWith(color: colours.primary),
          ),
          const SizedBox(height: 6),
          Text(
            'Settle ${notice.amountOverdue.format()} at the cooperative '
            'counter. Quote reference ${notice.noticeNo}.',
            style: text.bodyMedium?.copyWith(color: colours.onSurface),
          ),
        ],
      ),
    );
  }
}

class _ScopeStatement extends StatelessWidget {
  final bool periodElapsed;

  const _ScopeStatement({required this.periodElapsed});

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Divider(),
        const SizedBox(height: 11),
        Text(
          'BillAlert records and tracks disconnection notices. It never '
          'authorises, schedules, or executes a disconnection. “Referred” '
          'records only a handover to cooperative personnel; any decision '
          'or action remains with Bohol I Electric Cooperative.',
          style: text.labelSmall,
        ),
        const SizedBox(height: 6),
        Text(
          'Notice-period status supplied by the server: '
          '${periodElapsed ? 'elapsed' : 'not elapsed'}.',
          style: text.labelSmall,
        ),
      ],
    );
  }
}

class _InactiveNotice extends StatelessWidget {
  final Future<void> Function() onRefresh;

  const _InactiveNotice({required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.task_alt,
              size: 40,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              'This notice is no longer active.',
              style: text.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              'It may already have been settled, cancelled, or referred.',
              style: text.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextButton(onPressed: onRefresh, child: const Text('Check again')),
          ],
        ),
      ),
    );
  }
}

class _ClosedNotice extends StatelessWidget {
  final NoticeOutcome outcome;

  const _ClosedNotice({required this.outcome});

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.check_circle_outline,
              size: 44,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 14),
            Text('Notice closed', style: text.titleLarge),
            const SizedBox(height: 6),
            Text(
              _outcomeConfirmation(outcome),
              style: text.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }
}

String _outcomeTitle(NoticeOutcome outcome) => switch (outcome) {
  NoticeOutcome.settled => 'Settled',
  NoticeOutcome.cancelled => 'Cancelled',
  NoticeOutcome.referred => 'Referred',
};

String _outcomeConfirmation(NoticeOutcome outcome) => switch (outcome) {
  NoticeOutcome.settled => 'The household’s notice was recorded as settled.',
  NoticeOutcome.cancelled => 'The notice was recorded as cancelled.',
  NoticeOutcome.referred =>
    'The handover to cooperative personnel was recorded. BillAlert did '
        'not authorise, schedule, or execute a disconnection.',
};

/// Formats an instant in Philippine Standard Time (UTC+08:00).
///
/// This only presents the exact server instant. It does not calculate the
/// earliest lawful moment or decide whether the notice period has elapsed.
String _phStamp(DateTime instant) {
  final DateTime manila = instant.toUtc().add(PhDate.utcOffset);
  final int hour24 = manila.hour;
  final int hour = hour24 % 12 == 0 ? 12 : hour24 % 12;
  final String minute = manila.minute.toString().padLeft(2, '0');
  const List<String> months = <String>[
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return '${manila.day} ${months[manila.month - 1]} ${manila.year}, '
      '$hour:$minute ${hour24 < 12 ? 'AM' : 'PM'}';
}
