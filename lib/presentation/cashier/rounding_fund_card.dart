import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_failure.dart';
import '../../core/result/result.dart';
import '../../domain/repositories/payment_repository.dart';
import '../../domain/value_objects/cycle_label.dart';
import '../../domain/value_objects/money.dart';
import '../auth/auth_controller.dart';
import '../providers.dart';

/// The area's rounding fund, oldest month first. Only the Cashier's app
/// shows it; the Meter Reader is never shown the rounding.
final roundingFundProvider =
    FutureProvider.autoDispose<List<RoundingFundMonth>>((Ref ref) async {
      final user = await ref.watch(authControllerProvider.future);
      final areaId = user?.areaId;
      if (areaId == null) return const <RoundingFundMonth>[];
      final result = await ref
          .read(paymentRepositoryProvider)
          .roundingFund(areaId);
      return switch (result) {
        Ok(:final value) => value,
        Err(:final failure) => throw failure,
      };
    });

/// Cashier › Receipts: this month's rounding, the Meter Reader's pay and the
/// fund saved. Tap for every month.
class RoundingFundCard extends ConsumerWidget {
  const RoundingFundCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colours = Theme.of(context).colorScheme;
    final AsyncValue<List<RoundingFundMonth>> fund = ref.watch(
      roundingFundProvider,
    );
    final List<RoundingFundMonth>? months = fund.value;
    final RoundingFundMonth? latest = months == null || months.isEmpty
        ? null
        : months.last;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: months == null || months.isEmpty
            ? null
            : () => showRoundingFundMonths(context, months),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(Icons.savings_outlined, color: colours.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      latest == null
                          ? 'Rounding fund'
                          : 'Rounding fund · ${_monthName(latest)}',
                      style: text.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (latest != null)
                    Icon(Icons.chevron_right, color: colours.onSurfaceVariant),
                ],
              ),
              const SizedBox(height: 10),
              if (latest != null) ...<Widget>[
                FundLine('Rounding this month', latest.rounding),
                if (latest.readerPay > Money.zero)
                  FundLine('Previously recorded Reader pay', latest.readerPay),
                if (latest.gap > Money.zero)
                  FundLine(
                    'Kept for unpaid bills',
                    latest.keptForGap,
                    note: 'BOHECO still owed ${latest.gap.format()}',
                  ),
                const Divider(height: 18),
                FundLine('Saved in the fund', latest.fundAfter, strong: true),
              ] else
                Text(
                  switch (fund) {
                    AsyncError(:final error) =>
                      error is AppFailure
                          ? error.message
                          : 'Could not load the rounding fund.',
                    AsyncData() => 'No payments collected yet.',
                    _ => 'Loading…',
                  },
                  style: text.bodySmall?.copyWith(
                    color: colours.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static String _monthName(RoundingFundMonth m) =>
      CycleLabel(m.year, m.month).displayName;
}

/// Every month of the fund, newest first, in a sheet.
void showRoundingFundMonths(
  BuildContext context,
  List<RoundingFundMonth> months,
) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (BuildContext context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (BuildContext context, ScrollController scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: <Widget>[
          Text(
            'Rounding fund by month',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Monthly ₱500 compensation is recorded separately under BOHECO trip. These figures summarize regular collections.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          for (final RoundingFundMonth m in months.reversed) ...<Widget>[
            const SizedBox(height: 16),
            Text(
              RoundingFundCard._monthName(m),
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            FundLine('Collected', m.collected),
            FundLine('To BOHECO', m.toBoheco),
            FundLine('Rounding', m.rounding),
            FundLine('Fund carried in', m.fundBefore),
            FundLine('BOHECO owed at period end', m.gap),
            FundLine('Kept for unpaid bills', m.keptForGap),
            if (m.readerPay > Money.zero)
              FundLine('Previously recorded Reader pay', m.readerPay),
            FundLine('Saved in the fund', m.fundAfter, strong: true),
          ],
        ],
      ),
    ),
  );
}

/// One labelled amount on the fund card and the Cashier's Remit.
class FundLine extends StatelessWidget {
  final String label;
  final Money value;
  final String? note;
  final bool strong;

  const FundLine(
    this.label,
    this.value, {
    this.note,
    this.strong = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colours = Theme.of(context).colorScheme;
    final TextStyle? style = (strong ? text.titleSmall : text.bodyMedium)
        ?.copyWith(
          fontWeight: strong ? FontWeight.w700 : null,
          fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(label, style: style),
                if (note != null)
                  Text(
                    note!,
                    style: text.bodySmall?.copyWith(color: colours.error),
                  ),
              ],
            ),
          ),
          Text(value.format(), style: style),
        ],
      ),
    );
  }
}
