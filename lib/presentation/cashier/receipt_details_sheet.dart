import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/repositories/payment_repository.dart';
import '../../domain/value_objects/ph_date.dart';

/// Opens the complete server-issued receipt without leaving the Cashier tab.
Future<void> showCashierReceiptDetails(
  BuildContext context,
  PaymentSummary receipt,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => CashierReceiptDetails(receipt: receipt),
);

/// The facts from one cash handover, as returned by `v_payment_history`.
class CashierReceiptDetails extends StatelessWidget {
  final PaymentSummary receipt;

  const CashierReceiptDetails({required this.receipt, super.key});

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colours = Theme.of(context).colorScheme;

    return FractionallySizedBox(
      heightFactor: 0.9,
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 12, 12),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text('Receipt details', style: text.titleLarge),
                ),
                IconButton(
                  tooltip: 'Close receipt',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: colours.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: <Widget>[
                      Icon(Icons.verified, color: colours.primary, size: 32),
                      const SizedBox(height: 8),
                      Text(
                        'OFFICIAL DIGITAL RECEIPT',
                        style: text.labelMedium?.copyWith(
                          color: colours.primary,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.7,
                        ),
                      ),
                      const SizedBox(height: 4),
                      SelectableText(
                        receipt.receiptNo,
                        style: text.titleLarge,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                _Fact(label: 'Consumer', value: receipt.consumerName),
                _Fact(label: 'Date and time', value: _stamp(receipt.paidAt)),
                _Fact(
                  label: 'Verification code',
                  value: receipt.verificationCode,
                  selectable: true,
                ),
                const Divider(height: 28),
                Text('Bills settled', style: text.titleMedium),
                const SizedBox(height: 10),
                for (final SettledBill bill in receipt.bills)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _AmountLine(
                      label: bill.cycleLabel.isEmpty
                          ? bill.billNo.value
                          : bill.cycleLabel,
                      value: bill.amountPaid.format(),
                    ),
                  ),
                const Divider(height: 24),
                _AmountLine(
                  label: 'Total paid',
                  value: receipt.totalCollected.format(),
                  emphasized: true,
                ),
                if (receipt.cashTendered != null) ...<Widget>[
                  const SizedBox(height: 10),
                  _AmountLine(
                    label: 'Cash received',
                    value: receipt.cashTendered!.format(),
                  ),
                ],
                if (receipt.changeDue != null) ...<Widget>[
                  const SizedBox(height: 10),
                  _AmountLine(
                    label: 'Change',
                    value: receipt.changeDue!.format(),
                  ),
                ],
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            decoration: BoxDecoration(
              color: colours.surface,
              border: Border(top: BorderSide(color: colours.outlineVariant)),
            ),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _copy(context),
                icon: const Icon(Icons.copy_outlined),
                label: const Text('Copy receipt details'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _copy(BuildContext context) async {
    final String bills = receipt.bills
        .map(
          (SettledBill bill) =>
              '${bill.cycleLabel.isEmpty ? bill.billNo.value : bill.cycleLabel}: '
              '${bill.amountPaid.format()}',
        )
        .join('\n');
    await Clipboard.setData(
      ClipboardData(
        text:
            'BillAlert receipt ${receipt.receiptNo}\n'
            '${receipt.consumerName}\n'
            '${_stamp(receipt.paidAt)}\n'
            '$bills\n'
            'Total paid: ${receipt.totalCollected.format()}\n'
            'Verification: ${receipt.verificationCode}',
      ),
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Receipt details copied.')));
  }

  static String _stamp(DateTime instant) {
    final PhDate day = PhDate.at(instant);
    final DateTime manila = instant.toUtc().add(PhDate.utcOffset);
    final int hour24 = manila.hour;
    final int hour = hour24 % 12 == 0 ? 12 : hour24 % 12;
    final String minute = manila.minute.toString().padLeft(2, '0');
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
    return '${day.day} ${months[day.month - 1]} ${day.year}, '
        '$hour:$minute ${hour24 < 12 ? 'AM' : 'PM'}';
  }
}

class _Fact extends StatelessWidget {
  final String label;
  final String value;
  final bool selectable;

  const _Fact({
    required this.label,
    required this.value,
    this.selectable = false,
  });

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: text.bodySmall),
          const SizedBox(height: 2),
          if (selectable)
            SelectableText(value, style: text.bodyLarge)
          else
            Text(value, style: text.bodyLarge),
        ],
      ),
    );
  }
}

class _AmountLine extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasized;

  const _AmountLine({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  @override
  Widget build(BuildContext context) {
    final TextStyle? style = emphasized
        ? Theme.of(context).textTheme.titleMedium
        : Theme.of(context).textTheme.bodyLarge;
    return Row(
      children: <Widget>[
        Expanded(child: Text(label, style: style)),
        const SizedBox(width: 12),
        Text(value, style: style),
      ],
    );
  }
}
