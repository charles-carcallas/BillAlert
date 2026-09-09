import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/repositories/payment_repository.dart';
import '../../domain/value_objects/ph_date.dart';
import '../common/failure_banner.dart';
import 'receipts_controller.dart';

/// CSH-03 — Cashier › Receipts.
///
/// One row per handover, not per bill. A receipt that settled three months
/// appears once and says "3 months", because that is what was handed over.
///
/// Grouped by Philippine calendar day. `paid_at` is a UTC instant, and a
/// payment taken at 7am in Tubod is the previous day in UTC — so the day is
/// worked out through [PhDate], the same way every other date in this app is.
class ReceiptsScreen extends ConsumerWidget {
  const ReceiptsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(receiptsControllerProvider);
    final controller = ref.read(receiptsControllerProvider.notifier);
    final TextTheme text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Receipts')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: controller.load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: <Widget>[
              _TodayCard(today: state.today),

              if (state.failure != null) ...<Widget>[
                const SizedBox(height: 12),
                FailureBanner(failure: state.failure!, onRetry: controller.load),
              ],

              const SizedBox(height: 20),

              if (state.isLoading && state.receipts.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (state.receipts.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 48),
                  child: Column(
                    children: <Widget>[
                      Icon(
                        Icons.receipt_long_outlined,
                        size: 40,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No receipts yet.',
                        style: text.titleMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Receipts appear here as cash is collected.',
                        style: text.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              else
                ..._grouped(context, state.receipts),
            ],
          ),
        ),
      ),
    );
  }

  /// Day headings with their receipts underneath, newest day first.
  static List<Widget> _grouped(
    BuildContext context,
    List<PaymentSummary> receipts,
  ) {
    final TextTheme text = Theme.of(context).textTheme;
    final PhDate today = PhDate.at(DateTime.now());

    final widgets = <Widget>[];
    PhDate? currentDay;

    // The list already arrives newest first, so a heading is emitted whenever
    // the day changes rather than by sorting into buckets first.
    for (final PaymentSummary receipt in receipts) {
      final PhDate day = PhDate.at(receipt.paidAt);
      if (currentDay == null || day != currentDay) {
        if (currentDay != null) widgets.add(const SizedBox(height: 20));
        widgets.add(Text(_dayLabel(day, today), style: text.titleSmall));
        widgets.add(const SizedBox(height: 8));
        currentDay = day;
      }
      widgets.add(_ReceiptTile(receipt: receipt));
    }

    return widgets;
  }

  static String _dayLabel(PhDate day, PhDate today) {
    final int daysAgo = today.daysSince(day);
    if (daysAgo == 0) return 'Today';
    if (daysAgo == 1) return 'Yesterday';
    return '${_weekday(day)}, ${day.day} ${_month(day.month)}';
  }

  static const List<String> _months = <String>[
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  static String _month(int month) => _months[month - 1];

  static const List<String> _weekdays = <String>[
    'Monday', 'Tuesday', 'Wednesday', 'Thursday',
    'Friday', 'Saturday', 'Sunday',
  ];

  /// DateTime.weekday is 1..7 starting at Monday, which is the same order as
  /// the list above.
  static String _weekday(PhDate day) =>
      _weekdays[DateTime.utc(day.year, day.month, day.day).weekday - 1];
}

class _TodayCard extends StatelessWidget {
  final CollectionSummary today;

  const _TodayCard({required this.today});

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text("Today's collections", style: text.bodySmall),
                  const SizedBox(height: 2),
                  Text(today.totalCollected.format(), style: text.headlineMedium),
                ],
              ),
            ),
            Text(
              '${today.receiptCount} receipt'
              '${today.receiptCount == 1 ? '' : 's'}',
              style: text.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _ReceiptTile extends StatelessWidget {
  final PaymentSummary receipt;

  const _ReceiptTile({required this.receipt});

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(receipt.receiptNo, style: text.titleSmall),
                  const SizedBox(height: 2),
                  Text(
                    '${_time(receipt.paidAt)} · ${receipt.billCount} '
                    'month${receipt.billCount == 1 ? '' : 's'}',
                    style: text.bodySmall,
                  ),
                  const SizedBox(height: 6),
                  // Which months this one handover settled. The same receipt
                  // number against several months is the correct result.
                  Text(
                    receipt.bills
                        .map((SettledBill b) => b.cycleLabel)
                        .where((String label) => label.isNotEmpty)
                        .join(' · '),
                    style: text.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(receipt.totalCollected.format(), style: text.titleMedium),
          ],
        ),
      ),
    );
  }

  /// "2:18 PM" in Philippine time. Written out rather than taken from `intl`,
  /// which this project deliberately does not depend on.
  static String _time(DateTime instant) {
    final DateTime manila = instant.toUtc().add(PhDate.utcOffset);
    final int hour24 = manila.hour;
    final int hour = hour24 % 12 == 0 ? 12 : hour24 % 12;
    final String minute = manila.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${hour24 < 12 ? 'AM' : 'PM'}';
  }
}
