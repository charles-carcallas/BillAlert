import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/bill.dart';
import '../../domain/repositories/bill_repository.dart';
import '../../domain/repositories/payment_repository.dart';
import '../../domain/value_objects/money.dart';
import '../../domain/value_objects/ph_date.dart';
import '../common/failure_banner.dart';
import '../common/staff_app_bar.dart';
import '../providers.dart';
import 'record_payment_controller.dart';

/// FR-30 — Cashier › Payment.
///
/// Three states, in order: find the household, choose the months and take the
/// cash, then hand over the receipt.
///
/// One handover is ONE receipt, however many months it settles. That is not a
/// display choice - `fn_record_payment` takes the bill ids and the amounts as
/// parallel lists and settles them in a single transaction, and this screen
/// makes exactly one call. Nothing here loops over bills issuing payments.
///
/// The receipt number is never invented here. It is minted by the server from
/// a sequence and read back afterwards; until it arrives the screen says the
/// payment is queued, which is the truth.
class RecordPaymentScreen extends ConsumerWidget {
  const RecordPaymentScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(recordPaymentControllerProvider);
    final controller = ref.read(recordPaymentControllerProvider.notifier);

    final PaymentSummary? receipt = state.receipt;
    if (receipt != null) {
      return _ReceiptIssued(
        receipt: receipt,
        onNewPayment: controller.startNewPayment,
      );
    }

    final bool choosingHousehold = state.selected == null;
    return Scaffold(
      appBar: choosingHousehold
          ? const StaffAppBar(title: 'Consumers')
          : AppBar(
              title: const Text('Take payment'),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Choose another household',
                onPressed: controller.startNewPayment,
              ),
            ),
      body: SafeArea(
        child: choosingHousehold
            ? _HouseholdPicker(state: state, controller: controller)
            : _PaymentForm(
                state: state,
                controller: controller,
                today: ref.watch(phClockProvider).today(),
              ),
      ),
    );
  }
}

/// CSH-02 — who is at the counter.
class _HouseholdPicker extends StatelessWidget {
  final RecordPaymentState state;
  final RecordPaymentController controller;

  const _HouseholdPicker({required this.state, required this.controller});

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final List<ConsumerOutstanding> visible = state.visibleHouseholds;
    final Money total = state.households.fold(
      Money.zero,
      (Money sum, ConsumerOutstanding item) => sum + item.totalOutstanding,
    );
    final int payable = state.households
        .where((ConsumerOutstanding item) => item.hasPayableBills)
        .length;

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            onChanged: controller.search,
            decoration: const InputDecoration(
              hintText: 'Search name or account number',
              prefixIcon: Icon(Icons.search),
            ),
          ),
        ),
        if (state.households.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '$payable consumer${payable == 1 ? '' : 's'} with payable '
                'bills · ${total.format()} outstanding',
                style: text.bodySmall,
              ),
            ),
          ),
        if (state.failure != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: FailureBanner(
              failure: state.failure!,
              onRetry: controller.loadHouseholds,
            ),
          ),
        Expanded(
          child: state.isLoadingHouseholds && state.households.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : visible.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      state.households.isEmpty
                          ? 'Nobody in this area has an unpaid bill.'
                          : 'No household matches that search.',
                      style: text.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: controller.loadHouseholds,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: visible.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (BuildContext context, int index) {
                      final ConsumerOutstanding c = visible[index];
                      return _HouseholdTile(
                        household: c,
                        onTap: c.hasPayableBills
                            ? () => controller.selectHousehold(c)
                            : null,
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  static String _billsPhrase(ConsumerOutstanding c) {
    if (!c.hasPayableBills) {
      return c.unpricedBillCount > 0
          ? 'awaiting an amount'
          : 'nothing outstanding';
    }
    final String bills =
        '${c.payableBillCount} bill${c.payableBillCount == 1 ? '' : 's'}';
    return c.unpricedBillCount > 0
        ? '$bills · ${c.unpricedBillCount} awaiting an amount'
        : bills;
  }
}

class _HouseholdTile extends StatelessWidget {
  final ConsumerOutstanding household;
  final VoidCallback? onTap;

  const _HouseholdTile({required this.household, this.onTap});

  @override
  Widget build(BuildContext context) {
    final ColorScheme colours = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;
    final bool overdue = household.overdueCount > 0;
    final Color accent = overdue ? const Color(0xFFB85C00) : colours.primary;

    return Material(
      color: overdue ? const Color(0xFFFFF8EE) : colours.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: overdue ? const Color(0xFFF0C58E) : colours.outlineVariant,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: IntrinsicHeight(
          child: Row(
            children: <Widget>[
              Container(width: 4, color: accent),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(13, 13, 8, 13),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              household.consumerName,
                              style: text.titleMedium,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            household.totalOutstanding.format(),
                            style: text.titleMedium?.copyWith(
                              color: overdue ? accent : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        <String>[
                          household.consumerNo.value,
                          if (household.purok?.trim().isNotEmpty ?? false)
                            household.purok!.trim(),
                        ].join(' · '),
                        style: text.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              _HouseholdPicker._billsPhrase(household),
                              style: text.bodySmall,
                            ),
                          ),
                          if (overdue)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFE6C6),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                '${household.overdueCount} overdue',
                                style: text.labelSmall?.copyWith(
                                  color: accent,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.chevron_right,
                            size: 20,
                            color: onTap == null
                                ? colours.outline
                                : colours.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Choose the months, take the cash.
class _PaymentForm extends StatelessWidget {
  final RecordPaymentState state;
  final RecordPaymentController controller;
  final PhDate today;

  const _PaymentForm({
    required this.state,
    required this.controller,
    required this.today,
  });

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colours = Theme.of(context).colorScheme;
    final ConsumerOutstanding household = state.selected!;

    return Column(
      children: <Widget>[
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: colours.surfaceContainerLowest,
                  border: Border.all(color: colours.outlineVariant),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'PAYING',
                      style: text.labelSmall?.copyWith(
                        color: colours.primary,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.7,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(household.consumerName, style: text.titleLarge),
                    Text(
                      <String>[
                        household.consumerNo.value,
                        if (household.purok?.trim().isNotEmpty ?? false)
                          household.purok!.trim(),
                      ].join(' · '),
                      style: text.bodySmall,
                    ),
                  ],
                ),
              ),

              if (state.failure != null) ...<Widget>[
                const SizedBox(height: 12),
                FailureBanner(failure: state.failure!),
              ],

              const SizedBox(height: 20),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text('OUTSTANDING BILLS', style: text.labelMedium),
                        Text('Tap a bill to select it', style: text.bodySmall),
                      ],
                    ),
                  ),
                  if (state.payableBills.length > 1)
                    TextButton(
                      onPressed: state.isSubmitting
                          ? null
                          : controller.selectAll,
                      child: const Text('Select all'),
                    ),
                ],
              ),
              const SizedBox(height: 4),

              if (state.isLoadingBills)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (state.payableBills.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'Nothing to collect. Any reading for this household is '
                    'still waiting for its amount from the cooperative.',
                    style: text.bodyMedium,
                  ),
                )
              else
                for (final Bill bill in state.payableBills) ...<Widget>[
                  _BillSelectionTile(
                    bill: bill,
                    today: today,
                    selected: state.selectedBillIds.contains(bill.id.value),
                    onTap: state.isSubmitting
                        ? null
                        : () => controller.toggleBill(
                            bill,
                            !state.selectedBillIds.contains(bill.id.value),
                          ),
                  ),
                  const SizedBox(height: 8),
                ],

              const SizedBox(height: 14),
              Text('CASH RECEIVED', style: text.labelMedium),
              const SizedBox(height: 6),
              TextField(
                enabled: !state.isSubmitting,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                decoration: const InputDecoration(
                  prefixText: '₱ ',
                  hintText: 'Enter cash received',
                ),
                onChanged: controller.setCashTendered,
              ),
            ],
          ),
        ),
        _Totals(state: state, controller: controller),
      ],
    );
  }
}

class _BillSelectionTile extends StatelessWidget {
  final Bill bill;
  final PhDate today;
  final bool selected;
  final VoidCallback? onTap;

  const _BillSelectionTile({
    required this.bill,
    required this.today,
    required this.selected,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme colours = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;
    final bool overdue = bill.isOverdueOn(today);
    return Material(
      color: selected
          ? colours.primary.withValues(alpha: 0.08)
          : colours.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: selected ? colours.primary : colours.outlineVariant,
          width: selected ? 1.5 : 1,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Row(
            children: <Widget>[
              AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                height: 24,
                width: 24,
                decoration: BoxDecoration(
                  color: selected ? colours.primary : Colors.transparent,
                  border: Border.all(
                    color: selected ? colours.primary : colours.outline,
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: selected
                    ? Icon(Icons.check, size: 17, color: colours.onPrimary)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(bill.cycle.displayName, style: text.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      '${overdue ? 'Overdue' : 'Due'} · '
                      '${bill.dueDate?.toIso() ?? 'date not set'} · '
                      '${bill.billNo.value}',
                      style: text.bodySmall?.copyWith(
                        color: overdue ? colours.error : null,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(bill.balance.format(), style: text.titleMedium),
            ],
          ),
        ),
      ),
    );
  }
}

/// The running total, the change, and the one button that records it.
class _Totals extends StatelessWidget {
  final RecordPaymentState state;
  final RecordPaymentController controller;

  const _Totals({required this.state, required this.controller});

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colours = Theme.of(context).colorScheme;
    final Money? change = state.change;
    final int count = state.selectedBills.length;

    return Material(
      color: colours.surface,
      child: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: colours.outlineVariant)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _Line(
                  label: count == 0
                      ? 'Total'
                      : 'Total · $count month${count == 1 ? '' : 's'}',
                  value: state.total.format(),
                  emphasise: true,
                ),
                if (state.cashTendered != null) ...<Widget>[
                  const SizedBox(height: 4),
                  _Line(
                    label: 'Cash received',
                    value: state.cashTendered!.format(),
                  ),
                  const SizedBox(height: 4),
                  _Line(
                    label: 'Change',
                    value: change == null ? 'short' : change.format(),
                  ),
                ],
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: state.canConfirm ? controller.confirm : null,
                  icon: state.isSubmitting
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.payments_outlined),
                  label: Text(
                    count == 0
                        ? 'Select a bill to continue'
                        : 'Confirm cash payment · ${state.total.format()}',
                  ),
                ),
                if (state.queuedOffline) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    'Saved on this phone. The receipt number is issued when it '
                    'reaches the server.',
                    style: text.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasise;

  const _Line({
    required this.label,
    required this.value,
    this.emphasise = false,
  });

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final TextStyle? style = emphasise ? text.titleLarge : text.bodyMedium;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Text(label, style: emphasise ? text.titleMedium : text.bodyMedium),
        Text(value, style: style),
      ],
    );
  }
}

/// CSH-04 — the official receipt, as the server issued it.
///
/// One receipt for the whole handover, listing every month it settled. The
/// same OR number appearing against three months is the correct behaviour,
/// not a bug: the consumer handed over money once.
class _ReceiptIssued extends StatelessWidget {
  final PaymentSummary receipt;
  final VoidCallback onNewPayment;

  const _ReceiptIssued({required this.receipt, required this.onNewPayment});

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colours = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Receipt issued'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Copy receipt details',
            icon: const Icon(Icons.copy_outlined),
            onPressed: () => _copyReceipt(context),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colours.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: <Widget>[
                  Icon(Icons.check_circle, color: colours.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text('Payment recorded', style: text.titleSmall),
                        Text(
                          'The official receipt is ready.',
                          style: text.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: colours.surfaceContainerLowest,
                border: Border.all(color: colours.outlineVariant),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    'BILLALERT',
                    style: text.labelMedium?.copyWith(
                      color: colours.primary,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  Text(
                    'OFFICIAL DIGITAL RECEIPT',
                    style: text.labelSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    receipt.receiptNo,
                    style: text.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  Text(
                    'Verification ${receipt.verificationCode}',
                    style: text.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                  const Divider(height: 28),
                  _Line(label: 'Consumer', value: receipt.consumerName),
                  const SizedBox(height: 14),
                  Text(
                    'Settled ${receipt.billCount} '
                    'month${receipt.billCount == 1 ? '' : 's'}',
                    style: text.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  for (final SettledBill bill in receipt.bills)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: _Line(
                        label: bill.cycleLabel.isEmpty
                            ? bill.billNo.value
                            : bill.cycleLabel,
                        value: bill.amountPaid.format(),
                      ),
                    ),
                  const Divider(),
                  _Line(
                    label: 'Total paid',
                    value: receipt.totalCollected.format(),
                    emphasise: true,
                  ),
                  if (receipt.cashTendered != null) ...<Widget>[
                    const SizedBox(height: 4),
                    _Line(
                      label: 'Cash received',
                      value: receipt.cashTendered!.format(),
                    ),
                  ],
                  if (receipt.changeDue != null) ...<Widget>[
                    const SizedBox(height: 4),
                    _Line(label: 'Change', value: receipt.changeDue!.format()),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 20),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _copyReceipt(context),
                    icon: const Icon(Icons.copy_outlined),
                    label: const Text('Copy details'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: onNewPayment,
                    child: const Text('Next customer'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _copyReceipt(BuildContext context) async {
    await Clipboard.setData(
      ClipboardData(
        text: <String>[
          'BillAlert receipt ${receipt.receiptNo}',
          receipt.consumerName,
          'Paid: ${receipt.totalCollected.format()}',
          'Verification: ${receipt.verificationCode}',
        ].join('\n'),
      ),
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Receipt details copied.')));
  }
}
