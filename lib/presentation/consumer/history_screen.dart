import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/entities/bill.dart';
import '../../domain/repositories/payment_repository.dart';
import '../../domain/value_objects/ph_date.dart';
import '../common/failure_banner.dart';
import '../common/local_sort_button.dart';
import '../providers.dart';
import '../router.dart';
import 'bill_details_sheet.dart';
import 'consumer_app_bar.dart';
import 'history_controller.dart';
import 'payment_history_filter.dart';

/// CON-07 — Consumer › History.
///
/// Bills show one row per cycle. Payments show one row per cash handover,
/// filtered and sorted by the actual payment date in Philippine time.
///
/// An unpriced month appears here too, with no peso figure at all. Leaving it
/// out would be tidier and would hide the seven-day wait this whole
/// application exists to make visible.
enum _HistoryView { payments, bills }

enum _DateOrder { newestFirst, oldestFirst }

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  _HistoryView _view = _HistoryView.payments;
  _DateOrder _dateOrder = _DateOrder.newestFirst;
  DateTimeRange? _paymentRange;
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(historyControllerProvider);
    final controller = ref.read(historyControllerProvider.notifier);
    final TextTheme text = Theme.of(context).textTheme;

    // The status of a bill depends on what day it is, so the clock is asked
    // once here rather than by each row.
    final PhDate today = ref.read(phClockProvider).today();
    final String query = _searchController.text.trim().toLowerCase();
    final List<Bill> visibleBills =
        state.bills
            .where(
              (bill) => bill.cycle.displayName.toLowerCase().contains(query),
            )
            .toList()
          ..sort(
            (a, b) => _dateOrder == _DateOrder.newestFirst
                ? b.cycle.compareTo(a.cycle)
                : a.cycle.compareTo(b.cycle),
          );
    final DateTimeRange? range = _paymentRange;
    final List<PaymentSummary> visibleReceipts = filterPaymentHistory(
      state.receipts,
      query: query,
      from: range == null
          ? null
          : PhDate(range.start.year, range.start.month, range.start.day),
      through: range == null
          ? null
          : PhDate(range.end.year, range.end.month, range.end.day),
      newestFirst: _dateOrder == _DateOrder.newestFirst,
    );
    final bool payments = _view == _HistoryView.payments;
    final bool noResults = payments
        ? visibleReceipts.isEmpty
        : visibleBills.isEmpty;
    final bool filtered = query.isNotEmpty || (payments && range != null);

    return Scaffold(
      appBar: const ConsumerAppBar(title: 'History'),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: controller.load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: <Widget>[
              _HistoryTabs(
                selected: _view,
                onChanged: (_HistoryView view) {
                  setState(() {
                    _view = view;
                    _searchController.clear();
                  });
                },
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      textInputAction: TextInputAction.search,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: _view == _HistoryView.payments
                            ? 'Search month or OR no.'
                            : 'Search month',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _searchController.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Clear search',
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() {});
                                },
                                icon: const Icon(Icons.close),
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 120,
                    child: LocalSortButton<_DateOrder>(
                      buttonKey: const ValueKey('consumer-history-sort'),
                      value: _dateOrder,
                      options: const <LocalSortOption<_DateOrder>>[
                        LocalSortOption(
                          value: _DateOrder.newestFirst,
                          label: 'Newest',
                          icon: Icons.arrow_downward,
                        ),
                        LocalSortOption(
                          value: _DateOrder.oldestFirst,
                          label: 'Oldest',
                          icon: Icons.arrow_upward,
                        ),
                      ],
                      onChanged: (value) => setState(() => _dateOrder = value),
                    ),
                  ),
                ],
              ),
              if (payments) ...<Widget>[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    OutlinedButton.icon(
                      key: const ValueKey('payment-date-range'),
                      onPressed: () =>
                          _choosePaymentDates(state.receipts, today),
                      icon: const Icon(Icons.date_range_outlined),
                      label: Text(
                        range == null
                            ? 'Payment dates · All dates'
                            : '${_dayLabel(range.start)} – ${_dayLabel(range.end)}',
                      ),
                    ),
                    if (range != null)
                      TextButton(
                        key: const ValueKey('clear-payment-dates'),
                        onPressed: () => setState(() => _paymentRange = null),
                        child: const Text('Clear dates'),
                      ),
                  ],
                ),
                Text(
                  'Payment dates use Philippine time.',
                  style: text.bodySmall,
                ),
              ],
              const SizedBox(height: 12),
              if (state.failure != null) ...<Widget>[
                FailureBanner(
                  failure: state.failure!,
                  onRetry: controller.load,
                ),
                const SizedBox(height: 12),
              ],

              if (state.isLoading &&
                  (payments ? state.receipts.isEmpty : state.bills.isEmpty))
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (noResults && state.failure == null)
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
                        filtered
                            ? 'No matching records.'
                            : _view == _HistoryView.payments
                            ? 'No payments yet.'
                            : 'No bills yet.',
                        style: text.titleMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        filtered
                            ? (payments
                                  ? 'Try another search or clear the payment dates.'
                                  : 'Try another billing month.')
                            : _view == _HistoryView.payments
                            ? 'Completed payments and their receipts will '
                                  'appear here.'
                            : 'Your bills will appear here once your meter '
                                  'has been read.',
                        style: text.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              else if (payments)
                _PaymentHistoryList(receipts: visibleReceipts)
              else
                _HistoryList(bills: visibleBills, today: today),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _choosePaymentDates(
    List<PaymentSummary> receipts,
    PhDate today,
  ) async {
    final DateTime current = DateTime(today.year, today.month, today.day);
    DateTime first = current;
    DateTime last = current;
    for (final receipt in receipts) {
      final PhDate paid = PhDate.at(receipt.paidAt);
      final DateTime day = DateTime(paid.year, paid.month, paid.day);
      if (day.isBefore(first)) first = day;
      if (day.isAfter(last)) last = day;
    }
    // A retained filter can outlive a refresh that removes matching receipts.
    if (_paymentRange case final range?) {
      if (range.start.isBefore(first)) first = range.start;
      if (range.end.isAfter(last)) last = range.end;
    }
    final DateTimeRange? selected = await showDateRangePicker(
      context: context,
      firstDate: DateTime(first.year, 1, 1),
      lastDate: DateTime(last.year, 12, 31),
      currentDate: current,
      initialDateRange: _paymentRange,
      helpText: 'Payment dates',
      saveText: 'Apply',
      builder: (context, child) {
        if (MediaQuery.sizeOf(context).width >= 360) return child!;
        final ThemeData theme = Theme.of(context);
        return Theme(
          data: theme.copyWith(
            datePickerTheme: theme.datePickerTheme.copyWith(
              rangePickerHeaderHeadlineStyle: theme.textTheme.titleMedium,
            ),
          ),
          child: child!,
        );
      },
    );
    if (!mounted || selected == null) return;
    setState(() => _paymentRange = selected);
  }

  static String _dayLabel(DateTime day) =>
      PhDate(day.year, day.month, day.day).toIso();
}

/// A multi-bill handover appears once, and partial payments retain each receipt.
class _PaymentHistoryList extends StatelessWidget {
  final List<PaymentSummary> receipts;

  const _PaymentHistoryList({required this.receipts});

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Column(
      children: <Widget>[
        for (final receipt in receipts)
          Card(
            key: ValueKey('payment-${receipt.receiptNo}'),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () =>
                  context.push(Routes.consumerReceiptFor(receipt.receiptNo)),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('OR ${receipt.receiptNo}', style: text.titleSmall),
                    const SizedBox(height: 4),
                    Text(
                      'Paid ${PhDate.at(receipt.paidAt).toIso()}',
                      style: text.bodySmall,
                    ),
                    Text(
                      receipt.bills
                          .map(
                            (bill) => bill.cycleLabel.isEmpty
                                ? bill.billNo.value
                                : bill.cycleLabel,
                          )
                          .join(' · '),
                      style: text.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            receipt.totalCollected.format(),
                            style: text.titleMedium,
                          ),
                        ),
                        const Icon(Icons.chevron_right, size: 18),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _HistoryTabs extends StatelessWidget {
  final _HistoryView selected;
  final ValueChanged<_HistoryView> onChanged;

  const _HistoryTabs({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final colours = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colours.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          for (final view in _HistoryView.values)
            Expanded(
              child: _HistoryTab(
                label: view == _HistoryView.payments ? 'Payments' : 'Bills',
                selected: selected == view,
                onTap: () => onChanged(view),
              ),
            ),
        ],
      ),
    );
  }
}

class _HistoryTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _HistoryTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colours = Theme.of(context).colorScheme;
    return Material(
      color: selected ? colours.surfaceContainerLowest : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(
            label,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: selected ? colours.primary : colours.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

class _HistoryList extends StatelessWidget {
  final List<Bill> bills;
  final PhDate today;

  const _HistoryList({required this.bills, required this.today});

  @override
  Widget build(BuildContext context) {
    final colours = Theme.of(context).colorScheme;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colours.surfaceContainerLowest,
        border: Border.all(color: colours.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: <Widget>[
          for (var index = 0; index < bills.length; index++) ...<Widget>[
            _MonthTile(bill: bills[index], today: today),
            if (index < bills.length - 1)
              const Divider(indent: 14, endIndent: 14),
          ],
        ],
      ),
    );
  }
}

class _MonthTile extends StatelessWidget {
  final Bill bill;
  final PhDate today;

  const _MonthTile({required this.bill, required this.today});

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final String status = bill.statusLabelOn(today);
    final Widget row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
              const SizedBox(height: 5),
              _StatusLabel(label: status),
            ],
          ),
          ...<Widget>[
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right,
              size: 18,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ],
        ],
      ),
    );

    return InkWell(
      onTap: () => showConsumerBillDetails(context, bill: bill, today: today),
      child: row,
    );
  }
}

class _StatusLabel extends StatelessWidget {
  final String label;

  const _StatusLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    final ColorScheme colours = Theme.of(context).colorScheme;
    final bool settled =
        label == 'Paid' || label == 'Settled' || label == 'Covered by BOHECO';
    final bool attention =
        label == 'Unpaid' || label == 'Overdue' || label == 'Partially paid';
    final Color foreground = settled
        ? colours.primary
        : attention
        ? colours.error
        : colours.onSurfaceVariant;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: foreground, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: foreground,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
