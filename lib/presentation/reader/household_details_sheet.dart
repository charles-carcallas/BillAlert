import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Consumer;

import '../../core/result/result.dart';
import '../../domain/entities/bill.dart';
import '../../domain/entities/consumer.dart';
import '../../domain/repositories/payment_repository.dart';
import '../../domain/value_objects/ids.dart';
import '../../domain/value_objects/ph_date.dart';
import '../cashier/receipt_details_sheet.dart';
import '../common/expandable_bottom_sheet.dart';
import '../consumer/bill_details_sheet.dart';
import '../providers.dart';

/// One household's bills and receipts, each loaded on its own so a failure
/// in one still shows the other.
typedef HouseholdRecords = ({
  Result<List<Bill>> bills,
  Result<List<PaymentSummary>> payments,
});

/// Asks the server first and falls back to what this phone saved, the same
/// way the household's own History tab does. Row-level security limits a
/// meter reader to households in their own area.
final householdRecordsProvider = FutureProvider.autoDispose
    .family<HouseholdRecords, ConsumerId>((Ref ref, ConsumerId id) async {
      final (
        Result<List<Bill>> bills,
        Result<List<PaymentSummary>> payments,
      ) = await (
        ref.read(billRepositoryProvider).historyFor(id),
        ref.read(paymentRepositoryProvider).historyFor(id),
      ).wait;
      return (bills: bills, payments: payments);
    });

/// Meter Reader › Consumers › a household.
Future<void> showReaderHouseholdDetails(
  BuildContext context,
  Consumer household,
) => showExpandableBottomSheet<void>(
  context: context,
  initialSize: 0.9,
  builder: (_, ScrollController scrollController) => ReaderHouseholdDetails(
    household: household,
    scrollController: scrollController,
  ),
);

class ReaderHouseholdDetails extends ConsumerWidget {
  final Consumer household;
  final ScrollController? scrollController;

  const ReaderHouseholdDetails({
    required this.household,
    this.scrollController,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TextTheme text = Theme.of(context).textTheme;
    final PhDate today = ref.watch(phClockProvider).today();
    final AsyncValue<HouseholdRecords> records = ref.watch(
      householdRecordsProvider(household.id),
    );
    void retry() => ref.invalidate(householdRecordsProvider(household.id));

    return Column(
      children: <Widget>[
        SheetDragRegion(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
            child: Row(
              children: <Widget>[
                Expanded(child: Text('Household', style: text.titleLarge)),
                IconButton(
                  tooltip: 'Close household',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
            children: <Widget>[
              _IdentityPanel(household: household),
              _Section(
                title: 'Details',
                children: <Widget>[
                  _FactRow(
                    icon: Icons.speed_outlined,
                    label: 'Meter serial',
                    value: household.meterSerialNo ?? 'Not on file',
                  ),
                  _FactRow(
                    icon: Icons.bolt_outlined,
                    label: 'Last reading',
                    value: household.previousReadingDate == null
                        ? 'No previous reading'
                        : '${household.previousReading.format()} · '
                              '${_longDate(household.previousReadingDate!)}',
                  ),
                  _FactRow(
                    icon: Icons.place_outlined,
                    label: 'Purok',
                    value: household.purok ?? 'Not on file',
                  ),
                  _FactRow(
                    icon: Icons.sms_outlined,
                    label: 'SMS number',
                    value: household.contactNumber ?? 'Not on file',
                  ),
                ],
              ),
              _Section(
                title: 'Bills',
                children: records.when(
                  loading: () => const <Widget>[_LoadingRow()],
                  error: (Object _, StackTrace _) => <Widget>[
                    _ProblemRow(
                      message: 'Bills could not be loaded.',
                      onRetry: retry,
                    ),
                  ],
                  data: (HouseholdRecords value) => switch (value.bills) {
                    Err(:final failure) => <Widget>[
                      _ProblemRow(message: failure.message, onRetry: retry),
                    ],
                    Ok(value: final List<Bill> bills) when bills.isEmpty =>
                      const <Widget>[_EmptyRow(message: 'No bills yet.')],
                    Ok(value: final List<Bill> bills) => <Widget>[
                      for (final Bill bill in bills)
                        _BillRow(
                          bill: bill,
                          today: today,
                          onTap: () => showConsumerBillDetails(
                            context,
                            bill: bill,
                            today: today,
                          ),
                        ),
                    ],
                  },
                ),
              ),
              _Section(
                title: 'Payments',
                children: records.when(
                  loading: () => const <Widget>[_LoadingRow()],
                  error: (Object _, StackTrace _) => <Widget>[
                    _ProblemRow(
                      message: 'Payments could not be loaded.',
                      onRetry: retry,
                    ),
                  ],
                  data: (HouseholdRecords value) => switch (value.payments) {
                    Err(:final failure) => <Widget>[
                      _ProblemRow(message: failure.message, onRetry: retry),
                    ],
                    Ok(value: final List<PaymentSummary> payments)
                        when payments.isEmpty =>
                      const <Widget>[_EmptyRow(message: 'No payments yet.')],
                    Ok(value: final List<PaymentSummary> payments) => <Widget>[
                      for (final PaymentSummary payment in payments)
                        _PaymentRow(
                          payment: payment,
                          onTap: () =>
                              showCashierReceiptDetails(context, payment),
                        ),
                    ],
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _IdentityPanel extends StatelessWidget {
  final Consumer household;

  const _IdentityPanel({required this.household});

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colours = Theme.of(context).colorScheme;
    final String initials =
        '${household.firstName.isEmpty ? '' : household.firstName[0]}'
                '${household.lastName.isEmpty ? '' : household.lastName[0]}'
            .toUpperCase();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colours.primary.withValues(alpha: 0.08),
        border: Border.all(color: colours.primary.withValues(alpha: 0.18)),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colours.primary,
              shape: BoxShape.circle,
            ),
            child: Text(
              initials.isEmpty ? '?' : initials,
              style: text.titleLarge?.copyWith(
                color: colours.onPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(household.fullName, style: text.titleLarge),
                const SizedBox(height: 2),
                Text(
                  household.consumerNo.value,
                  style: text.bodySmall?.copyWith(
                    color: colours.onSurfaceVariant,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 8),
                _StatusChip(
                  label: switch (household.accountStatus) {
                    AccountStatus.active => 'Active',
                    AccountStatus.pending => 'Pending',
                    AccountStatus.inactive => 'Inactive',
                  },
                  colour: household.isActive
                      ? colours.primary
                      : colours.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A titled card of rows, split by dividers that start where the text does.
class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colours = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Text(
              title,
              style: text.titleSmall?.copyWith(
                color: colours.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: colours.surfaceContainerLowest,
              border: Border.all(color: colours.outlineVariant),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: <Widget>[
                for (int i = 0; i < children.length; i++) ...<Widget>[
                  if (i > 0)
                    Divider(
                      height: 1,
                      thickness: 1,
                      indent: 64,
                      color: colours.outlineVariant.withValues(alpha: 0.6),
                    ),
                  children[i],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _IconTile extends StatelessWidget {
  final IconData icon;
  final Color colour;

  const _IconTile({required this.icon, required this.colour});

  @override
  Widget build(BuildContext context) => Container(
    width: 36,
    height: 36,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: colour.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Icon(icon, size: 19, color: colour),
  );
}

class _FactRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _FactRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colours = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        children: <Widget>[
          _IconTile(icon: icon, colour: colours.primary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label,
                  style: text.labelSmall?.copyWith(
                    color: colours.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 1),
                Text(value, style: text.bodyLarge),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BillRow extends StatelessWidget {
  final Bill bill;
  final PhDate today;
  final VoidCallback onTap;

  const _BillRow({
    required this.bill,
    required this.today,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colours = Theme.of(context).colorScheme;
    // The same order Bill.statusLabelOn decides in, so the colour never
    // disagrees with the word beside it.
    final Color tone = bill.isUnpriced
        ? colours.onSurfaceVariant
        : bill.isSettled
        ? colours.primary
        : colours.error;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 11, 8, 11),
        child: Row(
          children: <Widget>[
            _IconTile(
              icon: bill.isSettled
                  ? Icons.check_circle_outline
                  : Icons.receipt_long_outlined,
              colour: tone,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(bill.cycle.displayName, style: text.titleSmall),
                  const SizedBox(height: 1),
                  Text(
                    bill.consumption.format(),
                    style: text.bodySmall?.copyWith(
                      color: colours.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Text(bill.totalAmount?.format() ?? '—', style: text.titleSmall),
                const SizedBox(height: 3),
                _StatusChip(label: bill.statusLabelOn(today), colour: tone),
              ],
            ),
            Icon(Icons.chevron_right, color: colours.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class _PaymentRow extends StatelessWidget {
  final PaymentSummary payment;
  final VoidCallback onTap;

  const _PaymentRow({required this.payment, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colours = Theme.of(context).colorScheme;
    final String months = payment.bills
        .map((SettledBill bill) => bill.cycleLabel)
        .where((String label) => label.isNotEmpty)
        .join(', ');

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 11, 8, 11),
        child: Row(
          children: <Widget>[
            _IconTile(icon: Icons.payments_outlined, colour: colours.primary),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    _longDate(PhDate.at(payment.paidAt)),
                    style: text.titleSmall,
                  ),
                  const SizedBox(height: 1),
                  Text(
                    months.isEmpty
                        ? payment.receiptNo
                        : '${payment.receiptNo} · $months',
                    style: text.bodySmall?.copyWith(
                      color: colours.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(payment.totalCollected.format(), style: text.titleSmall),
            Icon(Icons.chevron_right, color: colours.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color colour;

  const _StatusChip({required this.label, required this.colour});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: colour.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: colour,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _LoadingRow extends StatelessWidget {
  const _LoadingRow();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(18),
    child: Center(
      child: SizedBox.square(
        dimension: 22,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    ),
  );
}

class _EmptyRow extends StatelessWidget {
  final String message;

  const _EmptyRow({required this.message});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(18),
    child: Text(
      message,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

class _ProblemRow extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ProblemRow({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
    child: Row(
      children: <Widget>[
        Icon(
          Icons.cloud_off_outlined,
          size: 20,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(message, style: Theme.of(context).textTheme.bodySmall),
        ),
        TextButton(onPressed: onRetry, child: const Text('Try again')),
      ],
    ),
  );
}

const List<String> _months = <String>[
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _longDate(PhDate date) =>
    '${date.day} ${_months[date.month - 1]} ${date.year}';
