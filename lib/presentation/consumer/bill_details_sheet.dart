import 'package:flutter/material.dart';

import '../../domain/entities/bill.dart';
import '../../domain/value_objects/ph_date.dart';

/// Opens one billing-cycle record without turning it into a payment receipt.
Future<void> showConsumerBillDetails(
  BuildContext context, {
  required Bill bill,
  required PhDate today,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => ConsumerBillDetails(bill: bill, today: today),
);

/// The facts BillAlert has for one bill. No tariff or derived amount appears
/// here: the peso amount is shown only after the cooperative posts it.
class ConsumerBillDetails extends StatelessWidget {
  final Bill bill;
  final PhDate today;

  const ConsumerBillDetails({
    required this.bill,
    required this.today,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colours = Theme.of(context).colorScheme;
    final String status = bill.statusLabelOn(today);
    final bool needsAttention =
        status == 'Unpaid' || status == 'Overdue' || status == 'Partially paid';
    final Color statusColour = needsAttention ? colours.error : colours.primary;

    return FractionallySizedBox(
      heightFactor: 0.82,
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 12, 12),
            child: Row(
              children: <Widget>[
                Expanded(child: Text('Bill details', style: text.titleLarge)),
                IconButton(
                  tooltip: 'Close bill details',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: statusColour.withValues(alpha: 0.11),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        bill.cycle.displayName,
                        style: text.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: statusColour.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          status,
                          style: text.labelLarge?.copyWith(
                            color: statusColour,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                _Fact(label: 'Bill number', value: bill.billNo.value),
                _Fact(label: 'Billing month', value: bill.cycle.displayName),
                _Fact(
                  label: 'Electricity consumed',
                  value: bill.consumption.format(),
                ),
                _Fact(
                  label: 'Amount billed',
                  value: bill.isUnpriced
                      ? 'Not posted yet'
                      : bill.totalAmount!.format(),
                ),
                _Fact(
                  label: 'Due date',
                  value: bill.dueDate == null
                      ? 'Not assigned yet'
                      : _friendlyDate(bill.dueDate!),
                ),
                if (bill.isPayable) ...<Widget>[
                  _Fact(
                    label: 'Payment received',
                    value: bill.amountPaid.format(),
                  ),
                  _Fact(
                    label: 'Remaining balance',
                    value: bill.balance.format(),
                    emphasized: true,
                  ),
                ],
                if (bill.isUnpriced)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: colours.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'The meter reading has been recorded. The cooperative '
                      'has not posted this bill’s peso amount yet.',
                      style: text.bodyMedium,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _friendlyDate(PhDate date) {
    const List<String> months = <String>[
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
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }
}

class _Fact extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasized;

  const _Fact({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(child: Text(label, style: text.bodyMedium)),
          const SizedBox(width: 16),
          Flexible(
            child: Text(
              value,
              style: emphasized
                  ? text.titleMedium?.copyWith(fontWeight: FontWeight.w700)
                  : text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}
