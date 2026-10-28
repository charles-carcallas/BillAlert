import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/repositories/payment_repository.dart';
import '../../domain/value_objects/ph_date.dart';
import '../common/failure_banner.dart';
import '../common/local_search_field.dart';
import '../common/local_sort_button.dart';
import '../common/payment_search.dart';
import '../common/staff_app_bar.dart';
import 'receipt_details_sheet.dart';
import 'receipts_controller.dart';

/// CSH-03 — Cashier › Receipts.
///
/// One row per handover, not per bill. A receipt that settled three months
/// appears once and says "3 months", because that is what was handed over.
///
/// Grouped by Philippine calendar day. `paid_at` is a UTC instant, and a
/// payment taken at 7am in Tubod is the previous day in UTC — so the day is
/// worked out through [PhDate], the same way every other date in this app is.
class ReceiptsScreen extends ConsumerStatefulWidget {
  const ReceiptsScreen({super.key});

  @override
  ConsumerState<ReceiptsScreen> createState() => _ReceiptsScreenState();
}

enum _ReceiptSort { newest, oldest }

class _ReceiptsScreenState extends ConsumerState<ReceiptsScreen> {
  final TextEditingController _search = TextEditingController();
  _ReceiptSort _sort = _ReceiptSort.newest;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(receiptsControllerProvider);
    final controller = ref.read(receiptsControllerProvider.notifier);
    final TextTheme text = Theme.of(context).textTheme;
    final List<PaymentSummary> visible =
        state.receipts
            .where((receipt) => paymentMatchesSearch(receipt, _search.text))
            .toList()
          ..sort((a, b) {
            final byDate = _sort == _ReceiptSort.newest
                ? b.paidAt.compareTo(a.paidAt)
                : a.paidAt.compareTo(b.paidAt);
            return byDate != 0 ? byDate : a.receiptNo.compareTo(b.receiptNo);
          });

    return Scaffold(
      appBar: const StaffAppBar(title: 'Receipts'),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: controller.load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: <Widget>[
              _CollectionsSummary(
                today: state.today,
                outstanding: state.outstanding,
              ),

              if (state.failure != null) ...<Widget>[
                const SizedBox(height: 12),
                FailureBanner(
                  failure: state.failure!,
                  onRetry: controller.load,
                ),
              ],

              const SizedBox(height: 20),

              if (state.receipts.isNotEmpty) ...<Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: LocalSearchField(
                        fieldKey: const ValueKey<String>(
                          'cashier-receipts-search',
                        ),
                        controller: _search,
                        onChanged: (_) => setState(() {}),
                        hintText: 'Search consumer or receipt number',
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 120,
                      child: LocalSortButton<_ReceiptSort>(
                        buttonKey: const ValueKey('cashier-receipts-sort'),
                        value: _sort,
                        options: const <LocalSortOption<_ReceiptSort>>[
                          LocalSortOption(
                            value: _ReceiptSort.newest,
                            label: 'Newest',
                            icon: Icons.arrow_downward,
                          ),
                          LocalSortOption(
                            value: _ReceiptSort.oldest,
                            label: 'Oldest',
                            icon: Icons.arrow_upward,
                          ),
                        ],
                        onChanged: (value) => setState(() => _sort = value),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],

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
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: 0.09),
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: Icon(
                          Icons.receipt_long_outlined,
                          size: 36,
                          color: Theme.of(context).colorScheme.primary,
                        ),
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
              else if (visible.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Column(
                    children: <Widget>[
                      Icon(
                        Icons.search_off,
                        size: 40,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No receipt matches that search.',
                        style: text.titleMedium,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              else
                ..._grouped(context, visible),
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

    final groups = <PhDate, List<PaymentSummary>>{};
    for (final PaymentSummary receipt in receipts) {
      final PhDate day = PhDate.at(receipt.paidAt);
      groups.putIfAbsent(day, () => <PaymentSummary>[]).add(receipt);
    }
    return <Widget>[
      for (final entry in groups.entries) ...<Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            _dayLabel(entry.key, today).toUpperCase(),
            style: text.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              letterSpacing: 0.4,
            ),
          ),
        ),
        const SizedBox(height: 8),
        _ReceiptGroup(receipts: entry.value),
        const SizedBox(height: 18),
      ],
    ];
  }

  static String _dayLabel(PhDate day, PhDate today) {
    final int daysAgo = today.daysSince(day);
    if (daysAgo == 0) return 'Today';
    if (daysAgo == 1) return 'Yesterday';
    return '${_weekday(day)}, ${day.day} ${_month(day.month)}';
  }

  static const List<String> _months = <String>[
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

  static String _month(int month) => _months[month - 1];

  static const List<String> _weekdays = <String>[
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  /// DateTime.weekday is 1..7 starting at Monday, which is the same order as
  /// the list above.
  static String _weekday(PhDate day) =>
      _weekdays[DateTime.utc(day.year, day.month, day.day).weekday - 1];
}

/// Separate collection and outstanding figures inside one summary panel.
/// These amounts are never added together.
class _CollectionsSummary extends StatelessWidget {
  final CollectionSummary today;

  /// Null until the roll-up has loaded. Only the collected figure is shown
  /// until then, rather than claiming an outstanding balance of zero.
  final AreaOutstanding? outstanding;

  const _CollectionsSummary({required this.today, required this.outstanding});

  @override
  Widget build(BuildContext context) {
    final colours = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colours.surfaceContainerLowest,
        border: Border.all(color: colours.outlineVariant),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
          final compact = constraints.maxWidth < 600 * scale;
          final collected = _CollectionMetric(
            icon: Icons.receipt_long_outlined,
            label: "Today's collections",
            amount: today.totalCollected.format(),
            detail:
                '${today.receiptCount} receipt'
                '${today.receiptCount == 1 ? '' : 's'}',
            accent: colours.primary,
            compact: compact,
          );
          final owed = outstanding;
          if (owed == null) return collected;
          final remaining = _CollectionMetric(
            icon: Icons.account_balance_wallet_outlined,
            label: 'Still to collect',
            amount: owed.total.format(),
            detail:
                '${owed.households} household'
                '${owed.households == 1 ? '' : 's'}',
            overdue: owed.overdueHouseholds,
            accent: owed.overdueHouseholds > 0
                ? colours.error
                : colours.onSurfaceVariant,
            compact: compact,
          );
          if (constraints.maxWidth >= 240 * scale) {
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(child: collected),
                  VerticalDivider(width: compact ? 24 : 40),
                  Expanded(child: remaining),
                ],
              ),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              collected,
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Divider(),
              ),
              remaining,
            ],
          );
        },
      ),
    );
  }
}

class _CollectionMetric extends StatelessWidget {
  final IconData icon;
  final String label;
  final String amount;
  final String detail;
  final Color accent;
  final int overdue;
  final bool compact;

  const _CollectionMetric({
    required this.icon,
    required this.label,
    required this.amount,
    required this.detail,
    required this.accent,
    this.overdue = 0,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colours = Theme.of(context).colorScheme;
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: compact ? text.bodySmall : text.bodyMedium),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            amount,
            maxLines: 1,
            style: text.headlineMedium?.copyWith(
              color: accent,
              fontSize: compact ? 24 : 28,
              height: 1.2,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: <Widget>[
            Text(detail, style: text.bodySmall),
            if (overdue > 0)
              Text(
                '$overdue overdue',
                style: text.bodySmall?.copyWith(
                  color: colours.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
      ],
    );
    if (compact) return content;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.09),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, size: 24, color: accent),
        ),
        const SizedBox(width: 14),
        Expanded(child: content),
      ],
    );
  }
}

class _ReceiptGroup extends StatelessWidget {
  final List<PaymentSummary> receipts;

  const _ReceiptGroup({required this.receipts});

  @override
  Widget build(BuildContext context) {
    final colours = Theme.of(context).colorScheme;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colours.surfaceContainerLowest,
        border: Border.all(color: colours.outlineVariant),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: <Widget>[
          for (var index = 0; index < receipts.length; index++) ...<Widget>[
            _ReceiptTile(receipt: receipts[index]),
            if (index < receipts.length - 1)
              const Divider(indent: 16, endIndent: 16),
          ],
        ],
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
    final colours = Theme.of(context).colorScheme;
    final initials = receipt.consumerName
        .split(' ')
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0])
        .join()
        .toUpperCase();

    return Semantics(
      button: true,
      label: 'Open receipt ${receipt.receiptNo}',
      child: InkWell(
        onTap: () => showCashierReceiptDetails(context, receipt),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              CircleAvatar(
                radius: 18,
                backgroundColor: colours.primary.withValues(alpha: 0.11),
                foregroundColor: colours.primary,
                child: Text(
                  initials.isEmpty ? '?' : initials,
                  style: text.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(receipt.consumerName, style: text.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      '${receipt.receiptNo} · ${_time(receipt.paidAt)}',
                      style: text.bodySmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${receipt.billCount} '
                      'month${receipt.billCount == 1 ? '' : 's'} settled',
                      style: text.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(receipt.totalCollected.format(), style: text.titleMedium),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right,
                color: colours.onSurfaceVariant,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _time(DateTime instant) {
    final DateTime manila = instant.toUtc().add(PhDate.utcOffset);
    final int hour24 = manila.hour;
    final int hour = hour24 % 12 == 0 ? 12 : hour24 % 12;
    final String minute = manila.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${hour24 < 12 ? 'AM' : 'PM'}';
  }
}
