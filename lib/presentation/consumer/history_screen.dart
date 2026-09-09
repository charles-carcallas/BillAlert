import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/entities/bill.dart';
import '../../domain/value_objects/ph_date.dart';
import '../common/failure_banner.dart';
import '../providers.dart';
import '../router.dart';
import 'history_controller.dart';

/// CON-07 — Consumer › History.
///
/// One row per month, newest first, each saying what it came to and how it
/// stands. Where a month has been settled it carries the receipt number that
/// settled it — and the same number appearing against several months is
/// correct, not a duplicate: one handover pays for as many months as the
/// consumer chose to clear.
///
/// An unpriced month appears here too, with no peso figure at all. Leaving it
/// out would be tidier and would hide the seven-day wait this whole
/// application exists to make visible.
class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(historyControllerProvider);
    final controller = ref.read(historyControllerProvider.notifier);
    final TextTheme text = Theme.of(context).textTheme;

    // The status of a bill depends on what day it is, so the clock is asked
    // once here rather than by each row.
    final PhDate today = ref.read(phClockProvider).today();

    return Scaffold(
      appBar: AppBar(title: const Text('History')),
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

              if (state.isLoading && state.bills.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (state.bills.isEmpty && state.failure == null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 48),
                  child: Column(
                    children: <Widget>[
                      Icon(
                        Icons.history,
                        size: 40,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No months yet.',
                        style: text.titleMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Your bills will appear here once your meter has been '
                        'read.',
                        style: text.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              else
                for (final Bill bill in state.bills)
                  _MonthTile(
                    bill: bill,
                    today: today,
                    receiptNo: state.receiptByBillId[bill.id.value],
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MonthTile extends StatelessWidget {
  final Bill bill;
  final PhDate today;
  final String? receiptNo;

  const _MonthTile({
    required this.bill,
    required this.today,
    this.receiptNo,
  });

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    final Widget row = Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(bill.cycle.displayName, style: text.titleMedium),
                  const SizedBox(height: 2),
                  Text(
                    '${bill.billNo.value} · ${bill.consumption.format()}',
                    style: text.bodySmall,
                  ),
                  if (receiptNo != null) ...<Widget>[
                    const SizedBox(height: 4),
                    Text('Receipt $receiptNo', style: text.bodySmall),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                // An unpriced month shows no figure. The entity is asked
                // whether it has one; the screen never tests for null itself.
                Text(
                  bill.isUnpriced ? '—' : bill.totalAmount!.format(),
                  style: text.titleMedium,
                ),
                const SizedBox(height: 4),
                _StatusChip(label: bill.statusLabelOn(today)),
              ],
            ),
          ],
      ),
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      // Only a settled month has a receipt to open. The rest are not
      // tappable, rather than tappable and then apologetic.
      child: receiptNo == null
          ? row
          : InkWell(
              onTap: () => context.push(Routes.consumerReceiptFor(receiptNo!)),
              child: row,
            ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;

  const _StatusChip({required this.label});

  @override
  Widget build(BuildContext context) {
    final ColorScheme colours = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: colours.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: colours.onSurfaceVariant),
      ),
    );
  }
}
