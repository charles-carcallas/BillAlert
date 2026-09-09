import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/bill.dart';
import '../../domain/value_objects/money.dart';
import '../../domain/value_objects/ph_date.dart';
import '../common/failure_banner.dart';
import 'post_bill_amount_controller.dart';

class PostBillAmountScreen extends ConsumerWidget {
  const PostBillAmountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(postBillAmountControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Post Bill Amount')),
      body: RefreshIndicator(
        onRefresh: ref.read(postBillAmountControllerProvider.notifier).refresh,
        child: _buildBody(context, state, ref),
      ),
    );
  }

  Widget _buildBody(BuildContext context, PostBillAmountState state, WidgetRef ref) {
    if (state.failure != null && state.billsAwaitingAmount.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FailureBanner(
            failure: state.failure!,
            onRetry: ref.read(postBillAmountControllerProvider.notifier).refresh,
          ),
        ],
      );
    }

    if (state.isLoading && state.billsAwaitingAmount.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.billsAwaitingAmount.isEmpty) {
      return const Center(
        child: Text('No unpriced bills found.'),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: state.billsAwaitingAmount.length + (state.failure != null ? 1 : 0),
      itemBuilder: (context, index) {
        if (state.failure != null && index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: FailureBanner(failure: state.failure!),
          );
        }

        final billIndex = state.failure != null ? index - 1 : index;
        final bill = state.billsAwaitingAmount[billIndex];
        return _BillAmountCard(bill: bill, isSubmitting: state.isSubmitting);
      },
    );
  }
}

class _BillAmountCard extends ConsumerStatefulWidget {
  final Bill bill;
  final bool isSubmitting;

  const _BillAmountCard({required this.bill, required this.isSubmitting});

  @override
  ConsumerState<_BillAmountCard> createState() => _BillAmountCardState();
}

class _BillAmountCardState extends ConsumerState<_BillAmountCard> {
  final _amountController = TextEditingController();
  final _dueDateController = TextEditingController();

  @override
  void dispose() {
    _amountController.dispose();
    _dueDateController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final amountText = _amountController.text;
    final dueDateText = _dueDateController.text;

    final amount = Money.tryParse(amountText);
    if (amount == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid amount. Please use numbers.')),
      );
      return;
    }

    final dueDate = PhDate.tryParse(dueDateText);
    if (dueDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid date. Use YYYY-MM-DD.')),
      );
      return;
    }

    await ref.read(postBillAmountControllerProvider.notifier).postAmount(
      widget.bill,
      amount,
      dueDate,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Bill No: ${widget.bill.billNo.value}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text('Cycle: ${widget.bill.cycle.displayName}'),
            Text('Consumption: ${widget.bill.consumption.format()}'),
            const SizedBox(height: 16),
            TextField(
              controller: _amountController,
              decoration: const InputDecoration(
                labelText: 'Amount (₱)',
                hintText: 'e.g. 1975.35',
                border: OutlineInputBorder(),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              enabled: !widget.isSubmitting,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _dueDateController,
              decoration: const InputDecoration(
                labelText: 'Due Date',
                hintText: 'YYYY-MM-DD',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.datetime,
              enabled: !widget.isSubmitting,
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton(
                onPressed: widget.isSubmitting ? null : _submit,
                child: const Text('Post Amount'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
