import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/result/result.dart';
import '../../data/repositories/overdue_repository.dart';
import '../../data/supabase/failure_mapper.dart';
import '../../domain/outbox/outbox_entry.dart';
import '../../domain/value_objects/money.dart';
import '../auth/auth_controller.dart';
import '../cashier/receipt_details_sheet.dart';
import '../cashier/receipts_controller.dart';
import '../cashier/record_payment_controller.dart';
import '../providers.dart';
import 'settlement_panel.dart';

final overdueRepositoryProvider = Provider(
  (ref) => OverdueRepository(
    ref.watch(supabaseClientProvider),
    ref.watch(appDatabaseProvider),
  ),
);
final overdueBillsProvider = FutureProvider((ref) async {
  final user = await ref.watch(authControllerProvider.future);
  if (user?.areaId == null) return <OverdueBill>[];
  return ref
      .watch(overdueRepositoryProvider)
      .list(user!.areaId!.value, user.id.value);
});

class OverdueScreen extends ConsumerStatefulWidget {
  const OverdueScreen({
    super.key,
    this.consumerId,
    this.paymentRoute,
    this.onPaymentRecorded,
  });
  final String? consumerId;
  final String? paymentRoute;
  final Future<void> Function()? onPaymentRecorded;
  @override
  ConsumerState<OverdueScreen> createState() => _OverdueScreenState();
}

class _OverdueScreenState extends ConsumerState<OverdueScreen> {
  bool busy = false;
  String? message;
  Future<void> collect(OverdueBill row, bool repayment) async {
    if (busy) return;
    final owner = ref.read(authControllerProvider).value?.accessScope;
    bool current() =>
        mounted && ref.read(authControllerProvider).value?.accessScope == owner;
    if (!ref.read(networkStatusProvider).isOnline) {
      setState(() => message = 'Connect before collecting payment.');
      return;
    }
    final cash = TextEditingController();
    String? error;
    final navigator = Navigator.of(context, rootNavigator: true);
    final dialog = DialogRoute<bool>(
      context: context,
      themes: InheritedTheme.capture(from: context, to: navigator.context),
      builder: (c) => StatefulBuilder(
        builder: (c, update) => AlertDialog(
          title: Text(
            repayment ? 'Collect repayment' : 'Collect full bill payment',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${row.household}\n${row.bill.cycle.displayName} · ${row.bill.balance.format()}',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: cash,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Cash received (₱)',
                ),
              ),
              if (error != null) Text(error!),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final value = Money.tryParse(cash.text);
                if (value == null || value < row.bill.balance) {
                  update(
                    () => error = 'Receive the full amount before confirming.',
                  );
                  return;
                }
                Navigator.pop(c, true);
              },
              child: const Text('Record payment'),
            ),
          ],
        ),
      ),
    );
    final yes = await navigator.push(dialog);
    // The popped route still owns its text field during the exit animation.
    await dialog.completed;
    final tendered = Money.tryParse(cash.text);
    cash.dispose();
    if (!current() || yes != true || tendered == null) return;
    if (!ref.read(networkStatusProvider).isOnline) {
      setState(() => message = 'Connection lost. No payment recorded.');
      return;
    }
    setState(() {
      busy = true;
      message = null;
    });
    try {
      final uuid = ref.read(clientUuidFactoryProvider)();
      final result = await ref.read(recordCashPaymentProvider)(
        consumerLabel: row.household,
        bills: [row.bill],
        amounts: [row.bill.balance],
        cashTendered: tendered,
        clientUuid: uuid,
      );
      if (!current()) return;
      if (result case Err(:final failure)) throw failure;
      await ref.read(syncServiceProvider).syncNow();
      if (!current()) return;
      final queue = await ref.read(outboxRepositoryProvider).all();
      if (!current()) return;
      if (queue case Err(:final failure)) throw failure;
      final entry = (queue as Ok<List<OutboxEntry>>).value
          .where((e) => e.operation.clientUuid == uuid)
          .firstOrNull;
      if (entry?.status != OutboxStatus.synced || entry?.serverId == null) {
        message =
            'Payment confirmation pending. Do not collect again. Sync and check Receipts.';
      } else {
        final receipt = await ref
            .read(paymentRepositoryProvider)
            .byTransaction(entry!.serverId!);
        if (!current()) return;
        if (receipt case Ok(:final value) when value != null) {
          message =
              'Receipt ${value.receiptNo} · Change ${value.changeDue?.format() ?? Money.zero.format()}';
          if (!mounted) return;
          await showCashierReceiptDetails(context, value);
          if (!current()) return;
        } else {
          message = 'Payment recorded. Check Receipts before collecting again.';
        }
      }
      ref.invalidate(receiptsControllerProvider);
      ref.invalidate(overdueBillsProvider);
      ref.invalidate(settlementSnapshotProvider);
      if (widget.onPaymentRecorded != null) {
        await widget.onPaymentRecorded!();
      } else {
        ref.invalidate(recordPaymentControllerProvider);
      }
    } catch (e, s) {
      if (current()) message = FailureMapper.from(e, s).message;
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bills = ref.watch(overdueBillsProvider);
    final snapshot = ref.watch(settlementSnapshotProvider);
    final routes = {
      for (final b in snapshot.value?.rows('bills') ?? <Map<String, dynamic>>[])
        b['bill_id']: b,
    };
    final content = Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Expanded(child: Text('Payment route')),
              IconButton(
                onPressed: busy
                    ? null
                    : () {
                        ref.invalidate(settlementSnapshotProvider);
                        ref.invalidate(overdueBillsProvider);
                      },
                tooltip: 'Refresh payment route',
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        if (message != null)
          Padding(padding: const EdgeInsets.all(16), child: Text(message!)),
        if (busy || snapshot.isLoading) const LinearProgressIndicator(),
        if (snapshot.hasError)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Could not verify the payment route. Refresh online before collecting.',
            ),
          ),
        Expanded(
          child: bills.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, s) =>
                Center(child: Text(FailureMapper.from(e, s).message)),
            data: (list) {
              final rows =
                  list
                      .where(
                        (b) =>
                            (widget.consumerId == null ||
                                b.bill.consumerId.value == widget.consumerId) &&
                            (widget.paymentRoute == null ||
                                (routes[b.bill.id.value]?['route'] ==
                                        widget.paymentRoute &&
                                    routes[b.bill.id.value]?['state'] !=
                                        'settled')),
                      )
                      .toList()
                    ..sort((a, b) => a.bill.cycle.compareTo(b.bill.cycle));
              if (rows.isEmpty) {
                return const Center(
                  child: Text('No outstanding bills in this view.'),
                );
              }
              return ListView(
                children: [
                  for (final b in rows)
                    Card(
                      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              b.household,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Text(
                              '${b.bill.cycle.displayName} · ${b.bill.balance.format()}',
                            ),
                            if (b.consumerNo != null) Text(b.consumerNo!),
                            if (widget.paymentRoute == 'boheco' &&
                                b.bill.isOverdueOn(
                                  ref.watch(phClockProvider).today(),
                                ))
                              const Text('Overdue · Pay directly at BOHECO'),
                            const SizedBox(height: 8),
                            Text(
                              routes[b.bill.id.value] == null
                                  ? 'Pay Cashier before collection closes'
                                  : settlementLabel(
                                      routes[b.bill.id.value]!['state']
                                          as String,
                                    ),
                            ),
                            if (!snapshot.hasError &&
                                !snapshot.isLoading &&
                                (routes[b.bill.id.value] == null ||
                                    routes[b.bill.id.value]!['state'] ==
                                        'awaiting_repayment')) ...[
                              const SizedBox(height: 12),
                              FilledButton(
                                onPressed: busy
                                    ? null
                                    : () => collect(
                                        b,
                                        routes[b.bill.id.value]?['route'] ==
                                            'pondo',
                                      ),
                                child: Text(
                                  routes[b.bill.id.value]?['route'] == 'pondo'
                                      ? 'Collect repayment'
                                      : 'Collect full payment',
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
    return widget.consumerId != null
        ? content
        : Scaffold(
            appBar: AppBar(title: const Text('Outstanding bills')),
            body: SafeArea(child: content),
          );
  }
}
