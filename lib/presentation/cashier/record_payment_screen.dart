// ============================================================
// WEEK 11 — START HERE   ·   Cashier · Record Payment (screen)
// Owner: Obiso
// Worksheet: docs/week11/worksheets/03_cashier_record_payment.md
//
// PURPOSE
//   Take cash across the counter for one or more outstanding bills.
//
// WHERE YOU ARE IN THE CHAIN
//   login → reading → outbox → sync → unpriced bill → post amount
//         → consumer sees amount → [ THIS FILE ] → receipt
//
// CALLS
//   RecordCashPayment (domain/usecases/cashier/record_cash_payment.dart)
//   which reaches fn_record_payment. You never call Supabase from a screen.
//   Importing supabase_flutter here breaks the layering and fails a test.
//
// BEFORE CODING — answer these in the worksheet
//   Q1. Why is one handover one receipt, rather than one receipt per bill?
//   Q2. Why can an unpriced bill never appear in this list?
//   Q3. What stops a double-tap on Confirm from recording two payments?
//
// DO NOT CHANGE
//   The RecordCashPayment use case. The Money value object.
//   The one-call-settles-all shape of fn_record_payment.
//
// DONE WHEN
//   Two or more real bills settle in one payment, one receipt number is
//   produced, and the row is visible in payment_transactions in Supabase.
// ============================================================
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../common/failure_banner.dart';
import 'record_payment_controller.dart';

class RecordPaymentScreen extends ConsumerWidget {
  const RecordPaymentScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(recordPaymentControllerProvider);
    final controller = ref.read(recordPaymentControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Record Payment'),
        leading: state.selectedConsumer != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: controller.clearSelection,
              )
            : null,
      ),
      body: state.selectedConsumer == null
          ? _buildSearch(context, state, controller)
          : _buildPayment(context, state, controller),
    );
  }

  Widget _buildSearch(BuildContext context, RecordPaymentState state, RecordPaymentController controller) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          TextField(
            decoration: const InputDecoration(
              labelText: 'Search Consumer',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
            onChanged: controller.searchConsumers,
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.builder(
              itemCount: state.searchResults.length,
              itemBuilder: (context, index) {
                final consumer = state.searchResults[index];
                return ListTile(
                  title: Text(consumer.fullName),
                  subtitle: Text(consumer.consumerNo.value),
                  onTap: () => controller.selectConsumer(consumer),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPayment(BuildContext context, RecordPaymentState state, RecordPaymentController controller) {
    if (state.receiptNumber != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 64),
            const SizedBox(height: 16),
            Text('Payment Recorded', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text('Receipt: ${state.receiptNumber}', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: controller.clearSelection,
              child: const Text('New Payment'),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        if (state.failure != null)
          FailureBanner(failure: state.failure!),
        ListTile(
          title: Text(state.selectedConsumer!.fullName),
          subtitle: Text(state.selectedConsumer!.consumerNo.value),
          tileColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        Expanded(
          child: state.isFetchingBills
              ? const Center(child: CircularProgressIndicator())
              : state.payableBills.isEmpty
                  ? const Center(child: Text('No outstanding bills.'))
                  : ListView.builder(
                      itemCount: state.payableBills.length,
                      itemBuilder: (context, index) {
                        final bill = state.payableBills[index];
                        return CheckboxListTile(
                          title: Text(bill.cycle.displayName),
                          subtitle: Text('Balance: ${bill.balance.format()}'),
                          value: state.selectedBillIds.contains(bill.id.value),
                          onChanged: (selected) => controller.toggleBill(bill, selected ?? false),
                        );
                      },
                    ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Total: ${state.totalSelected.format()}',
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.end,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: state.selectedBillIds.isEmpty || state.isSubmitting
                      ? null
                      : controller.confirmPayment,
                  child: state.isSubmitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Confirm Payment'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
