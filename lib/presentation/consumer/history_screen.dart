import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/entities/bill.dart';
import '../../domain/value_objects/ph_date.dart';
import '../common/failure_banner.dart';
import '../providers.dart';
import '../router.dart';
import 'consumer_app_bar.dart';
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
    final List<Bill> availableBills = _view == _HistoryView.payments
        ? state.bills
              .where(
                (Bill bill) => state.receiptByBillId[bill.id.value] != null,
              )
              .toList()
        : List<Bill>.of(state.bills);
    final String query = _searchController.text.trim().toLowerCase();
    final List<Bill> visibleBills =
        availableBills.where((Bill bill) {
          if (query.isEmpty) return true;
          if (bill.cycle.displayName.toLowerCase().contains(query)) return true;
          if (_view == _HistoryView.payments) {
            final String? receiptNo = state.receiptByBillId[bill.id.value];
            return receiptNo?.toLowerCase().contains(query) ?? false;
          }
          return false;
        }).toList()..sort(
          (Bill a, Bill b) => _dateOrder == _DateOrder.newestFirst
              ? b.cycle.compareTo(a.cycle)
              : a.cycle.compareTo(b.cycle),
        );

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
                    width: 142,
                    child: DropdownButtonFormField<_DateOrder>(
                      initialValue: _dateOrder,
                      decoration: const InputDecoration(
                        labelText: 'Sort by date',
                      ),
                      items: const <DropdownMenuItem<_DateOrder>>[
                        DropdownMenuItem<_DateOrder>(
                          value: _DateOrder.newestFirst,
                          child: Text('Newest'),
                        ),
                        DropdownMenuItem<_DateOrder>(
                          value: _DateOrder.oldestFirst,
                          child: Text('Oldest'),
                        ),
                      ],
                      onChanged: (_DateOrder? value) {
                        if (value != null) setState(() => _dateOrder = value);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (state.failure != null) ...<Widget>[
                FailureBanner(
                  failure: state.failure!,
                  onRetry: controller.load,
                ),
                const SizedBox(height: 12),
              ],

              if (state.isLoading && state.bills.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (visibleBills.isEmpty && state.failure == null)
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
                        query.isNotEmpty
                            ? 'No matching records.'
                            : _view == _HistoryView.payments
                            ? 'No payments yet.'
                            : 'No bills yet.',
                        style: text.titleMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        query.isNotEmpty
                            ? 'Try another month or receipt number.'
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
              else
                _HistoryList(
                  bills: visibleBills,
                  today: today,
                  receiptByBillId: state.receiptByBillId,
                  view: _view,
                ),
            ],
          ),
        ),
      ),
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
  final Map<String, String> receiptByBillId;
  final _HistoryView view;

  const _HistoryList({
    required this.bills,
    required this.today,
    required this.receiptByBillId,
    required this.view,
  });

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
            _MonthTile(
              bill: bills[index],
              today: today,
              receiptNo: receiptByBillId[bills[index].id.value],
              view: view,
            ),
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
  final String? receiptNo;
  final _HistoryView view;

  const _MonthTile({
    required this.bill,
    required this.today,
    required this.view,
    this.receiptNo,
  });

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
                  view == _HistoryView.payments
                      ? 'OR $receiptNo'
                      : '${bill.billNo.value} · '
                            '${bill.consumption.format()}',
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
          if (receiptNo != null) ...<Widget>[
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

    // Only a settled month has a receipt to open. The rest are ordinary list
    // rows rather than controls that lead nowhere.
    return receiptNo == null
        ? row
        : InkWell(
            onTap: () => context.push(Routes.consumerReceiptFor(receiptNo!)),
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
    final bool settled = label == 'Paid' || label == 'Settled';
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
