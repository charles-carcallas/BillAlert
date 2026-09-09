// `Consumer` in this app means a household, not Riverpod's widget.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Consumer;

import '../../core/errors/app_failure.dart';
import '../../core/result/result.dart';
import '../../domain/entities/consumer.dart';
import '../../domain/repositories/payment_repository.dart';
import '../../domain/value_objects/ph_date.dart';
import '../common/failure_banner.dart';
import '../providers.dart';

/// The household's own copy of one receipt, looked up by its number.
///
/// Looked up rather than passed in, so the screen works from a link and not
/// only from a tap on the History list. The receipt still comes from
/// `v_payment_history` under the consumer's own RLS, so asking for somebody
/// else's number returns nothing.
final consumerReceiptProvider =
    FutureProvider.family<PaymentSummary?, String>((Ref ref, String receiptNo) async {
  final consumerResult =
      await ref.watch(consumerRepositoryProvider).signedInConsumer();

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

/// CON-03 — the Official Digital Receipt.
///
/// One receipt for one cash handover, listing every month it settled. The
/// consumer paid once, so this is one document however many months it covers.
///
/// The verification code is shown as text rather than as the mockup's QR
/// code. Rendering a QR needs a package, and this project adds none — the
/// code itself is the thing the counter checks, and a person can read it
/// aloud. Said plainly on the screen rather than left as a silent omission.
class ConsumerReceiptScreen extends ConsumerWidget {
  final String receiptNo;

  const ConsumerReceiptScreen({required this.receiptNo, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final receipt = ref.watch(consumerReceiptProvider(receiptNo));

    return Scaffold(
      appBar: AppBar(title: const Text('Receipt')),
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
    final TextTheme text = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.receipt_long_outlined,
              size: 40,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text('No receipt $receiptNo',
                style: text.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text(
              'It may belong to another household.',
              style: text.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _Receipt extends ConsumerWidget {
  final PaymentSummary receipt;

  const _Receipt({required this.receipt});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colours = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: <Widget>[
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            child: Column(
              children: <Widget>[
                Container(
                  height: 44,
                  width: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colours.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text('⚡', style: TextStyle(fontSize: 22)),
                ),
                const SizedBox(height: 10),
                Text('Bohol I Electric Cooperative', style: text.titleMedium),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Icon(Icons.verified_outlined,
                        size: 14, color: colours.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Text('Official Digital Receipt', style: text.bodySmall),
                  ],
                ),
                const SizedBox(height: 14),
                const Divider(height: 1),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Icon(Icons.check_circle, size: 18, color: colours.primary),
                    const SizedBox(width: 8),
                    Text('Settled', style: text.titleMedium),
                  ],
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _Fact(term: 'Receipt no.', value: receipt.receiptNo),
                const SizedBox(height: 14),
                _Fact(term: 'Date & time', value: _stamp(receipt.paidAt)),
                const SizedBox(height: 14),
                // The cashier's name is not shown: v_payment_history carries
                // cashier_id but no name, and this screen will not join in
                // Dart to invent one.
                _Fact(term: 'Account holder', value: receipt.consumerName),
              ],
            ),
          ),
        ),

        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text('Bills settled', style: text.bodySmall),
                const SizedBox(height: 10),
                // One line per month. The same receipt number against several
                // months is correct: the money changed hands once.
                for (final SettledBill bill in receipt.bills)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _Line(
                      label: bill.cycleLabel.isEmpty
                          ? bill.billNo.value
                          : bill.cycleLabel,
                      value: bill.amountPaid.format(),
                    ),
                  ),
                const Divider(),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    Text('Total paid', style: text.titleMedium),
                    Text(receipt.totalCollected.format(),
                        style: text.headlineMedium),
                  ],
                ),
                if (receipt.cashTendered != null ||
                    receipt.changeDue != null) ...<Widget>[
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      if (receipt.cashTendered != null)
                        Text(
                          'Cash tendered ${receipt.cashTendered!.format()}',
                          style: text.bodySmall,
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
          ),
        ),

        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: <Widget>[
                Text(
                  'Present this code at the counter to verify',
                  style: text.bodySmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                SelectableText(
                  receipt.verificationCode,
                  style: text.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'The mockup shows this as a QR code. Rendering one needs a '
                  'package this project does not use, so the code is printed '
                  'in full instead — it is the same value the counter checks.',
                  style: text.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),
        Text(
          'This digital receipt is issued in place of a printed one and is '
          'valid at any Bohol I Electric Cooperative counter.',
          style: text.bodySmall,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  /// "21 August 2026, 2:18 PM" in Philippine time.
  static String _stamp(DateTime instant) {
    final PhDate day = PhDate.at(instant);
    final DateTime manila = instant.toUtc().add(PhDate.utcOffset);
    final int hour24 = manila.hour;
    final int hour = hour24 % 12 == 0 ? 12 : hour24 % 12;
    final String minute = manila.minute.toString().padLeft(2, '0');
    const List<String> months = <String>[
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return '${day.day} ${months[day.month - 1]} ${day.year}, '
        '$hour:$minute ${hour24 < 12 ? 'AM' : 'PM'}';
  }
}

class _Fact extends StatelessWidget {
  final String term;
  final String value;

  const _Fact({required this.term, required this.value});

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(term, style: text.bodySmall),
        const SizedBox(height: 2),
        Text(value, style: text.bodyLarge),
      ],
    );
  }
}

class _Line extends StatelessWidget {
  final String label;
  final String value;

  const _Line({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Text(label, style: text.bodyLarge),
        Text(value, style: text.bodyLarge),
      ],
    );
  }
}
