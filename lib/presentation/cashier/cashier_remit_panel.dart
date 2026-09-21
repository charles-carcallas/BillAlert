import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_failure.dart';
import '../../core/result/result.dart';
import '../../domain/repositories/payment_repository.dart';
import '../../domain/value_objects/cycle_label.dart';
import '../../domain/value_objects/money.dart';
import '../auth/auth_controller.dart';
import '../providers.dart';
import 'rounding_fund_card.dart';

/// Every handover recorded in the Cashier's area, newest first.
final remitHandoversProvider = FutureProvider.autoDispose<List<RemitHandover>>((
  Ref ref,
) async {
  final user = await ref.watch(authControllerProvider.future);
  final areaId = user?.areaId;
  if (areaId == null) return const <RemitHandover>[];
  final result = await ref
      .read(paymentRepositoryProvider)
      .remitHandovers(areaId);
  return switch (result) {
    Ok(:final value) => value,
    Err(:final failure) => throw failure,
  };
});

/// Pull to refresh on the Cashier's Remit.
void refreshCashierRemit(WidgetRef ref) {
  ref
    ..invalidate(roundingFundProvider)
    ..invalidate(remitHandoversProvider);
}

/// Cashier › Remit, under the month's summary: where the month's money goes,
/// and the record of handing BOHECO's part to the Meter Reader.
class CashierRemitPanel extends ConsumerStatefulWidget {
  final CycleLabel month;

  const CashierRemitPanel({required this.month, super.key});

  @override
  ConsumerState<CashierRemitPanel> createState() => _CashierRemitPanelState();
}

class _CashierRemitPanelState extends ConsumerState<CashierRemitPanel> {
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colours = Theme.of(context).colorScheme;
    final AsyncValue<List<RoundingFundMonth>> fund = ref.watch(
      roundingFundProvider,
    );
    final List<RemitHandover>? handovers = ref
        .watch(remitHandoversProvider)
        .value;

    final RoundingFundMonth? m = fund.value
        ?.where(
          (RoundingFundMonth f) =>
              f.year == widget.month.year && f.month == widget.month.month,
        )
        .firstOrNull;
    final RemitHandover? done = handovers
        ?.where(
          (RemitHandover h) =>
              h.year == widget.month.year && h.month == widget.month.month,
        )
        .firstOrNull;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.savings_outlined, color: colours.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Where the money goes',
                    style: text.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (fund.value?.isNotEmpty ?? false)
                  TextButton(
                    onPressed: () =>
                        showRoundingFundMonths(context, fund.value!),
                    child: const Text('All months'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (m == null)
              Text(
                switch (fund) {
                  AsyncError(:final error) =>
                    error is AppFailure
                        ? error.message
                        : 'Could not load the rounding fund.',
                  AsyncData() => 'Nothing collected for this month yet.',
                  _ => 'Loading…',
                },
                style: text.bodySmall?.copyWith(
                  color: colours.onSurfaceVariant,
                ),
              )
            else ...<Widget>[
              FundLine('Collected', m.collected),
              FundLine('To BOHECO', m.toBoheco),
              FundLine('Rounding', m.rounding),
              FundLine('Fund carried in', m.fundBefore),
              if (m.gap > Money.zero)
                FundLine(
                  'Kept for unpaid bills',
                  m.keptForGap,
                  note: 'BOHECO still owed ${m.gap.format()}',
                ),
              FundLine('Meter Reader pay (max ₱300)', m.readerPay),
              const Divider(height: 18),
              FundLine('Saved in the fund', m.fundAfter, strong: true),
            ],
            const SizedBox(height: 14),
            if (done != null)
              _HandedOver(done: done)
            else
              FilledButton.icon(
                onPressed: m == null || _saving || handovers == null
                    ? null
                    : () => _record(m),
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.handshake_outlined),
                label: const Text('Mark as handed over'),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _record(RoundingFundMonth m) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Hand over to the Meter Reader?'),
        content: Text(
          'Give the Meter Reader ${m.toBoheco.format()} for the BOHECO '
          'office, and ${m.readerPay.format()} as their pay.\n\n'
          'This is recorded with today\'s date and cannot be changed.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Record handover'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _saving = true);
    final result = await ref
        .read(paymentRepositoryProvider)
        .recordRemitHandover(
          year: widget.month.year,
          month: widget.month.month,
        );
    if (!mounted) return;
    setState(() => _saving = false);

    switch (result) {
      case Ok():
        ref.invalidate(remitHandoversProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Handover for ${widget.month.displayName} recorded.'),
          ),
        );
      case Err(:final failure):
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }
}

class _HandedOver extends StatelessWidget {
  final RemitHandover done;

  const _HandedOver({required this.done});

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colours = Theme.of(context).colorScheme;
    final DateTime at = done.handedAt.toUtc().add(const Duration(hours: 8));
    final String when =
        '${at.day} ${_months[at.month - 1]} ${at.year}, '
        '${at.hour.toString().padLeft(2, '0')}:'
        '${at.minute.toString().padLeft(2, '0')}';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colours.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.check_circle, color: colours.onPrimaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Handed over $when'
              '${done.handedToName == null ? '' : ' to ${done.handedToName}'}: '
              '${done.toBoheco.format()} for BOHECO, '
              '${done.readerPay.format()} pay.',
              style: text.bodySmall?.copyWith(
                color: colours.onPrimaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static const List<String> _months = <String>[
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
}
