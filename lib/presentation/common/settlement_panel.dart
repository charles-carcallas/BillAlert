import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/settlement_repository.dart';
import '../../data/supabase/failure_mapper.dart';
import '../../domain/entities/app_user.dart';
import '../../domain/entities/billing_schedule.dart';
import '../../domain/value_objects/cycle_label.dart';
import '../../domain/value_objects/money.dart';
import '../auth/auth_controller.dart';
import '../cashier/record_payment_controller.dart';
import '../providers.dart';
import 'overdue_screen.dart';

// A popped dialog remains mounted during its reverse animation. Keep the
// form controllers alive until its overlay has actually been removed.
Future<T?> _showFormDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final route = DialogRoute<T>(
    context: context,
    builder: builder,
    themes: InheritedTheme.capture(from: context, to: navigator.context),
  );
  final result = await navigator.push(route);
  await route.completed;
  return result;
}

final settlementRepositoryProvider = Provider(
  (ref) => SettlementRepository(
    ref.watch(supabaseClientProvider),
    ref.watch(appDatabaseProvider),
  ),
);
final settlementSnapshotProvider = FutureProvider.autoDispose((ref) async {
  final user = await ref.watch(authControllerProvider.future);
  if (user == null || !user.hasWorkAccess) {
    throw StateError('Staff access required.');
  }
  return ref.watch(settlementRepositoryProvider).snapshot(user.accessScope);
});
final householdSettlementsProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, id) {
      ref.watch(authControllerProvider.select((s) => s.value?.accessScope));
      return ref.watch(settlementRepositoryProvider).forHousehold(id);
    });

String settlementLabel(String state) => switch (state) {
  'review' => 'Reserve fund review · Collection paused',
  'handed_over' => 'Reserve fund with Meter Reader',
  'awaiting_referral' => 'Pay at BOHECO · Not yet reported',
  'referred' => 'Pay directly at BOHECO',
  'awaiting_repayment' => 'Repay reserve fund through Cashier',
  'settled' => 'Settled',
  _ => 'Check payment route',
};

/// Shared trip workspace: Cashier allocates, Reader confirms, Admin reviews.
/// All financial writes require a connection and a matching signed-in scope.
class SettlementPanel extends ConsumerStatefulWidget {
  const SettlementPanel({
    super.key,
    this.month,
    this.showFund = true,
    this.directOnly = false,
  });
  final bool directOnly;
  final bool showFund;
  final CycleLabel? month;
  @override
  ConsumerState<SettlementPanel> createState() => _SettlementPanelState();
}

class _SettlementPanelState extends ConsumerState<SettlementPanel> {
  final selected = <String>{};
  String? selectedMonth, message, reader;
  bool busy = false;
  Money amount(Map<String, dynamic> row, String key) =>
      Money.tryParse('${row[key]}') ?? Money.zero;

  Future<void> action(
    Future<void> Function(SettlementRepository) operation,
  ) async {
    if (busy) return;
    final scope = ref.read(authControllerProvider).value?.accessScope;
    if (!ref.read(networkStatusProvider).isOnline) {
      setState(
        () => message = 'Connect to update reserve fund or BOHECO records.',
      );
      return;
    }
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await operation(ref.read(settlementRepositoryProvider));
      if (!mounted ||
          ref.read(authControllerProvider).value?.accessScope != scope) {
        return;
      }
      selected.clear();
      ref.invalidate(settlementSnapshotProvider);
      ref.invalidate(overdueBillsProvider);
      ref.invalidate(recordPaymentControllerProvider);
      ref.invalidate(householdSettlementsProvider);
      setState(() => message = 'Saved.');
    } catch (e, s) {
      if (mounted &&
          ref.read(authControllerProvider).value?.accessScope == scope) {
        selected.clear();
        ref.invalidate(settlementSnapshotProvider);
        ref.invalidate(overdueBillsProvider);
        setState(() => message = FailureMapper.from(e, s).message);
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<bool> confirm(String title, String detail) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          scrollable: true,
          title: Text(title),
          content: Text(detail),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Confirm'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> funds(bool admin) async {
    if (busy) return;
    final user = ref.read(authControllerProvider).value;
    if (user == null) return;
    final owner = '${user.id.value}:${user.roleCode}:${user.areaId?.value}';
    final startingScope = user.accessScope;
    try {
      final pending = await ref
          .read(settlementRepositoryProvider)
          .pendingEntry(owner);
      if (!mounted ||
          ref.read(authControllerProvider).value?.accessScope != startingScope) {
        return;
      }
      if (pending != null) {
        if (await confirm(
              'Check previous fund entry?',
              '${Money.parse(pending.amount).format()} · ${pending.reason}\nThis entry may already be saved. Check it using the original reference before recording new money.',
            ) &&
            mounted &&
            ref.read(authControllerProvider).value?.accessScope ==
                startingScope) {
          await fundAction(
            owner,
            (r) => r.entry(
              Money.parse(pending.amount),
              pending.kind,
              pending.reason,
              pending.uuid,
              owner: owner,
            ),
          );
        }
        return;
      }
    } catch (e, s) {
      if (mounted) setState(() => message = FailureMapper.from(e, s).message);
      return;
    }
    final value = TextEditingController(), reason = TextEditingController();
    final options = [
      if (!admin) ...[
        ('opening', 'Opening balance', Icons.account_balance_wallet_outlined),
        ('contribution', 'Add money', Icons.add_circle_outline),
        ('withdrawal', 'Withdraw', Icons.remove_circle_outline),
      ],
      if (admin) ('correction', 'Correction', Icons.tune),
    ];
    String kind = admin ? 'correction' : 'contribution';
    String? error;
    final scope = ref.read(authControllerProvider).value?.accessScope;
    final result = await _showFormDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, update) => AlertDialog(
          backgroundColor: Theme.of(c).colorScheme.surface,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 24,
          ),
          titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          title: Text(
            'Record fund money',
            style: Theme.of(c).textTheme.titleLarge,
          ),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < options.length; i += 2)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (var j = i; j < i + 2; j++) ...[
                              if (j > i) const SizedBox(width: 8),
                              Expanded(
                                child: j >= options.length
                                    ? const SizedBox.shrink()
                                    : _FundEntryChoice(
                                        label: options[j].$2,
                                        icon: options[j].$3,
                                        selected: kind == options[j].$1,
                                        onPressed: () => update(() {
                                          kind = options[j].$1;
                                          error = null;
                                        }),
                                      ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  Text(switch (kind) {
                    'opening' => 'Starting cash already held.',
                    'withdrawal' => 'Money taken out of the fund.',
                    'correction' => 'Use + or − to adjust the balance.',
                    _ => 'New money received for the fund.',
                  }, style: Theme.of(c).textTheme.bodySmall),
                  const SizedBox(height: 12),
                  TextField(
                    controller: value,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Amount (₱)'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: reason,
                    decoration: const InputDecoration(
                      labelText: 'Reason / source',
                    ),
                  ),
                  if (error != null) Text(error!),
                ],
              ),
            ),
          ),
          actions: [
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(c, false),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      final m = Money.tryParse(value.text);
                      if (m == null ||
                          m.isZero ||
                          reason.text.trim().isEmpty ||
                          (kind != 'correction' && m < Money.zero)) {
                        update(() => error = 'Enter an amount and reason.');
                        return;
                      }
                      Navigator.pop(c, true);
                    },
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (mounted &&
        result == true &&
        ref.read(authControllerProvider).value?.accessScope == scope) {
      var m = Money.parse(value.text);
      if (kind == 'withdrawal') m = Money.zero - m;
      await fundAction(
        owner,
        (r) => r.entry(
          m,
          kind,
          reason.text.trim(),
          ref.read(clientUuidFactoryProvider)().value,
          owner: owner,
        ),
      );
    }
    value.dispose();
    reason.dispose();
  }

  Future<void> fundAction(
    String owner,
    Future<void> Function(SettlementRepository) operation,
  ) async {
    final scope = ref.read(authControllerProvider).value?.accessScope;
    await action(operation);
    if (!mounted ||
        ref.read(authControllerProvider).value?.accessScope != scope) {
      return;
    }
    try {
      final pending = await ref
          .read(settlementRepositoryProvider)
          .pendingEntry(owner);
      if (mounted &&
          ref.read(authControllerProvider).value?.accessScope == scope &&
          pending != null) {
        setState(
          () => message =
              'Fund entry confirmation is pending. Do not record the money again. Tap Record reserve fund money to check the original entry.',
        );
      }
    } catch (_) {
      // Keep the operation result visible if local storage is unavailable.
    }
  }

  Future<void> reversePayout(Map<String, dynamic> payout) async {
    final reason = TextEditingController();
    final owner = ref.read(authControllerProvider).value?.accessScope;
    final ok = await _showFormDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Reverse compensation payout?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Confirm the ₱500 was never handed over or was returned to Cashier. The month becomes unpaid again.',
            ),
            TextField(
              controller: reason,
              decoration: const InputDecoration(labelText: 'Reason'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (reason.text.trim().isNotEmpty) Navigator.pop(c, true);
            },
            child: const Text('Confirm returned cash'),
          ),
        ],
      ),
    );
    if (mounted &&
        ok == true &&
        owner == ref.read(authControllerProvider).value?.accessScope) {
      await action(
        (r) =>
            r.reverseCompensation(payout['id'] as String, reason.text.trim()),
      );
    }
    reason.dispose();
  }

  Future<void> payment(Map<String, dynamic> bill) async {
    final reference = TextEditingController(),
        evidence = TextEditingController();
    DateTime paidAt = ref.read(phClockProvider).nowUtc();
    String? error;
    final scope = ref.read(authControllerProvider).value?.accessScope;
    final result = await _showFormDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, update) => AlertDialog(
          title: const Text('Confirm BOHECO payment'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${bill['consumer_name']} · ${bill['consumer_no']}\n${bill['bill_no']}\nFull BOHECO amount: ${amount(bill, 'boheco_amount').format()}',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: reference,
                  decoration: const InputDecoration(
                    labelText: 'BOHECO receipt / reference',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: evidence,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Verification evidence',
                    hintText: 'Receipt checked, or BOHECO confirmation details',
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    final ph = paidAt.toUtc().add(const Duration(hours: 8));
                    final date = await showDatePicker(
                      context: c,
                      initialDate: DateTime(ph.year, ph.month, ph.day),
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now().toUtc().add(
                        const Duration(hours: 8),
                      ),
                    );
                    if (date != null && c.mounted) {
                      update(
                        () => paidAt = DateTime.utc(
                          date.year,
                          date.month,
                          date.day,
                          0,
                        ).subtract(const Duration(hours: 8)),
                      );
                    }
                  },
                  child: Text(
                    'Payment date: ${paidAt.toUtc().add(const Duration(hours: 8)).toIso8601String().substring(0, 10)}',
                  ),
                ),
                if (error != null) Text(error!),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (reference.text.trim().isEmpty ||
                    evidence.text.trim().isEmpty) {
                  update(
                    () =>
                        error = 'Receipt reference and evidence are required.',
                  );
                  return;
                }
                Navigator.pop(c, true);
              },
              child: const Text('Verify payment'),
            ),
          ],
        ),
      ),
    );
    if (mounted &&
        result == true &&
        ref.read(authControllerProvider).value?.accessScope == scope) {
      await action(
        (r) => r.verify(
          bill['bill_id'] as String,
          amount(bill, 'boheco_amount'),
          reference.text.trim(),
          paidAt,
          evidence.text.trim(),
          ref.read(clientUuidFactoryProvider)().value,
        ),
      );
    }
    reference.dispose();
    evidence.dispose();
  }

  Future<void> correction(Map<String, dynamic> bill) async {
    final reason = TextEditingController();
    final scope = ref.read(authControllerProvider).value?.accessScope;
    final returned = bill['state'] == 'handed_over';
    final ok = await _showFormDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        scrollable: true,
        title: Text(
          returned
              ? 'Record returned reserve fund'
              : 'Reverse BOHECO confirmation',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              returned
                  ? 'Confirm ${amount(bill, 'boheco_amount').format()} was physically returned to Cashier.'
                  : bill['route'] == 'pondo'
                  ? 'The money stays with the Meter Reader. Cashier repayment pauses until the correct BOHECO payment is verified. Record returned cash separately only if it is physically returned.'
                  : 'The original evidence stays in the audit history. The bill will become payable at BOHECO again.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reason,
              decoration: const InputDecoration(labelText: 'Correction reason'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (reason.text.trim().isNotEmpty) Navigator.pop(c, true);
            },
            child: const Text('Confirm correction'),
          ),
        ],
      ),
    );
    if (mounted &&
        ok == true &&
        ref.read(authControllerProvider).value?.accessScope == scope) {
      await action(
        (r) => r.correct(
          bill['bill_id'] as String,
          reason.text.trim(),
          action: returned ? 'return_funds' : 'reverse_verification',
          updatedAt: bill['updated_at'] as String,
          uuid: ref.read(clientUuidFactoryProvider)().value,
        ),
      );
    }
    reason.dispose();
  }

  Future<void> supply(Map<String, dynamic> bill) async {
    final evidence = TextEditingController();
    String status = 'reconnected';
    final scope = ref.read(authControllerProvider).value?.accessScope;
    final yes = await _showFormDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, update) => AlertDialog(
          title: const Text('Confirmed electricity status'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: status,
                items: const [
                  DropdownMenuItem(
                    value: 'reconnected',
                    child: Text('Reconnected by BOHECO'),
                  ),
                  DropdownMenuItem(
                    value: 'disconnected',
                    child: Text('Disconnected by BOHECO'),
                  ),
                ],
                onChanged: (v) => update(() => status = v!),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: evidence,
                decoration: const InputDecoration(
                  labelText: 'BOHECO confirmation evidence',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (evidence.text.trim().isNotEmpty) {
                  Navigator.pop(c, true);
                }
              },
              child: const Text('Save status'),
            ),
          ],
        ),
      ),
    );
    if (mounted &&
        yes == true &&
        ref.read(authControllerProvider).value?.accessScope == scope) {
      await action(
        (r) =>
            r.supply(bill['bill_id'] as String, status, evidence.text.trim()),
      );
    }
    evidence.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authControllerProvider.select((s) => s.value?.accessScope), (
      old,
      next,
    ) {
      if (old != next) {
        selected.clear();
        selectedMonth = null;
        reader = null;
        message = null;
      }
    });
    final user = ref.watch(authControllerProvider).value;
    final cashier = user is CashierUser,
        meter = user is MeterReaderUser,
        admin = user is AdminUser;
    final data = ref.watch(settlementSnapshotProvider);
    return data.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, s) => Column(
        children: [
          Text(FailureMapper.from(e, s).message),
          TextButton(
            onPressed: () => ref.invalidate(settlementSnapshotProvider),
            child: const Text('Refresh reserve fund and trips'),
          ),
        ],
      ),
      data: (snapshot) {
        final all = snapshot
            .rows('bills')
            .where((b) => !widget.directOnly || b['route'] == 'boheco')
            .toList();
        final trips = snapshot
            .rows('trips')
            .where(
              (t) =>
                  !widget.directOnly || all.any((b) => b['trip_id'] == t['id']),
            )
            .toList();
        final readers = snapshot.rows('readers');
        final calendarMonth = CycleLabel.of(ref.watch(phClockProvider).today());
        // Keep the initial relevant trip, but never fall back after the user
        // explicitly chooses an empty month.
        selectedMonth ??=
            (trips
                        .where(
                          (t) => t['trip_month'] == '${widget.month?.value}-01',
                        )
                        .firstOrNull ??
                    trips.firstOrNull)?['trip_month']
                as String? ??
            '${(widget.month ?? calendarMonth).value}-01';
        final trip = trips
            .where((t) => t['trip_month'] == selectedMonth)
            .firstOrNull;
        final rows = all
            .where((b) => trip != null && b['trip_id'] == trip['id'])
            .toList();
        final review = rows.where((b) => b['state'] == 'review').toList()
          ..sort(
            (a, b) => amount(
              a,
              'consumer_amount',
            ).compareTo(amount(b, 'consumer_amount')),
          );
        selected.removeWhere((id) => !review.any((b) => b['bill_id'] == id));
        final picked = review
            .where((b) => selected.contains(b['bill_id']))
            .toList();
        final total = picked.fold(
          Money.zero,
          (sum, b) => sum + amount(b, 'boheco_amount'),
        );
        final currentMonth = meter
            ? calendarMonth
            : widget.month ?? calendarMonth;
        final currentClosed = trips.any(
          (t) =>
              t['trip_month'] == '${currentMonth.value}-01' &&
              t['is_collection_closed'] != false,
        );
        String tripLabel(Map<String, dynamic> t) {
          final date = DateTime.tryParse('${t['trip_month']}');
          return date == null
              ? '${t['trip_month']}'
              : CycleLabel(date.year, date.month).displayName;
        }

        final coverageAvailable =
            snapshot.data.containsKey('coverage_available')
            ? snapshot.money('coverage_available')
            : snapshot.money('available');
        final activeReader =
            readers.where((r) => r['id'] == reader).firstOrNull ??
            (readers.length == 1 ? readers.first : null);
        Widget line(Map<String, dynamic> b) => ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('${b['consumer_name']}'),
          subtitle: Text(
            '${b['consumer_no']} · ${b['cycle_year']}-${b['cycle_month']}\n${settlementLabel(b['state'] as String)}',
          ),
          trailing: Text(amount(b, 'balance').format()),
        );
        final months = <String>{
          selectedMonth!,
          for (final t in trips) t['trip_month'] as String,
          for (var i = 0; i < 24; i++)
            '${CycleLabel(DateTime(calendarMonth.year, calendarMonth.month - i).year, DateTime(calendarMonth.year, calendarMonth.month - i).month).value}-01',
        }.toList()..sort((a, b) => b.compareTo(a));
        final Widget monthControl = DropdownButtonFormField<String>(
          key: ValueKey(selectedMonth),
          initialValue: selectedMonth,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Month'),
          items: months
              .map(
                (t) => DropdownMenuItem(
                  value: t,
                  child: Text(tripLabel({'trip_month': t})),
                ),
              )
              .toList(),
          onChanged: busy
              ? null
              : (v) => setState(() {
                  selectedMonth = v;
                  selected.clear();
                }),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!widget.directOnly)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      meter || !widget.showFund
                          ? 'BOHECO trips'
                          : 'Reserve fund',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Refresh trip',
                    onPressed: busy
                        ? null
                        : () => ref.invalidate(settlementSnapshotProvider),
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
            if (!meter && widget.showFund)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Available',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      Text(
                        snapshot.money('available').format(),
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: const Text('Balance details'),
                        children: [
                          if (admin)
                            TextButton.icon(
                              onPressed: busy ? null : () => funds(true),
                              icon: const Icon(Icons.edit_outlined),
                              label: const Text('Correct balance'),
                            ),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('With Meter Reader'),
                            trailing: Text(
                              snapshot.money('in_transit').format(),
                            ),
                          ),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Awaiting repayment'),
                            trailing: Text(
                              snapshot.money('owed_to_pondo').format(),
                            ),
                          ),
                        ],
                      ),
                      if (cashier)
                        TextButton.icon(
                          onPressed: busy ? null : () => funds(admin),
                          icon: const Icon(Icons.add),
                          label: const Text('Record reserve fund money'),
                        ),
                    ],
                  ),
                ),
              ),
            if (widget.showFund &&
                snapshot.rows('compensation_months').isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Meter Reader compensation',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Text('₱500 monthly'),
              if (cashier && readers.length > 1)
                DropdownButtonFormField<String>(
                  initialValue: reader,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Recipient'),
                  items: [
                    for (final r in readers)
                      DropdownMenuItem(
                        value: r['id'] as String,
                        child: Text(r['name'] as String),
                      ),
                  ],
                  onChanged: busy ? null : (v) => setState(() => reader = v),
                ),
              for (final p in snapshot.rows('compensation_months'))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        tripLabel({'trip_month': p['month']}),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      if (p['id'] != null)
                        Text('Paid · ${p['reader_name']}')
                      else if (cashier) ...[
                        if (snapshot.money('available') < Money.parse('500'))
                          const Text(
                            'Compensation pending · Insufficient reserve fund',
                          ),
                        if (activeReader == null)
                          const Text(
                            'Select an active Meter Reader to receive the payout.',
                          ),
                        FilledButton(
                          onPressed:
                              busy ||
                                  activeReader == null ||
                                  snapshot.money('available') <
                                      Money.parse('500')
                              ? null
                              : () async {
                                  final owner = ref
                                      .read(authControllerProvider)
                                      .value
                                      ?.accessScope;
                                  if (await confirm(
                                        'Record ₱500 payout?',
                                        '₱500 handed to ${activeReader['name']} for ${tripLabel({'trip_month': p['month']})}? Confirm only after handing over the money.',
                                      ) &&
                                      mounted &&
                                      owner ==
                                          ref
                                              .read(authControllerProvider)
                                              .value
                                              ?.accessScope) {
                                    await action(
                                      (r) => r.payCompensation(
                                        p['month'] as String,
                                        activeReader['id'] as String,
                                      ),
                                    );
                                  }
                                },
                          child: const Text('Record ₱500 payout'),
                        ),
                      ] else
                        const Text('Pending payout'),
                      if (admin && p['id'] != null)
                        TextButton(
                          onPressed: busy ? null : () => reversePayout(p),
                          child: const Text('Correct payout'),
                        ),
                    ],
                  ),
                ),
              if (!meter)
                Text(
                  'Set aside for compensation: ${snapshot.money('compensation_reserved').format()} · Available for bill coverage: ${coverageAvailable.format()}',
                ),
              const Divider(height: 24),
            ],
            if (admin &&
                widget.showFund &&
                snapshot.rows('waiver_review').isNotEmpty)
              ExpansionTile(
                title: const Text('Previous waived bills · Review'),
                subtitle: const Text(
                  'New Meter Reader bills are payable normally.',
                ),
                children: [
                  for (final b in snapshot.rows('waiver_review'))
                    ListTile(
                      title: Text('${b['consumer_name']}'),
                      subtitle: Text('${b['bill_no']}'),
                      trailing: Text(amount(b, 'amount').format()),
                    ),
                ],
              ),
            if (meter) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${currentMonth.displayName} collection',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  if (currentClosed)
                    const Chip(
                      label: Text('Closed'),
                      avatar: Icon(Icons.lock_outline, size: 16),
                    ),
                ],
              ),
              if (meter && !currentClosed)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: OutlinedButton.icon(
                    onPressed: busy
                        ? null
                        : () async {
                            final scope = ref
                                .read(authControllerProvider)
                                .value
                                ?.accessScope;
                            if (await confirm(
                                  'Close collection for this trip?',
                                  '${currentMonth.displayName}\nEligible unpaid bills wait for allocation; overdue uncovered bills go to Pay at BOHECO.',
                                ) &&
                                mounted &&
                                ref
                                        .read(authControllerProvider)
                                        .value
                                        ?.accessScope ==
                                    scope) {
                              await action(
                                (r) => r.close('${currentMonth.value}-01'),
                              );
                            }
                          },
                    icon: const Icon(Icons.lock_clock_outlined),
                    label: Text(
                      'Close collection · ${currentMonth.displayName}',
                    ),
                  ),
                ),
              const SizedBox(height: 12),
            ],
            if (widget.directOnly)
              Row(
                children: [
                  Expanded(child: monthControl),
                  IconButton(
                    tooltip: 'Refresh trip',
                    onPressed: busy
                        ? null
                        : () => ref.invalidate(settlementSnapshotProvider),
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              )
            else
              monthControl,
            if (trip?['closed_at'] is String &&
                trip?['is_collection_closed'] != false)
              Text(
                'Collection closed ${BillingSchedule.formatPhInstant(DateTime.parse(trip!['closed_at'] as String))} PH time.',
                style: Theme.of(context).textTheme.bodySmall,
              )
            else if (!widget.directOnly &&
                !currentClosed &&
                snapshot.data['schedule'] is Map)
              Text(
                'Usual cutoff: ${BillingSchedule.fromJson(Map<String, dynamic>.from(snapshot.data['schedule'] as Map)).cutoffLabel}.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            if (message != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(message!),
              ),
            if (busy) const LinearProgressIndicator(),
            if (rows.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  widget.directOnly
                      ? 'No bills assigned to Pay at BOHECO for this month.'
                      : 'No BOHECO trip bills recorded for this month.',
                ),
              ),
            if (!cashier && review.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: ExpansionTile(
                  key: ValueKey('awaiting:${trip?['id']}'),
                  tilePadding: EdgeInsets.zero,
                  title: Text('Awaiting Cashier allocation · ${review.length}'),
                  subtitle: Text(
                    meter
                        ? 'No action needed from you yet.'
                        : 'Cashier prepares the allocation.',
                  ),
                  children: [
                    for (final b in review)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('${b['consumer_name']}'),
                        subtitle: Text('${b['consumer_no']}'),
                        trailing: Text(amount(b, 'consumer_amount').format()),
                      ),
                  ],
                ),
              ),
            if (cashier && review.isNotEmpty) ...[
              const SizedBox(height: 16),
              ExpansionTile(
                key: ValueKey('prepare:${trip?['id']}'),
                tilePadding: EdgeInsets.zero,
                title: Text('Choose bills to cover · ${review.length}'),
                subtitle: Text('${picked.length} selected · ${total.format()}'),
                children: [
                  for (final b in review)
                    cashier
                        ? CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            value: selected.contains(b['bill_id']),
                            onChanged: busy
                                ? null
                                : (yes) => setState(() {
                                    if (yes == true) {
                                      selected.add(b['bill_id'] as String);
                                    } else {
                                      selected.remove(b['bill_id']);
                                    }
                                  }),
                            title: Text('${b['consumer_name']}'),
                            secondary: Tooltip(
                              message: 'Household repayment',
                              child: Text(
                                amount(b, 'consumer_amount').format(),
                              ),
                            ),
                            subtitle: Text(
                              '${b['consumer_no']}\nBOHECO ${amount(b, 'boheco_amount').format()}',
                            ),
                          )
                        : line(b),
                ],
              ),
              if (cashier) ...[
                if (readers.length > 1)
                  DropdownButtonFormField<String>(
                    initialValue: reader,
                    decoration: const InputDecoration(
                      labelText: 'Meter Reader receiving money',
                    ),
                    items: readers
                        .map(
                          (r) => DropdownMenuItem(
                            value: r['id'] as String,
                            child: Text(r['name'] as String),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => reader = v),
                  ),
                Text('Reserve fund selected · ${total.format()}'),
                if (total > coverageAvailable)
                  const Text(
                    'Selection exceeds funds available after compensation.',
                  ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed:
                      busy || activeReader == null || total > coverageAvailable
                      ? null
                      : () async {
                          final scope = ref
                              .read(authControllerProvider)
                              .value
                              ?.accessScope;
                          if (await confirm(
                                'Confirm allocation and handover?',
                                'Hand ${total.format()} to ${activeReader['name']}.\n${picked.length} bills covered; ${review.length - picked.length} bills assigned to BOHECO.\nConfirm only after handing over the actual cash.',
                              ) &&
                              mounted &&
                              ref
                                      .read(authControllerProvider)
                                      .value
                                      ?.accessScope ==
                                  scope) {
                            await action(
                              (r) => r.allocate(
                                trip!['id'] as String,
                                picked,
                                activeReader['id'] as String,
                              ),
                            );
                          }
                        },
                  child: const Text('Confirm allocation & handover'),
                ),
              ],
            ],
            if (meter &&
                trip != null &&
                rows.isNotEmpty &&
                (trip['completed_at'] == null ||
                    rows.any((b) => b['state'] == 'awaiting_referral'))) ...[
              const SizedBox(height: 16),
              if (rows.any(
                (b) => b['state'] == 'review' || b['state'] == 'handed_over',
              ))
                const Text(
                  'Finish allocation and record the reserve fund payments below before completing this trip.',
                ),
              FilledButton.icon(
                icon: const Icon(Icons.task_alt),
                label: const Text('Complete BOHECO trip'),
                onPressed:
                    busy ||
                        rows.any(
                          (b) =>
                              b['state'] == 'review' ||
                              b['state'] == 'handed_over',
                        )
                    ? null
                    : () async {
                        final pending = rows
                            .where((b) => b['state'] == 'awaiting_referral')
                            .toList();
                        final scope = ref
                            .read(authControllerProvider)
                            .value
                            ?.accessScope;
                        if (await confirm(
                              'Complete BOHECO trip?',
                              'Confirm the reserve fund payments are recorded and you reported these uncovered accounts to BOHECO:\n${pending.map((b) => '${b['consumer_name']} (${b['consumer_no']})').join('\n')}',
                            ) &&
                            mounted &&
                            ref
                                    .read(authControllerProvider)
                                    .value
                                    ?.accessScope ==
                                scope) {
                          await action(
                            (r) => r.completeTrip(
                              trip['id'] as String,
                              pending
                                  .map((b) => b['bill_id'] as String)
                                  .toList(),
                            ),
                          );
                        }
                      },
              ),
            ],
            for (final b in rows.where(
              (b) => b['state'] != 'review' && b['state'] != 'settled',
            )) ...[
              const Divider(height: 24),
              line(b),
              if (meter && b['route'] == 'boheco')
                TextButton(
                  onPressed: busy ? null : () => supply(b),
                  child: Text(
                    'Supply status: ${b['supply_status'] ?? 'unknown'}',
                  ),
                ),
              if (meter &&
                  (b['state'] == 'handed_over' ||
                      b['state'] == 'referred' ||
                      b['state'] == 'awaiting_referral'))
                FilledButton(
                  onPressed: busy ? null : () => payment(b),
                  child: Text(
                    b['route'] == 'pondo'
                        ? 'Confirm reserve fund payment to BOHECO'
                        : 'Verify direct payment',
                  ),
                ),
              if (admin && widget.showFund && b['state'] == 'handed_over')
                TextButton(
                  onPressed: busy ? null : () => correction(b),
                  child: const Text('Record returned funds'),
                ),
              if (admin &&
                  widget.showFund &&
                  b['route'] == 'pondo' &&
                  b['state'] == 'awaiting_repayment')
                TextButton(
                  onPressed: busy ? null : () => correction(b),
                  child: const Text('Correct verification'),
                ),
            ],
            if (rows.any((b) => b['state'] == 'settled'))
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Settled bills'),
                children: [
                  for (final b in rows.where((b) => b['state'] == 'settled'))
                    Column(
                      children: [
                        line(b),
                        if (meter)
                          TextButton(
                            onPressed: busy ? null : () => supply(b),
                            child: Text(
                              'Supply status: ${b['supply_status'] ?? 'unknown'}',
                            ),
                          ),
                        Text(
                          b['route'] == 'pondo'
                              ? 'Reserve fund repaid to Cashier'
                              : 'Paid directly to BOHECO · ${b['reference']}',
                        ),
                        if (admin && b['route'] == 'boheco')
                          TextButton(
                            onPressed: busy ? null : () => correction(b),
                            child: const Text('Correct verification'),
                          ),
                      ],
                    ),
                ],
              ),
            if (admin && widget.showFund && snapshot.rows('audit').isNotEmpty)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Verification & corrections'),
                children: [
                  for (final e in snapshot.rows('audit'))
                    ListTile(
                      title: Text('${e['action']}'),
                      subtitle: Text('${e['bill_id'] ?? ''} · ${e['detail']}'),
                    ),
                ],
              ),
            if (!meter && widget.showFund && snapshot.rows('ledger').isNotEmpty)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Reserve fund history'),
                children: [
                  for (final e in snapshot.rows('ledger'))
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        '${e['reason']}'.startsWith(
                              'Meter Reader compensation ',
                            )
                            ? '${e['reason']}'.split(' (salary PHP').first
                            : '${e['reason']}',
                      ),
                      subtitle: Text('${e['kind']} · ${e['occurred_at']}'),
                      trailing: Text(amount(e, 'amount').format()),
                    ),
                ],
              ),
          ],
        );
      },
    );
  }
}

class HouseholdPaymentRoute extends ConsumerWidget {
  const HouseholdPaymentRoute({
    super.key,
    required this.consumerId,
    this.billId,
  });
  final String consumerId;
  final String? billId;
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(householdSettlementsProvider(consumerId))
      .when(
        loading: () => const SizedBox.shrink(),
        error: (e, s) =>
            const Text('Connect to check the latest payment route.'),
        data: (rows) {
          final visible = rows
              .where(
                (b) => billId == null
                    ? b['state'] != 'settled'
                    : b['bill_id'] == billId,
              )
              .toList();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final b in visible)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    '${b['bill_no']} · ${settlementLabel(b['state'] as String)}${b['route'] == 'boheco' && b['state'] == 'settled' ? ' · Paid directly to BOHECO' : ''}',
                  ),
                ),
            ],
          );
        },
      );
}

/// Equal-sized options keep the fund form aligned at phone widths.
class _FundEntryChoice extends StatelessWidget {
  const _FundEntryChoice({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onPressed,
  });
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      selected: selected,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          minimumSize: const Size(0, 80),
          backgroundColor: selected ? colors.primaryContainer : colors.surface,
          foregroundColor: selected
              ? colors.onPrimaryContainer
              : colors.onSurfaceVariant,
          side: BorderSide(
            color: selected ? colors.primary : colors.outlineVariant,
            width: selected ? 1.5 : 1,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: Theme.of(context).textTheme.labelLarge,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(selected ? Icons.check_circle_outline : icon, size: 22),
            const SizedBox(height: 6),
            Text(label, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
