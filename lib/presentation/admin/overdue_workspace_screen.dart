import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/app_failure.dart';
import '../../core/result/result.dart';
import '../../data/repositories/overdue_repository.dart';
import '../../data/supabase/failure_mapper.dart';
import '../../domain/entities/app_user.dart';
import '../../domain/outbox/outbox_operation.dart';
import '../../domain/repositories/notice_repository.dart';
import '../../domain/value_objects/money.dart';
import '../auth/auth_controller.dart';
import '../common/overdue_screen.dart';
import '../common/profile_screen.dart';
import '../common/section_tabs.dart';
import '../common/settlement_panel.dart';
import '../common/staff_app_bar.dart';
import '../providers.dart';
import '../router.dart';
import 'disconnections_screen.dart';

final overdueHistoryProvider = FutureProvider((ref) async {
  final user = await ref.watch(authControllerProvider.future);
  if (user is! AdminUser || user.areaId == null) {
    return <Map<String, dynamic>>[];
  }
  return ref
      .watch(overdueRepositoryProvider)
      .history(user.areaId!.value, user.id.value);
});

/// Collection and notice state stay distinct within a household's case.
class OverdueHouseholdCase {
  OverdueHouseholdCase(this.id, this.label);
  final String id, label;
  final bills = <OverdueBill>[];
  final notices = <ActiveNotice>[];
  final pending = <IssueNoticeOperation>[];
  Money get balance =>
      bills.fold(Money.zero, (sum, row) => sum + row.bill.balance);
  bool get requested => bills.any((row) => row.isRequested);
  bool get authorized =>
      bills.isNotEmpty && bills.every((row) => row.isApproved);
  bool get ready => notices.any((notice) => notice.readyToClose);
}

List<OverdueHouseholdCase> groupOverdueHouseholds(
  List<OverdueBill> bills,
  List<ActiveNotice> notices,
  List<IssueNoticeOperation> pending,
) {
  final cases = <String, OverdueHouseholdCase>{};
  OverdueHouseholdCase household(String id, String label) =>
      cases.putIfAbsent(id, () => OverdueHouseholdCase(id, label));
  for (final row in bills) {
    household(row.bill.consumerId.value, row.household).bills.add(row);
  }
  for (final notice in notices) {
    household(
      notice.consumerId.value,
      notice.consumerLabel,
    ).notices.add(notice);
  }
  for (final notice in pending) {
    household(
      notice.consumerId.value,
      notice.consumerLabel,
    ).pending.add(notice);
  }
  return cases.values.toList()..sort((a, b) {
    final priority = (b.requested || b.ready ? 1 : 0).compareTo(
      a.requested || a.ready ? 1 : 0,
    );
    return priority != 0 ? priority : a.label.compareTo(b.label);
  });
}

class AdminOverdueWorkspaceScreen extends ConsumerStatefulWidget {
  const AdminOverdueWorkspaceScreen({super.key, this.initialHistory = false});
  final bool initialHistory;
  @override
  ConsumerState<AdminOverdueWorkspaceScreen> createState() => _WorkspaceState();
}

class _WorkspaceState extends ConsumerState<AdminOverdueWorkspaceScreen> {
  late String tab = widget.initialHistory ? 'History' : 'Pay at BOHECO';
  String search = '';
  String? selected, message;
  bool busy = false;

  void refresh() {
    ref.invalidate(settlementSnapshotProvider);
    ref.invalidate(overdueBillsProvider);
    ref.invalidate(activeNoticesProvider);
    ref.invalidate(closedNoticesProvider);
    ref.invalidate(overdueHistoryProvider);
    ref.invalidate(pendingOutboxProvider);
  }

  Future<void> decide(OverdueBill row, String action) async {
    if (busy) return;
    final scope = ref.read(authControllerProvider).value?.accessScope;
    bool current() =>
        mounted && ref.read(authControllerProvider).value?.accessScope == scope;
    if (!ref.read(networkStatusProvider).isOnline) {
      setState(() => message = 'Connect to authorize collection.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          action == 'approved'
              ? 'Authorize collection?'
              : 'Revoke authorization?',
        ),
        content: Text(
          '${row.household}\n${row.bill.cycle.displayName} · ${row.bill.balance.format()}\nThe Cashier records payment after receiving cash.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (!current() || confirmed != true) return;
    if (!ref.read(networkStatusProvider).isOnline) {
      setState(
        () => message = 'Connection lost. Refresh online before authorizing.',
      );
      return;
    }
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await ref
          .read(overdueRepositoryProvider)
          .decide(row.bill.id.value, action);
      if (!current()) return;
      setState(
        () => message = action == 'approved'
            ? 'Collection authorized. Awaiting Cashier payment.'
            : 'Authorization revoked.',
      );
      refresh();
    } catch (error, stack) {
      if (current()) {
        setState(() => message = FailureMapper.from(error, stack).message);
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> authorizeTogether(OverdueHouseholdCase household) async {
    if (busy) return;
    if (!ref.read(networkStatusProvider).isOnline) {
      setState(() => message = 'Connect to authorize collection.');
      return;
    }
    final scope = ref.read(authControllerProvider).value?.accessScope;
    final selectedIds = household.bills
        .where((row) => !row.isApproved)
        .map((row) => row.bill.id.value)
        .toSet();
    final chosen = await showDialog<List<OverdueBill>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) {
          final selectedRows = household.bills
              .where((row) => selectedIds.contains(row.bill.id.value))
              .toList();
          final total = selectedRows.fold(
            Money.zero,
            (sum, row) => sum + row.bill.balance,
          );
          return AlertDialog(
            title: const Text('Authorize overdue bills?'),
            content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(household.label),
                    const SizedBox(height: 12),
                    for (final row in household.bills)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(row.bill.cycle.displayName),
                        subtitle: Text(
                          '${row.bill.balance.format()}${row.isApproved ? ' · Already authorized' : ''}',
                        ),
                        value:
                            row.isApproved ||
                            selectedIds.contains(row.bill.id.value),
                        onChanged: row.isApproved
                            ? null
                            : (checked) => update(() {
                                if (checked == true) {
                                  selectedIds.add(row.bill.id.value);
                                } else {
                                  selectedIds.remove(row.bill.id.value);
                                }
                              }),
                      ),
                    const SizedBox(height: 12),
                    Text('${selectedRows.length} selected · ${total.format()}'),
                    const Text(
                      'The Cashier records payment after receiving cash.',
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: selectedRows.isEmpty
                    ? null
                    : () => Navigator.pop(context, selectedRows),
                child: const Text('Authorize selected bills'),
              ),
            ],
          );
        },
      ),
    );
    bool current() =>
        mounted && ref.read(authControllerProvider).value?.accessScope == scope;
    if (!current() || chosen == null || chosen.isEmpty) return;
    if (!ref.read(networkStatusProvider).isOnline) {
      setState(
        () => message = 'Connection lost. Refresh online before authorizing.',
      );
      return;
    }
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await ref.read(overdueRepositoryProvider).authorizeBatch(chosen);
      if (!current()) return;
      setState(
        () => message =
            '${chosen.length} bills authorized. Awaiting Cashier payment.',
      );
      refresh();
    } catch (error, stack) {
      if (current()) {
        final failure = FailureMapper.from(error, stack);
        setState(
          () => message = failure is NetworkFailure
              ? 'Authorization could not be confirmed. Refresh online before trying again.'
              : failure.message,
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> settle(ActiveNotice notice) async {
    if (busy) return;
    if (!ref.read(networkStatusProvider).isOnline) {
      setState(
        () => message = 'Connect to verify receipts and close this notice.',
      );
      return;
    }
    final scope = ref.read(authControllerProvider).value?.accessScope;
    bool current() =>
        mounted && ref.read(authControllerProvider).value?.accessScope == scope;
    setState(() {
      busy = true;
      message = null;
    });
    try {
      final result = await ref.read(noticeRepositoryProvider).review(notice.id);
      if (!mounted || !current()) return;
      if (result case Err(:final failure)) {
        throw failure;
      }
      final review = (result as Ok<NoticeReview?>).value;
      if (review == null || !review.readyToClose) {
        setState(
          () => message =
              'Payment is not confirmed or this notice has already closed. Refresh and review its receipts.',
        );
        refresh();
        return;
      }
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Close this paid notice?'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${review.notice.consumerLabel}\n${review.notice.noticeNo}',
                ),
                const SizedBox(height: 12),
                const Text(
                  'The bills listed in this notice are paid and no overdue balance remains. Closing moves the notice to History; it does not change the electricity connection.',
                ),
                for (final receipt in review.receipts)
                  Text('${receipt.receiptNo} · ${receipt.amount.format()}'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Close notice — Paid'),
            ),
          ],
        ),
      );
      if (!current() || confirmed != true) return;
      if (!ref.read(networkStatusProvider).isOnline) {
        throw const NetworkFailure();
      }
      final closed = await ref.read(recordNoticeOutcomeProvider)(
        noticeId: notice.id,
        outcome: NoticeOutcome.settled,
      );
      if (!current()) return;
      if (closed case Err(:final failure)) throw failure;
      setState(
        () => message = 'Paid notice closed. You can find it in History.',
      );
      refresh();
    } catch (error, stack) {
      if (current()) {
        final failure = FailureMapper.from(error, stack);
        setState(
          () => message = failure is NetworkFailure
              ? 'Closure could not be confirmed. Refresh online before trying again.'
              : failure.message,
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
      authControllerProvider.select((state) => state.value?.accessScope),
      (previous, next) {
        if (previous != next) {
          setState(() {
            selected = null;
            message = null;
            search = '';
          });
        }
      },
    );
    final user = ref.watch(authControllerProvider).value;
    if (user is! AdminUser) {
      return const Scaffold(
        body: Center(child: Text('Area President access required.')),
      );
    }
    final bills = ref.watch(overdueBillsProvider);
    final notices = ref.watch(activeNoticesProvider);
    final uploads = ref.watch(pendingOutboxProvider);
    final pending = (uploads.value ?? [])
        .map((e) => e.operation)
        .whereType<IssueNoticeOperation>()
        .toList();
    final cases = groupOverdueHouseholds(
      bills.value ?? [],
      notices.value ?? [],
      pending,
    );
    final household = cases.where((c) => c.id == selected).firstOrNull;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: const StaffAppBar(title: 'Bill follow-up'),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            refresh();
            try {
              if (tab == 'History') {
                await ref.read(overdueHistoryProvider.future);
                await ref.read(closedNoticesProvider.future);
              } else {
                await ref.read(overdueBillsProvider.future);
                await ref.read(activeNoticesProvider.future);
              }
            } catch (_) {
              // Each section renders its own loading error and retry action.
            }
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              SectionTabs(
                labels: const [
                  'Pay at BOHECO',
                  'Disconnection notices',
                  'History',
                ],
                selected: tab,
                onChanged: (value) => setState(() {
                  tab = value;
                  selected = null;
                  search = '';
                }),
              ),
              const SizedBox(height: 12),
              if (busy) const LinearProgressIndicator(),
              if (message != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(message!),
                ),
              if (tab != 'History') ...[
                if (tab != 'Pay at BOHECO' &&
                    (bills.hasError || notices.hasError || uploads.hasError))
                  TextButton.icon(
                    onPressed: refresh,
                    icon: const Icon(Icons.refresh),
                    label: const Text(
                      'Some records could not load. Refresh online.',
                    ),
                  ),
                if (tab != 'Pay at BOHECO' &&
                    (bills.isLoading || notices.isLoading))
                  const LinearProgressIndicator(),
                if (selected == null) ...[
                  if (tab == 'Pay at BOHECO')
                    const SettlementPanel(showFund: false, directOnly: true)
                  else
                    _noticeInbox(
                      cases
                          .where((c) => c.label.toLowerCase().contains(search))
                          .toList(),
                      unavailable:
                          notices.hasError ||
                          notices.isLoading ||
                          uploads.hasError ||
                          uploads.isLoading,
                    ),
                ] else ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => setState(() => selected = null),
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('All households'),
                    ),
                  ),
                  if (household == null)
                    const Text(
                      'This case has cleared or is no longer in the saved view.',
                    ),
                  if (household != null) ...[
                    Text(household.label, style: text.titleLarge),
                    const SizedBox(height: 16),
                    if (tab == 'Pay at BOHECO') ...[
                      Text('Reserve fund', style: text.titleMedium),
                      if (household.bills.length > 1 && !household.authorized)
                        FilledButton(
                          onPressed: busy
                              ? null
                              : () => authorizeTogether(household),
                          child: const Text('Authorize overdue bills'),
                        ),
                      for (final row in household.bills)
                        _collection(row, grouped: household.bills.length > 1),
                      if (household.bills.isEmpty)
                        const Text(
                          'No unpaid overdue balance in the saved view.',
                        ),
                    ],
                  ],
                ],
              ] else
                _History(),
            ],
          ),
        ),
      ),
    );
  }

  // Retained for older workspace tests; the Reserve fund tab uses SettlementPanel.
  // ignore: unused_element
  Widget _collectionInbox(
    List<OverdueHouseholdCase> cases, {
    required bool unavailable,
  }) {
    final requests = cases.where((c) => c.requested).toList();
    final waiting = cases.where((c) => c.authorized).toList();
    final other = cases.where((c) => !c.requested && !c.authorized).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Collection requests',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 4),
        Text(
          '${requests.length} ${requests.length == 1 ? 'household' : 'households'}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        if (requests.isEmpty && !unavailable)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Text('No collection requests waiting.'),
          ),
        for (final c in requests) _collectionCase(c, action: true),
        if (waiting.isNotEmpty)
          ExpansionTile(
            key: const PageStorageKey('admin-awaiting-payment'),
            tilePadding: EdgeInsets.zero,
            title: Text('Awaiting payment · ${waiting.length}'),
            children: [
              for (final c in waiting) _collectionCase(c, action: false),
            ],
          ),
        if (other.isNotEmpty)
          ExpansionTile(
            key: const PageStorageKey('admin-other-overdue'),
            tilePadding: EdgeInsets.zero,
            title: Text('Other overdue households · ${other.length}'),
            children: [for (final c in other) _collectionCase(c, action: true)],
          ),
      ],
    );
  }

  Widget _collectionCase(
    OverdueHouseholdCase c, {
    required bool action,
  }) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              c.label,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            subtitle: Text(
              '${c.balance.format()} · ${c.bills.length} overdue ${c.bills.length == 1 ? 'bill' : 'bills'}',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => setState(() {
              selected = c.id;
              message = null;
            }),
          ),
          if (action) ...[
            const SizedBox(height: 12),
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              onPressed: busy
                  ? null
                  : () => c.bills.length == 1
                        ? decide(c.bills.single, 'approved')
                        : authorizeTogether(c),
              child: Text(
                c.bills.length == 1
                    ? 'Authorize collection'
                    : 'Authorize overdue bills',
              ),
            ),
          ],
        ],
      ),
    ),
  );

  Widget _noticeInbox(
    List<OverdueHouseholdCase> cases, {
    required bool unavailable,
  }) {
    final ready = [
      for (final c in cases)
        for (final n in c.notices)
          if (n.readyToClose) (household: c, notice: n),
    ];
    final active = [
      for (final c in cases)
        for (final n in c.notices)
          if (!n.readyToClose) (household: c, notice: n),
    ];
    final pending = [for (final c in cases) ...c.pending];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Warnings for unpaid, overdue bills reported to BOHECO.'),
        const SizedBox(height: 12),
        FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          onPressed: busy || unavailable
              ? null
              : () async {
                  await context.push(Routes.serveNotice);
                  if (mounted) refresh();
                },
          icon: const Icon(Icons.add),
          label: const Text('Serve a notice'),
        ),
        const SizedBox(height: 16),
        TextField(
          key: const ValueKey('overdue-search'),
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Search household or account',
          ),
          onChanged: (value) =>
              setState(() => search = value.trim().toLowerCase()),
        ),
        const SizedBox(height: 20),
        if (active.isNotEmpty) ...[
          Text(
            'Awaiting payment · ${active.length}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          for (final item in active) _noticeCase(item.household, item.notice),
        ],
        if (ready.isNotEmpty) ...[
          if (active.isNotEmpty) const SizedBox(height: 20),
          Text(
            'Payment verified · ${ready.length}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          const Text('Review payment evidence, then close the notice.'),
          const SizedBox(height: 8),
          for (final item in ready) _noticeCase(item.household, item.notice),
        ],
        if (active.isEmpty && ready.isEmpty && !unavailable)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              search.isEmpty
                  ? 'No active disconnection notices.'
                  : 'No notices match your search.',
            ),
          ),
        if (pending.isNotEmpty)
          ExpansionTile(
            key: const PageStorageKey('admin-notices-pending'),
            tilePadding: EdgeInsets.zero,
            title: Text('Pending sync · ${pending.length}'),
            children: [
              for (final notice in pending)
                ListTile(
                  leading: const Icon(Icons.cloud_upload_outlined),
                  title: Text(notice.consumerLabel),
                  subtitle: const Text('Saved on this device · Check Sync'),
                  onTap: () => context.push('/admin/profile'),
                ),
            ],
          ),
        const SizedBox(height: 16),
        Text(
          'Closed notices appear in History.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _noticeCase(OverdueHouseholdCase c, ActiveNotice notice) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              c.label,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            subtitle: Text(notice.noticeNo),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              await context.push(Routes.noticeDocumentFor(notice.id.value));
              if (mounted) refresh();
            },
          ),
          const SizedBox(height: 8),
          Text(
            notice.readyToClose ? 'Payment verified' : 'Awaiting payment',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 4),
          if (notice.readyToClose)
            const Text('Payment evidence is available for review.')
          else ...[
            Text('${notice.amountOverdue.format()} overdue'),
            const Text('Pay at BOHECO main office'),
            const SizedBox(height: 8),
            Text(
              notice.periodElapsed
                  ? 'Notice period elapsed · BOHECO handles disconnection.'
                  : 'Notice period: ${notice.hoursRemaining}h remaining',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () async {
                  await context.push(Routes.noticeDocumentFor(notice.id.value));
                  if (mounted) refresh();
                },
                child: const Text('View notice'),
              ),
            ),
          ],
          if (notice.readyToClose) ...[
            const SizedBox(height: 12),
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              onPressed: busy ? null : () => settle(notice),
              child: const Text('Close notice — Paid'),
            ),
          ],
        ],
      ),
    ),
  );

  Widget _collection(OverdueBill row, {bool grouped = false}) {
    final approved = row.isApproved;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${row.bill.cycle.displayName} · ${row.bill.balance.format()}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              approved
                  ? 'Authorized · Awaiting Cashier payment'
                  : row.isRequested
                  ? 'Cashier requested collection'
                  : 'Needs authorization',
            ),
            if (!grouped || approved) ...[
              const SizedBox(height: 12),
              FilledButton(
                onPressed: busy
                    ? null
                    : () => decide(row, approved ? 'revoked' : 'approved'),
                child: Text(
                  approved ? 'Revoke authorization' : 'Authorize collection',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _History extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collections = ref.watch(overdueHistoryProvider);
    final notices = ref.watch(closedNoticesProvider);
    final records = <({DateTime at, Widget tile})>[];
    for (final row in collections.value ?? <Map<String, dynamic>>[]) {
      final bill = Map<String, dynamic>.from(row['bills'] as Map);
      final person = Map<String, dynamic>.from(bill['consumers'] as Map);
      records.add((
        at: DateTime.parse(row['occurred_at'] as String),
        tile: Card(
          child: ListTile(
            leading: const Icon(Icons.receipt_long_outlined),
            title: Text(
              '${person['first_name']} ${person['last_name']} · ${person['consumer_no']}',
            ),
            subtitle: Text(
              '${row['action'] == 'consumed' ? 'Overdue payment recorded' : 'Authorization revoked'}\n${bill['bill_no']} · ${Money.parse('${row['amount']}').format()}',
            ),
          ),
        ),
      ));
    }
    for (final notice in notices.value ?? <ClosedNotice>[]) {
      records.add((
        at: notice.closedAt,
        tile: Card(
          child: ListTile(
            leading: const Icon(Icons.description_outlined),
            title: Text(notice.household),
            subtitle: Text(
              '${notice.noticeNo} · Closed as ${notice.outcome.code}',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () =>
                context.push(Routes.noticeDocumentFor(notice.id.value)),
          ),
        ),
      ));
    }
    records.sort((a, b) => b.at.compareTo(a.at));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Refresh online for the latest records.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (collections.isLoading || notices.isLoading)
          const LinearProgressIndicator(),
        if (collections.hasError || notices.hasError)
          TextButton(
            onPressed: () {
              ref.invalidate(overdueHistoryProvider);
              ref.invalidate(closedNoticesProvider);
            },
            child: const Text('History could not fully load. Refresh online.'),
          ),
        if (records.isEmpty &&
            !collections.isLoading &&
            !notices.isLoading &&
            !collections.hasError &&
            !notices.hasError)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(child: Text('No completed cases yet.')),
          ),
        for (final record in records) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
            child: Text(
              _date(record.at),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          record.tile,
        ],
      ],
    );
  }

  String _date(DateTime at) {
    final ph = at.toUtc().add(const Duration(hours: 8));
    return '${ph.day}/${ph.month}/${ph.year} · ${ph.hour.toString().padLeft(2, '0')}:${ph.minute.toString().padLeft(2, '0')} PH';
  }
}
