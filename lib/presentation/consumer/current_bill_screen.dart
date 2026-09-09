// ============================================================
// WEEK 11 — START HERE   ·   Consumer · Current Bill (screen)
// Owner: Basio
// Worksheet: docs/week11/worksheets/02_consumer_current_bill.md
//
// PURPOSE
//   Show the consumer their current billing cycle: the reading, the
//   amount (once it arrives), balance, and due date.
//
// WHERE YOU ARE IN THE CHAIN
//   reader → outbox → sync → unpriced bill → admin posts amount
//         → [ THIS FILE ] → consumer sees their bill
//
// CALLS
//   CurrentBillController (presentation/consumer/current_bill_controller.dart)
//   which reads from BillRepository. You never call Supabase from a screen.
//   Importing supabase_flutter here breaks the layering and fails a test.
//
// BEFORE CODING — answer these in the worksheet
//   Q1. Why does the screen show both unpriced AND priced states?
//   Q2. Why is there no hard-coded amount anywhere in this file?
//   Q3. How does the screen know whether the bill is overdue?
//
// DO NOT CHANGE
//   The Bill entity. The Money value object.
//   The read-only nature of this screen — consumers view, they do not edit.
//
// DONE WHEN
//   The unpriced state renders from real data, the bill becomes priced
//   after the Admin posts, and no hard-coded amount appears anywhere.
// ============================================================
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../common/failure_banner.dart';
import '../providers.dart';
import 'current_bill_controller.dart';

class CurrentBillScreen extends ConsumerWidget {
  const CurrentBillScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(currentBillControllerProvider);
    final today = ref.watch(phClockProvider).today();

    return Scaffold(
      appBar: AppBar(title: const Text('My Current Bill')),
      body: RefreshIndicator(
        onRefresh: ref.read(currentBillControllerProvider.notifier).refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (state.failure != null)
              FailureBanner(
                failure: state.failure!,
                onRetry: ref.read(currentBillControllerProvider.notifier).refresh,
              ),
            if (state.isLoading && state.currentBill == null)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32.0),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (state.currentBill == null && !state.isLoading && state.failure == null)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32.0),
                  child: Text(
                    'No bill for the current cycle. Your meter may not have been read yet.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else if (state.currentBill != null) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        state.currentBill!.cycle.displayName,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text('Consumption: ${state.currentBill!.consumption.format()}'),
                      const SizedBox(height: 8),
                      Chip(label: Text(state.currentBill!.statusLabelOn(today))),
                      const SizedBox(height: 16),
                      if (state.currentBill!.isUnpriced)
                        const Text('Amount pending — the cooperative will send it soon.')
                      else ...[
                        Text('Total Amount: ${state.currentBill!.totalAmount!.format()}'),
                        Text('Balance: ${state.currentBill!.balance.format()}'),
                        if (state.currentBill!.dueDate != null)
                          Text('Due Date: ${state.currentBill!.dueDate!.toIso()}'),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'History',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              if (state.history.isEmpty)
                const Text('No past bills found.')
              else
                ...state.history.map((bill) => Card(
                      child: ListTile(
                        title: Text(bill.cycle.displayName),
                        subtitle: Text(bill.statusLabelOn(today)),
                        trailing: Text(bill.balance.format()),
                      ),
                    )),
            ],
          ],
        ),
      ),
    );
  }
}
