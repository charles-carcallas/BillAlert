import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/bill.dart';
import '../../domain/repositories/bill_repository.dart';
import '../../domain/repositories/payment_repository.dart';
import '../../domain/value_objects/money.dart';
import '../common/failure_banner.dart';
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

    return Scaffold(
      appBar: AppBar(
        title: Text(state.selected == null ? 'Payment' : 'Take payment'),
        leading: state.selected == null
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Choose another household',
                onPressed: controller.startNewPayment,
              ),
      ),
      body: SafeArea(
        child: state.selected == null
            ? _HouseholdPicker(state: state, controller: controller)
            : _PaymentForm(state: state, controller: controller),
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

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            onChanged: controller.search,
            decoration: const InputDecoration(
              hintText: 'Search by name or consumer number',
              prefixIcon: Icon(Icons.search),
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
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (BuildContext context, int index) {
                          final ConsumerOutstanding c = visible[index];
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(c.consumerName, style: text.titleMedium),
                            subtitle: Text(
                              '${c.consumerNo.value} · '
                              '${_billsPhrase(c)}'
                              '${c.overdueCount > 0 ? ' · ${c.overdueCount} overdue' : ''}',
                              style: text.bodySmall,
                            ),
                            trailing: Text(
                              c.totalOutstanding.format(),
                              style: text.titleMedium,
                            ),
                            // A household whose only readings are unpriced has
                            // nothing collectable, so it cannot be opened.
                            enabled: c.hasPayableBills,
                            onTap: () => controller.selectHousehold(c),
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

/// Choose the months, take the cash.
class _PaymentForm extends StatelessWidget {
  final RecordPaymentState state;
  final RecordPaymentController controller;

  const _PaymentForm({required this.state, required this.controller});

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ConsumerOutstanding household = state.selected!;

    return Column(
      children: <Widget>[
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            children: <Widget>[
              Text(household.consumerName, style: text.titleLarge),
              Text(household.consumerNo.value, style: text.bodySmall),

              if (state.failure != null) ...<Widget>[
                const SizedBox(height: 12),
                FailureBanner(failure: state.failure!),
              ],

              const SizedBox(height: 16),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text('Unpaid months', style: text.titleSmall),
                  ),
                  if (state.payableBills.length > 1)
                    TextButton(
                      onPressed: controller.selectAll,
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
                for (final Bill bill in state.payableBills)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: state.selectedBillIds.contains(bill.id.value),
                    onChanged: state.isSubmitting
                        ? null
                        : (bool? on) => controller.toggleBill(bill, on ?? false),
                    title: Text(bill.cycle.displayName),
                    subtitle: Text(
                      '${bill.billNo.value} · due '
                      '${bill.dueDate?.toIso() ?? 'not set'}',
                      style: text.bodySmall,
                    ),
                    secondary: Text(
                      bill.balance.format(),
                      style: text.titleMedium,
                    ),
                  ),

              const SizedBox(height: 20),
              Text('Cash received', style: text.titleSmall),
              const SizedBox(height: 6),
              TextField(
                enabled: !state.isSubmitting,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                decoration: const InputDecoration(
                  prefixText: '₱ ',
                  hintText: 'Leave empty if not recording cash',
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
      elevation: 0,
      color: colours.surfaceContainerHighest,
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
              FilledButton(
                onPressed: state.canConfirm ? controller.confirm : null,
                child: state.isSubmitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        count == 0
                            ? 'Record payment'
                            : 'Record ${state.total.format()}',
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
      appBar: AppBar(title: const Text('Receipt issued')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: <Widget>[
            Icon(Icons.check_circle, size: 44, color: colours.primary),
            const SizedBox(height: 12),
            Center(
              child: Text(receipt.receiptNo, style: text.headlineMedium),
            ),
            Center(
              child: Text(
                'Verification ${receipt.verificationCode}',
                style: text.bodySmall,
              ),
            ),
            const SizedBox(height: 20),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
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
                      _Line(
                        label: 'Change',
                        value: receipt.changeDue!.format(),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),
            FilledButton(
              onPressed: onNewPayment,
              child: const Text('Take another payment'),
            ),
          ],
        ),
      ),
    );
  }
}
