import 'package:flutter/material.dart';

import '../../domain/entities/bill.dart';
import '../../domain/value_objects/ph_date.dart';
import '../common/expandable_bottom_sheet.dart';

/// Opens one billing-cycle record without turning it into a payment receipt.
Future<void> showConsumerBillDetails(
  BuildContext context, {
  required Bill bill,
  required PhDate today,
}) => showExpandableBottomSheet<void>(
  context: context,
  initialSize: 0.82,
  builder: (_, ScrollController scrollController) => ConsumerBillDetails(
    bill: bill,
    today: today,
    scrollController: scrollController,
  ),
);

/// The facts BillAlert has for one bill. No tariff or derived amount appears
/// here: the peso amount is shown only after the cooperative posts it.
///
/// Laid out as a statement rather than a list of label/value pairs, in the
/// same card language as the Official Digital Receipt: what is owed first,
/// then when, then where the bill is in its life, then its reference facts.
/// Every figure on it is one the entity already holds — the screen asks the
/// bill, it never works anything out.
class ConsumerBillDetails extends StatelessWidget {
  final Bill bill;
  final PhDate today;
  final ScrollController? scrollController;

  const ConsumerBillDetails({
    required this.bill,
    required this.today,
    this.scrollController,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Column(
      children: <Widget>[
        SheetDragRegion(
          child: Padding(
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
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            children: <Widget>[
              _StatementCard(bill: bill, today: today),
              const SizedBox(height: 12),
              _DueDateCard(bill: bill, today: today),
              const SizedBox(height: 12),
              _ProgressCard(bill: bill),
              const SizedBox(height: 12),
              _InformationCard(bill: bill),
            ],
          ),
        ),
      ],
    );
  }
}

/// How a status looks. Decided from the bill's own predicates, in the same
/// order `Bill.statusLabelOn` uses, so the colour can never disagree with
/// the word beside it.
///
/// The colours follow the History list the sheet is opened from — a row the
/// consumer tapped in red must not open onto a green sheet.
final class _StatusStyle {
  final String label;
  final IconData icon;
  final Color colour;

  const _StatusStyle(this.label, this.icon, this.colour);

  factory _StatusStyle.of(Bill bill, PhDate today, ColorScheme colours) {
    final String label = bill.statusLabelOn(today);
    if (bill.isUnpriced) {
      return _StatusStyle(label, Icons.hourglass_top, colours.onSurfaceVariant);
    }
    if (bill.isSettled) {
      return _StatusStyle(label, Icons.check_circle, colours.primary);
    }
    if (bill.isOverdueOn(today)) {
      return _StatusStyle(label, Icons.error_outline, colours.error);
    }
    if (bill.isPartiallyPaid) {
      return _StatusStyle(label, Icons.timelapse, colours.error);
    }
    return _StatusStyle(label, Icons.schedule, colours.error);
  }
}

/// The top of the statement: which month, its status, and the one figure
/// the consumer opened this to find.
class _StatementCard extends StatelessWidget {
  final Bill bill;
  final PhDate today;

  const _StatementCard({required this.bill, required this.today});

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colours = Theme.of(context).colorScheme;
    final _StatusStyle status = _StatusStyle.of(bill, today, colours);

    return Container(
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
            child: Row(
              children: <Widget>[
                Container(
                  height: 44,
                  width: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colours.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.bolt, color: colours.onPrimary, size: 25),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'BILLING STATEMENT',
                        style: text.labelSmall?.copyWith(
                          color: colours.primary,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.7,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        bill.cycle.displayName,
                        style: text.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // The status as a full-width band, as the receipt shows SETTLED.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            color: status.colour.withValues(alpha: 0.12),
            child: Row(
              children: <Widget>[
                Icon(status.icon, size: 20, color: status.colour),
                const SizedBox(width: 8),
                Text(
                  status.label,
                  style: text.titleSmall?.copyWith(
                    color: status.colour,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  bill.isUnpriced ? 'Amount billed' : 'Remaining balance',
                  style: text.bodyMedium,
                ),
                const SizedBox(height: 4),
                // An unpriced bill has no figure to show, so it says so in
                // words rather than printing a zero that looks like a bill.
                Text(
                  bill.isUnpriced ? 'Not posted yet' : bill.balance.format(),
                  style: text.headlineMedium?.copyWith(
                    fontSize: bill.isUnpriced ? 26 : 40,
                    height: 1.15,
                    letterSpacing: bill.isUnpriced ? 0 : -1,
                    fontWeight: FontWeight.w700,
                  ),
                ),

                // The balance above, broken down, so the big number is never
                // a figure the consumer has to take on trust.
                if (bill.isPayable) ...<Widget>[
                  const SizedBox(height: 16),
                  const Divider(height: 1),
                  const SizedBox(height: 14),
                  _LedgerLine(
                    label: 'Amount billed',
                    value: bill.totalAmount!.format(),
                  ),
                  const SizedBox(height: 8),
                  _LedgerLine(
                    label: 'Payment received',
                    value: bill.amountPaid.isZero
                        ? bill.amountPaid.format()
                        : '−${bill.amountPaid.format()}',
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LedgerLine extends StatelessWidget {
  final String label;
  final String value;

  const _LedgerLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Row(
      children: <Widget>[
        Expanded(child: Text(label, style: text.bodyMedium)),
        const SizedBox(width: 12),
        Text(
          value,
          style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

/// When the bill falls due, and how that date sits against today.
class _DueDateCard extends StatelessWidget {
  final Bill bill;
  final PhDate today;

  const _DueDateCard({required this.bill, required this.today});

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colours = Theme.of(context).colorScheme;
    final bool overdue = bill.isOverdueOn(today);

    final String value;
    final String note;
    final Color tint;

    if (bill.isUnpriced) {
      value = 'Not assigned yet';
      note = 'A due date is set when the cooperative posts the amount.';
      tint = colours.onSurfaceVariant;
    } else if (bill.isSettled) {
      value = _friendlyDate(bill.dueDate!);
      note = 'Settled — nothing left to pay.';
      tint = colours.primary;
    } else if (overdue) {
      final int days = bill.daysOverdueOn(today);
      value = _friendlyDate(bill.dueDate!);
      note = 'Overdue by $days day${days == 1 ? '' : 's'}';
      tint = colours.error;
    } else {
      final int days = bill.dueDate!.daysSince(today);
      value = _friendlyDate(bill.dueDate!);
      note = days == 0
          ? 'Due today'
          : days == 1
          ? 'Due tomorrow'
          : 'Due in $days days';
      tint = colours.primary;
    }

    return _SectionCard(
      title: 'DUE DATE',
      child: Row(
        children: <Widget>[
          _IconTile(
            icon: overdue ? Icons.event_busy : Icons.event_outlined,
            colour: tint,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  value,
                  style: text.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  note,
                  style: text.bodySmall?.copyWith(
                    color: overdue ? colours.error : null,
                    fontWeight: overdue ? FontWeight.w600 : null,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _Step { done, current, upcoming }

/// Where this bill is in its life: read, priced, paid.
///
/// This is the whole premise of BillAlert made visible — a bill exists for
/// days before it has an amount — and every step is read from the entity.
class _ProgressCard extends StatelessWidget {
  final Bill bill;

  const _ProgressCard({required this.bill});

  @override
  Widget build(BuildContext context) {
    final _Step priced = bill.isPayable ? _Step.done : _Step.current;
    final _Step paid = bill.isSettled
        ? _Step.done
        : bill.isPayable
        ? _Step.current
        : _Step.upcoming;

    final String paymentNote = bill.isSettled
        ? 'Paid in full.'
        : bill.isPartiallyPaid
        ? 'Partly paid. The rest is still to be settled.'
        : bill.isPayable
        ? 'Pay at the cooperative counter.'
        : 'Opens once the amount is posted.';

    return _SectionCard(
      title: 'BILL PROGRESS',
      child: Column(
        children: <Widget>[
          _ProgressStep(
            state: _Step.done,
            title: 'Meter read',
            note:
                'Your consumption for ${bill.cycle.displayName} was '
                'recorded.',
            nextState: priced,
          ),
          _ProgressStep(
            state: priced,
            title: 'Amount posted',
            note: bill.isPayable
                ? 'The cooperative’s peso amount has been posted.'
                : 'The cooperative has not posted this bill’s peso amount '
                      'yet.',
            nextState: paid,
          ),
          _ProgressStep(state: paid, title: 'Payment', note: paymentNote),
        ],
      ),
    );
  }
}

class _ProgressStep extends StatelessWidget {
  final _Step state;
  final String title;
  final String note;

  /// The state of the step below, which decides the connector's colour.
  /// Null for the last step, which has no connector.
  final _Step? nextState;

  const _ProgressStep({
    required this.state,
    required this.title,
    required this.note,
    this.nextState,
  });

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colours = Theme.of(context).colorScheme;
    final bool isLast = nextState == null;

    final Widget marker = switch (state) {
      _Step.done => Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: colours.primary,
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.check, size: 16, color: colours.onPrimary),
      ),
      _Step.current => Container(
        width: 24,
        height: 24,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: colours.primary, width: 2),
        ),
        child: Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: colours.primary,
            shape: BoxShape.circle,
          ),
        ),
      ),
      _Step.upcoming => Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: colours.outline, width: 2),
        ),
      ),
    };

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(
            width: 24,
            child: Column(
              children: <Widget>[
                marker,
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      // Solid only between two steps that have both happened.
                      color: state == _Step.done && nextState == _Step.done
                          ? colours.primary
                          : colours.outlineVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: text.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: state == _Step.upcoming
                          ? colours.onSurfaceVariant
                          : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(note, style: text.bodySmall),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The reference facts: what to quote at the counter, and what was used.
class _InformationCard extends StatelessWidget {
  final Bill bill;

  const _InformationCard({required this.bill});

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'BILL INFORMATION',
      child: Column(
        children: <Widget>[
          _InfoRow(
            icon: Icons.tag,
            label: 'Bill number',
            value: bill.billNo.value,
          ),
          const Divider(height: 20),
          _InfoRow(
            icon: Icons.calendar_month_outlined,
            label: 'Billing month',
            value: bill.cycle.displayName,
          ),
          const Divider(height: 20),
          // The two dial figures, above the difference they produce, so the
          // consumption reads as arithmetic the household can check rather
          // than a number it has to accept. A bill whose reading did not
          // come back says so instead of printing a zero, which on a meter
          // would mean a dial that never turned.
          _InfoRow(
            icon: Icons.speed_outlined,
            label: 'Previous reading',
            value: bill.previousReading?.format() ?? 'Not recorded',
          ),
          const Divider(height: 20),
          _InfoRow(
            icon: Icons.speed,
            label: 'Present reading',
            value: bill.currentReading?.format() ?? 'Not recorded',
          ),
          const Divider(height: 20),
          _InfoRow(
            icon: Icons.bolt,
            label: 'Electricity consumed',
            value: bill.consumption.format(),
          ),
          if (bill.readingDate != null) ...<Widget>[
            const Divider(height: 20),
            _InfoRow(
              icon: Icons.event_available_outlined,
              label: 'Date read',
              value: _friendlyDate(bill.readingDate!),
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Row(
      children: <Widget>[
        _IconTile(
          icon: icon,
          colour: Theme.of(context).colorScheme.primary,
          size: 36,
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(label, style: text.bodyMedium)),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );
  }
}

class _IconTile extends StatelessWidget {
  final IconData icon;
  final Color colour;
  final double size;

  const _IconTile({required this.icon, required this.colour, this.size = 40});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: size * 0.5, color: colour),
    );
  }
}

/// A white card with an uppercase section label, in the receipt's style.
class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colours = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colours.surfaceContainerLowest,
        border: Border.all(color: colours.outlineVariant),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: text.labelMedium?.copyWith(
              color: colours.onSurfaceVariant,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

String _friendlyDate(PhDate date) {
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
