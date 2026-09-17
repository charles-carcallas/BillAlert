import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_failure.dart';
import '../../core/result/result.dart';
import '../../domain/repositories/payment_repository.dart';
import '../../domain/value_objects/cycle_label.dart';
import '../../domain/value_objects/money.dart';
import '../../domain/value_objects/ph_date.dart';
import '../auth/auth_controller.dart';
import '../cashier/receipt_details_sheet.dart';
import '../common/failure_banner.dart';
import '../providers.dart';

/// The BOHECO office takes the month's collections on this day.
const int remittanceDay = 28;

/// Every receipt issued in the signed-in reader's area in the remittance
/// period handed over in [month], newest first. Saved on the phone, so the
/// count still opens at the BOHECO office with no signal.
final monthCollectionsProvider = FutureProvider.autoDispose
    .family<List<PaymentSummary>, CycleLabel>((
      Ref ref,
      CycleLabel month,
    ) async {
      final user = await ref.watch(authControllerProvider.future);
      final areaId = user?.areaId;
      if (areaId == null) {
        throw const PermissionFailure(
          'No service area is attached to this account, so there are no '
          'collections to remit.',
        );
      }
      final (:DateTime from, :DateTime until) = monthBounds(month);
      final result = await ref
          .read(paymentRepositoryProvider)
          .collectedInArea(areaId, from: from, until: until);
      return switch (result) {
        Ok(:final value) => value,
        Err(:final failure) => throw failure,
      };
    });

/// When the collections handed over in [month] were last saved on this phone.
final monthCollectionsSavedAtProvider = FutureProvider.autoDispose
    .family<DateTime?, CycleLabel>((Ref ref, CycleLabel month) async {
      // Re-read whenever the collections themselves are reloaded.
      await ref.watch(monthCollectionsProvider(month).future);
      final user = await ref.watch(authControllerProvider.future);
      final areaId = user?.areaId;
      if (areaId == null) return null;
      final result = await ref
          .read(paymentRepositoryProvider)
          .collectedInAreaSavedAt(areaId, from: monthBounds(month).from);
      return switch (result) {
        Ok(:final value) => value,
        Err() => null,
      };
    });

/// The remittance period handed over on the 28th of [month]: from the 29th
/// of the month before through the 28th itself, midnight to midnight in
/// Manila, as UTC instants. Everything collected up to the end of the 28th
/// goes in this month's envelope; from the 29th it waits for the next one.
///
/// DateTime.utc rolls invalid days forward, so "29 February" in a common year
/// becomes 1 March, which is exactly the day after that month's 28th.
({DateTime from, DateTime until}) monthBounds(CycleLabel month) => (
  from: DateTime.utc(
    month.year,
    month.month - 1,
    remittanceDay + 1,
  ).subtract(PhDate.utcOffset),
  until: DateTime.utc(
    month.year,
    month.month,
    remittanceDay + 1,
  ).subtract(PhDate.utcOffset),
);

/// The month whose handover [today] is collecting for: this month up to the
/// 28th, next month from the 29th.
CycleLabel handoverMonthOf(PhDate today) {
  final CycleLabel month = CycleLabel.of(today);
  return today.day <= remittanceDay ? month : _nextMonth(month);
}

CycleLabel _nextMonth(CycleLabel month) => month.month == 12
    ? CycleLabel(month.year + 1, 1)
    : CycleLabel(month.year, month.month + 1);

/// Meter Reader › Remit.
///
/// On the 28th the reader carries the area's collections to the BOHECO
/// office. This is the count to hand over with them: the month's total, how
/// many receipts make it up, and each receipt by day, so the cash in the
/// envelope can be matched before leaving rather than argued over at the
/// counter. Nothing here is worked out on the phone beyond adding up the
/// receipts the server issued.
class RemittanceScreen extends ConsumerStatefulWidget {
  const RemittanceScreen({super.key});

  @override
  ConsumerState<RemittanceScreen> createState() => _RemittanceScreenState();
}

class _RemittanceScreenState extends ConsumerState<RemittanceScreen> {
  CycleLabel? _month;

  @override
  Widget build(BuildContext context) {
    final PhDate today = ref.watch(phClockProvider).today();
    final CycleLabel current = handoverMonthOf(today);
    final CycleLabel month = _month ?? current;
    final DateTime? savedAt = ref
        .watch(monthCollectionsSavedAtProvider(month))
        .value;
    final AsyncValue<List<PaymentSummary>> receipts = ref.watch(
      monthCollectionsProvider(month),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Remittance')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => ref.refresh(monthCollectionsProvider(month).future),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: <Widget>[
              _SummaryPanel(
                month: month,
                today: today,
                isCurrentMonth: month == current,
                savedAt: savedAt,
                receipts: receipts.value,
                onPrevious: () => setState(() => _month = _shift(month, -1)),
                onNext: month == current
                    ? null
                    : () => setState(() => _month = _shift(month, 1)),
                onCopy: receipts.value == null
                    ? null
                    : () => _copy(context, month, receipts.value!),
              ),
              ...receipts.when(
                loading: () => const <Widget>[
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ],
                error: (Object error, StackTrace _) => <Widget>[
                  const SizedBox(height: 16),
                  FailureBanner(
                    failure: error is AppFailure
                        ? error
                        : ServerFailure(ServerFailure.defaultMessage, '$error'),
                    onRetry: () =>
                        ref.invalidate(monthCollectionsProvider(month)),
                  ),
                ],
                data: (List<PaymentSummary> list) => list.isEmpty
                    ? <Widget>[_Empty(month: month)]
                    : _byDay(context, list),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static CycleLabel _shift(CycleLabel month, int by) {
    final int index = month.year * 12 + (month.month - 1) + by;
    return CycleLabel(index ~/ 12, index % 12 + 1);
  }

  /// Receipts under a heading per Philippine day, each day with its subtotal.
  List<Widget> _byDay(BuildContext context, List<PaymentSummary> receipts) {
    final Map<PhDate, List<PaymentSummary>> days =
        <PhDate, List<PaymentSummary>>{};
    for (final PaymentSummary receipt in receipts) {
      days
          .putIfAbsent(PhDate.at(receipt.paidAt), () => <PaymentSummary>[])
          .add(receipt);
    }
    return <Widget>[
      for (final MapEntry<PhDate, List<PaymentSummary>> day in days.entries)
        _DayGroup(date: day.key, receipts: day.value),
    ];
  }

  Future<void> _copy(
    BuildContext context,
    CycleLabel month,
    List<PaymentSummary> receipts,
  ) async {
    final String reader =
        ref.read(authControllerProvider).value?.fullName ?? '';
    await Clipboard.setData(
      ClipboardData(text: remittanceText(month, receipts, reader: reader)),
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Remittance copied. Paste it into a message or note.'),
      ),
    );
  }
}

/// The remittance as plain text, to paste into a message or print from a
/// notes app: the total first, then every receipt under its day.
String remittanceText(
  CycleLabel month,
  List<PaymentSummary> receipts, {
  String reader = '',
}) {
  final Money total = _totalOf(receipts);
  final StringBuffer out = StringBuffer()
    ..writeln('BillAlert remittance — ${month.displayName}')
    ..writeln(_periodLabel(month));
  if (reader.isNotEmpty) out.writeln('Meter reader: $reader');
  out.writeln('Receipts: ${receipts.length}   Total: ${total.format()}');
  PhDate? day;
  // Oldest first on paper, so it reads in the order the money came in.
  for (final PaymentSummary receipt in receipts.reversed) {
    final PhDate date = PhDate.at(receipt.paidAt);
    if (date != day) {
      day = date;
      out
        ..writeln()
        ..writeln(_longDate(date));
    }
    final String months = receipt.bills
        .map((SettledBill bill) => bill.cycleLabel)
        .where((String label) => label.isNotEmpty)
        .join(', ');
    out.writeln(
      '  ${receipt.receiptNo}  ${receipt.consumerName}'
      '${months.isEmpty ? '' : ' ($months)'}  ${receipt.totalCollected.format()}',
    );
  }
  return out.toString();
}

Money _totalOf(Iterable<PaymentSummary> receipts) => receipts.fold(
  Money.zero,
  (Money sum, PaymentSummary receipt) => sum + receipt.totalCollected,
);

class _SummaryPanel extends StatelessWidget {
  final CycleLabel month;
  final PhDate today;
  final bool isCurrentMonth;
  final DateTime? savedAt;
  final List<PaymentSummary>? receipts;
  final VoidCallback onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onCopy;

  const _SummaryPanel({
    required this.month,
    required this.today,
    required this.isCurrentMonth,
    required this.savedAt,
    required this.receipts,
    required this.onPrevious,
    required this.onNext,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colours = Theme.of(context).colorScheme;
    final List<PaymentSummary>? list = receipts;
    final int households = list == null
        ? 0
        : list.map((PaymentSummary r) => r.consumerId).toSet().length;

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
      decoration: BoxDecoration(
        color: colours.primary.withValues(alpha: 0.08),
        border: Border.all(color: colours.primary.withValues(alpha: 0.18)),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              IconButton(
                tooltip: 'Previous month',
                onPressed: onPrevious,
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  month.displayName,
                  textAlign: TextAlign.center,
                  style: text.titleMedium?.copyWith(
                    color: colours.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Next month',
                onPressed: onNext,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const SizedBox(height: 6),
                Text(
                  'Cash to hand over',
                  textAlign: TextAlign.center,
                  style: text.labelLarge?.copyWith(
                    color: colours.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  list == null ? '—' : _totalOf(list).format(),
                  textAlign: TextAlign.center,
                  style: text.displaySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colours.onSurface,
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _Stat(
                        label: 'Receipts',
                        value: list == null ? '—' : '${list.length}',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _Stat(
                        label: 'Households',
                        value: list == null ? '—' : '$households',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _Stat(
                        label: 'Hand over',
                        value: '$remittanceDay ${_shortMonth(month)}',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  _periodLabel(month),
                  textAlign: TextAlign.center,
                  style: text.bodySmall?.copyWith(
                    color: colours.onSurfaceVariant,
                  ),
                ),
                if (isCurrentMonth) ...<Widget>[
                  const SizedBox(height: 6),
                  _DueLine(daysLeft: _daysUntilHandover(today, month)),
                ],
                if (savedAt != null) ...<Widget>[
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Icon(
                        Icons.offline_pin_outlined,
                        size: 14,
                        color: colours.onSurfaceVariant,
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          'Saved on this phone · updated ${_ago(savedAt!)}',
                          textAlign: TextAlign.center,
                          style: text.bodySmall?.copyWith(
                            color: colours.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 14),
                FilledButton.tonalIcon(
                  onPressed: onCopy,
                  icon: const Icon(Icons.copy_outlined, size: 18),
                  label: const Text('Copy remittance summary'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;

  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colours = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      decoration: BoxDecoration(
        color: colours.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: <Widget>[
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: text.labelSmall?.copyWith(color: colours.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _DueLine extends StatelessWidget {
  final int daysLeft;

  const _DueLine({required this.daysLeft});

  @override
  Widget build(BuildContext context) {
    final ColorScheme colours = Theme.of(context).colorScheme;
    final bool soon = daysLeft <= 3;
    final Color tone = soon ? colours.error : colours.onSurfaceVariant;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Icon(Icons.event_outlined, size: 16, color: tone),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            daysLeft == 0
                ? 'Hand over to the BOHECO office today'
                : daysLeft == 1
                ? 'Hand over to the BOHECO office tomorrow'
                : 'Hand over to the BOHECO office in $daysLeft days',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: tone,
              fontWeight: soon ? FontWeight.w600 : null,
            ),
          ),
        ),
      ],
    );
  }
}

class _DayGroup extends StatelessWidget {
  final PhDate date;
  final List<PaymentSummary> receipts;

  const _DayGroup({required this.date, required this.receipts});

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
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    _longDate(date),
                    style: text.titleSmall?.copyWith(
                      color: colours.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  _totalOf(receipts).format(),
                  style: text.titleSmall?.copyWith(
                    color: colours.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
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
                for (int i = 0; i < receipts.length; i++) ...<Widget>[
                  if (i > 0)
                    Divider(
                      height: 1,
                      thickness: 1,
                      indent: 64,
                      color: colours.outlineVariant.withValues(alpha: 0.6),
                    ),
                  _ReceiptRow(receipt: receipts[i]),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReceiptRow extends StatelessWidget {
  final PaymentSummary receipt;

  const _ReceiptRow({required this.receipt});

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colours = Theme.of(context).colorScheme;
    final String months = receipt.bills
        .map((SettledBill bill) => bill.cycleLabel)
        .where((String label) => label.isNotEmpty)
        .join(', ');

    return InkWell(
      onTap: () => showCashierReceiptDetails(context, receipt),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 11, 8, 11),
        child: Row(
          children: <Widget>[
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colours.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.payments_outlined,
                size: 19,
                color: colours.primary,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    receipt.consumerName,
                    style: text.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 1),
                  Text(
                    months.isEmpty
                        ? receipt.receiptNo
                        : '${receipt.receiptNo} · $months',
                    style: text.bodySmall?.copyWith(
                      color: colours.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(receipt.totalCollected.format(), style: text.titleSmall),
            Icon(Icons.chevron_right, color: colours.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final CycleLabel month;

  const _Empty({required this.month});

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colours = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: <Widget>[
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: colours.primary.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.account_balance_wallet_outlined,
              size: 30,
              color: colours.primary,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'No payments collected in ${month.displayName}.',
            style: text.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            'Receipts the Cashier issues in your area appear here.',
            style: text.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

const List<String> _monthsShort = <String>[
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

String _shortMonth(CycleLabel month) => _monthsShort[month.month - 1];

/// "Collected 29 Aug – 28 Sep 2026".
String _periodLabel(CycleLabel month) {
  final CycleLabel before = month.month == 1
      ? CycleLabel(month.year - 1, 12)
      : CycleLabel(month.year, month.month - 1);
  // The day after the previous month's 28th, which is 1 March after a
  // 28-day February.
  final PhDate start = PhDate.at(monthBounds(month).from);
  final String startText = start.month == before.month
      ? '${start.day} ${_shortMonth(before)}'
      : '${start.day} ${_shortMonth(month)}';
  return 'Collected $startText – $remittanceDay ${_shortMonth(month)} '
      '${month.year}';
}

int _daysUntilHandover(PhDate today, CycleLabel month) {
  final DateTime from = DateTime.utc(today.year, today.month, today.day);
  final DateTime to = DateTime.utc(month.year, month.month, remittanceDay);
  return to.difference(from).inDays;
}

String _ago(DateTime instant) {
  final Duration difference = DateTime.now().toUtc().difference(instant);
  if (difference.inMinutes < 1) return 'just now';
  if (difference.inMinutes < 60) return '${difference.inMinutes} min ago';
  if (difference.inHours < 24) return '${difference.inHours} h ago';
  return '${difference.inDays} d ago';
}

String _longDate(PhDate date) =>
    '${date.day} ${_monthsShort[date.month - 1]} ${date.year}';
