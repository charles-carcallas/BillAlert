import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Consumer;

import '../../core/errors/app_failure.dart';
import '../../core/result/result.dart';
import '../../domain/entities/consumer.dart';
import '../../domain/repositories/payment_repository.dart';
import '../../domain/value_objects/ph_date.dart';
import '../common/failure_banner.dart';
import '../providers.dart';

/// The household's own copy of one receipt, looked up by its number.
final consumerReceiptProvider = FutureProvider.family<PaymentSummary?, String>((
  Ref ref,
  String receiptNo,
) async {
  final consumerResult = await ref
      .watch(consumerRepositoryProvider)
      .signedInConsumer();

  final Consumer? me = switch (consumerResult) {
    Ok(:final value) => value,
    Err(:final failure) => throw failure,
  };

  if (me == null) {
    throw const PermissionFailure(
      'This is a household receipt, and the account you are signed in with '
      'is not attached to one.',
    );
  }

  final result = await ref.watch(paymentRepositoryProvider).historyFor(me.id);
  final List<PaymentSummary> receipts = switch (result) {
    Ok(:final value) => value,
    Err(:final failure) => throw failure,
  };

  for (final PaymentSummary receipt in receipts) {
    if (receipt.receiptNo == receiptNo) return receipt;
  }
  return null;
});

/// CON-03 — one official digital receipt for one cash handover.
class ConsumerReceiptScreen extends ConsumerWidget {
  final String receiptNo;

  const ConsumerReceiptScreen({required this.receiptNo, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final receipt = ref.watch(consumerReceiptProvider(receiptNo));

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        centerTitle: true,
        leading: IconButton(
          tooltip: 'Close receipt',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.close),
        ),
        title: const Text('Receipt'),
      ),
      body: SafeArea(
        child: receipt.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (Object error, StackTrace _) => Padding(
            padding: const EdgeInsets.all(16),
            child: FailureBanner(
              failure: error is AppFailure
                  ? error
                  : ServerFailure(ServerFailure.defaultMessage, '$error'),
              onRetry: () => ref.invalidate(consumerReceiptProvider(receiptNo)),
            ),
          ),
          data: (PaymentSummary? found) => found == null
              ? _NotFound(receiptNo: receiptNo)
              : _Receipt(receipt: found),
        ),
      ),
    );
  }
}

class _NotFound extends StatelessWidget {
  final String receiptNo;

  const _NotFound({required this.receiptNo});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.receipt_long_outlined,
              size: 42,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              'Receipt not found',
              style: text.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              'No receipt $receiptNo is available for this household.',
              style: text.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _Receipt extends StatelessWidget {
  final PaymentSummary receipt;

  const _Receipt({required this.receipt});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colours = Theme.of(context).colorScheme;

    return Column(
      children: <Widget>[
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: colours.surfaceContainerLowest,
                  border: Border.all(color: colours.outlineVariant),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                      child: Column(
                        children: <Widget>[
                          Container(
                            height: 44,
                            width: 44,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: colours.primary,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.bolt,
                              color: colours.onPrimary,
                              size: 25,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Bohol I Electric Cooperative',
                            style: text.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 5),
                          Text(
                            'OFFICIAL DIGITAL RECEIPT',
                            style: text.labelSmall?.copyWith(
                              color: colours.primary,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.7,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      color: colours.primary.withValues(alpha: 0.15),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          Icon(
                            Icons.check_circle,
                            color: colours.primary,
                            size: 22,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'SETTLED',
                            style: text.titleSmall?.copyWith(
                              color: colours.primary,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _ReceiptSection(
                      children: <Widget>[
                        _Fact(term: 'Receipt no.', value: receipt.receiptNo),
                        const SizedBox(height: 14),
                        _Fact(
                          term: 'Date & time',
                          value: _stamp(receipt.paidAt),
                        ),
                        const SizedBox(height: 14),
                        _Fact(
                          term: 'Account holder',
                          value: receipt.consumerName,
                        ),
                      ],
                    ),
                    _ReceiptSection(
                      children: <Widget>[
                        Text(
                          'BILLS SETTLED',
                          style: text.labelMedium?.copyWith(
                            color: colours.onSurfaceVariant,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 10),
                        for (final SettledBill bill in receipt.bills)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 9),
                            child: _Line(
                              label: bill.cycleLabel.isEmpty
                                  ? bill.billNo.value
                                  : bill.cycleLabel,
                              value: bill.amountPaid.format(),
                            ),
                          ),
                        const Divider(),
                        const SizedBox(height: 5),
                        _Line(
                          label: 'Total paid',
                          value: receipt.totalCollected.format(),
                          emphasized: true,
                        ),
                        if (receipt.cashTendered != null ||
                            receipt.changeDue != null) ...<Widget>[
                          const SizedBox(height: 9),
                          Row(
                            children: <Widget>[
                              if (receipt.cashTendered != null)
                                Expanded(
                                  child: Text(
                                    'Cash tendered '
                                    '${receipt.cashTendered!.format()}',
                                    style: text.bodySmall,
                                  ),
                                ),
                              if (receipt.changeDue != null)
                                Text(
                                  'Change ${receipt.changeDue!.format()}',
                                  style: text.bodySmall,
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                    _ReceiptSection(
                      children: <Widget>[
                        Text(
                          'Present this code at the counter to verify',
                          style: text.bodySmall,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 16,
                          ),
                          decoration: BoxDecoration(
                            color: colours.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: SelectableText(
                            receipt.verificationCode,
                            style: text.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.7,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.all(14),
                      child: Text(
                        'This digital receipt is issued in place of a printed '
                        'one and is valid proof of payment.',
                        style: text.labelSmall,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: BoxDecoration(
            color: colours.surface,
            border: Border(top: BorderSide(color: colours.outlineVariant)),
          ),
          child: SafeArea(
            top: false,
            child: FilledButton.icon(
              onPressed: () async {
                await Clipboard.setData(
                  ClipboardData(text: _copyText(receipt)),
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Receipt details copied.')),
                  );
                }
              },
              icon: const Icon(Icons.copy_outlined),
              label: const Text('Copy receipt details'),
            ),
          ),
        ),
      ],
    );
  }

  static String _copyText(PaymentSummary receipt) {
    final bills = receipt.bills
        .map((bill) => '${bill.cycleLabel}: ${bill.amountPaid.format()}')
        .join('\n');
    return 'Bohol I Electric Cooperative\n'
        'Receipt ${receipt.receiptNo}\n'
        '${_stamp(receipt.paidAt)}\n'
        '$bills\n'
        'Total paid: ${receipt.totalCollected.format()}\n'
        'Verification: ${receipt.verificationCode}';
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

class _ReceiptSection extends StatelessWidget {
  final List<Widget> children;

  const _ReceiptSection({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  final String term;
  final String value;

  const _Fact({required this.term, required this.value});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(term, style: text.bodySmall),
        const SizedBox(height: 2),
        Text(
          value,
          style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}

class _Line extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasized;

  const _Line({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final style = emphasized
        ? text.titleMedium?.copyWith(fontWeight: FontWeight.w700)
        : text.bodyLarge;
    return Row(
      children: <Widget>[
        Expanded(child: Text(label, style: style)),
        const SizedBox(width: 12),
        Text(value, style: style),
      ],
    );
  }
}
