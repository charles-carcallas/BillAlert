import 'package:flutter/material.dart';
import '../../domain/entities/bill.dart';
import '../../domain/entities/billing_schedule.dart';

class CollectionDeadline extends StatelessWidget {
  const CollectionDeadline({super.key, required this.bill});
  final Bill bill;
  @override
  Widget build(BuildContext context) {
    final cutoff = bill.collectionCutoffAt;
    if (cutoff == null ||
        bill.isUnpriced ||
        bill.isSettled ||
        bill.settlementState != null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        'Pay through Cashier before ${BillingSchedule.formatPhInstant(cutoff)} PH time.',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }
}
