import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../data/local/query_cache.dart';
import '../../data/network/foreground_poll.dart';
import '../../data/notifications/staff_phone_alerts.dart';
import '../../data/supabase/failure_mapper.dart';
import '../../domain/entities/app_user.dart';
import '../../domain/notifications/phone_alerts.dart';
import '../admin/disconnections_screen.dart';
import '../admin/post_bill_amount_controller.dart';
import '../auth/auth_controller.dart';
import '../cashier/receipts_controller.dart';
import '../cashier/record_payment_controller.dart';
import '../providers.dart';
import '../reader/roster_controller.dart';
import 'overdue_screen.dart';
import 'saved_list_time.dart';

final staffAlertsProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  final user = await ref.watch(authControllerProvider.future);
  if (user == null || user is ConsumerUser) return [];
  return QueryCache(ref.watch(appDatabaseProvider)).rows(
    'staff-alerts:${user.id.value}',
    () => ref
        .read(supabaseClientProvider)
        .from('staff_alerts')
        .select()
        .eq('recipient_id', user.id.value)
        .order('created_at', ascending: false)
        .limit(100),
  );
});

bool staffDestinationAllowed(AppUser user, String destination) =>
    switch (user.roleCode) {
      'admin' => const [
        '/admin',
        '/admin/overdue',
        '/admin/disconnections',
        '/admin/profile',
      ].contains(destination),
      'cashier' => const [
        '/cashier',
        '/cashier/overdue',
        '/cashier/remit',
        '/cashier/profile',
      ].contains(destination),
      'meter_reader' => const [
        '/reader',
        '/reader/remittance',
        '/reader/profile',
      ].contains(destination),
      _ => false,
    };

class StaffAlertsGate extends ConsumerStatefulWidget {
  final Widget child;
  final bool managePhone;
  const StaffAlertsGate({
    required this.child,
    this.managePhone = true,
    super.key,
  });
  @override
  ConsumerState<StaffAlertsGate> createState() => _StaffAlertsGateState();
}

class _StaffAlertsGateState extends ConsumerState<StaffAlertsGate> {
  late final ForegroundPoll _poll;
  StreamSubscription<dynamic>? _sync;
  late final AppLifecycleListener _lifecycle;
  String? _device;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _poll = ForegroundPoll(ref.read(networkStatusProvider), _refresh);
    _lifecycle = AppLifecycleListener(onResume: _resume, onPause: _poll.pause);
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  void _open(String? payload) {
    if (!mounted || payload == null) return;
    final user = ref.read(authControllerProvider).value;
    if (user == null) return;
    final prefix = 'staff:${user.id.value}:';
    if (!payload.startsWith(prefix)) return;
    final destination = payload.substring(prefix.length);
    if (staffDestinationAllowed(user, destination)) context.go(destination);
  }

  Future<void> _start() async {
    try {
      final phone = ref.read(phoneNotifierProvider);
      if (widget.managePhone) await phone.initialize(onTap: _open);
      if (!mounted) return;
      if (widget.managePhone) _open(await phone.launchPayload());
      await ref.read(notificationPermissionProvider).request();
      _device = await staffAlertDeviceId();
      if (!mounted) return;
      await ref.read(backgroundAlertsProvider).start();
      _sync = ref.read(syncServiceProvider).reports.listen((report) async {
        if (!mounted || !report.didAnything) return;
        final user = ref.read(authControllerProvider).value;
        if (user == null || user is ConsumerUser) return;
        // One summary per drain, rather than an alert for every uploaded row.
        try {
          await phone.show(
            PhoneNotice(
              id: stableNoticeId('sync:${user.id.value}'),
              title: report.failed > 0
                  ? 'Some work needs attention'
                  : 'Sync complete',
              body: report.failed > 0
                  ? 'Open Profile to review work that has not synced.'
                  : '${report.succeeded} items reached the server.',
              payload: 'staff:${user.id.value}:${user.homeRoute}/profile',
            ),
          );
        } catch (_) {}
        if (mounted && report.succeeded > 0) _refreshWork();
      });
    } catch (_) {
      /* Inbox and Profile remain available without tray support. */
    } finally {
      _resume();
    }
  }

  void _resume() {
    if (!mounted) return;
    _poll.resume();
  }

  Future<void> _refresh() async {
    if (!mounted || _busy || !ref.read(networkStatusProvider).isOnline) return;
    final scope = ref.read(authControllerProvider).value?.accessScope;
    _busy = true;
    try {
      if (_device != null) {
        await refreshStaffPhoneAlerts(
          ref.read(supabaseClientProvider),
          ref.read(phoneNotifierProvider),
          _device!,
        );
      }
    } catch (_) {
      /* The next foreground/background interval retries. */
    } finally {
      if (mounted &&
          _poll.active &&
          ref.read(networkStatusProvider).isOnline &&
          ref.read(authControllerProvider).value?.accessScope == scope) {
        ref.invalidate(staffAlertsProvider);
        _refreshWork();
      }
      _busy = false;
    }
  }

  void _refreshWork() {
    final user = ref.read(authControllerProvider).value;
    if (user is AdminUser) {
      ref.invalidate(activeNoticesProvider);
      ref.invalidate(closedNoticesProvider);
      if (ref.read(postBillAmountControllerProvider).posting == null) {
        unawaited(
          ref.read(postBillAmountControllerProvider.notifier).refresh(),
        );
      }
      ref.invalidate(overdueBillsProvider);
    }
    if (user is MeterReaderUser) ref.invalidate(initialRosterRefreshProvider);
    if (user is CashierUser) {
      ref.invalidate(overdueBillsProvider);
      ref.invalidate(receiptsControllerProvider);
      final state = ref.read(recordPaymentControllerProvider);
      if (state.selected == null && !state.isSubmitting) {
        ref.invalidate(recordPaymentControllerProvider);
      }
    }
  }

  @override
  void dispose() {
    _poll.dispose();
    _lifecycle.dispose();
    unawaited(_sync?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class StaffAlertsScreen extends ConsumerWidget {
  const StaffAlertsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(
      title: const Text('Staff notifications'),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () => ref.invalidate(staffAlertsProvider),
          tooltip: 'Refresh',
        ),
      ],
    ),
    body: ref
        .watch(staffAlertsProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, s) =>
              Center(child: Text(FailureMapper.from(e, s).message)),
          data: (rows) => rows.isEmpty
              ? const Center(
                  child: Text('No staff notifications in the saved view.'),
                )
              : ListView(
                  children: [
                    SavedListTime(
                      cacheKey:
                          'staff-alerts:${ref.watch(authControllerProvider).value?.id.value}',
                    ),
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'Saved notifications remain available offline. Refresh online for the latest work.',
                      ),
                    ),
                    for (final row in rows)
                      ListTile(
                        leading: Icon(
                          row['is_read'] == true
                              ? Icons.notifications_none
                              : Icons.notifications_active,
                        ),
                        title: Text(row['title'] as String),
                        subtitle: Text('${row['body']}\n${row['created_at']}'),
                        onTap: () async {
                          final user = ref.read(authControllerProvider).value;
                          final destination = row['destination'] as String;
                          if (user == null ||
                              row['recipient_id'] != user.id.value ||
                              !staffDestinationAllowed(user, destination)) {
                            return;
                          }
                          try {
                            await ref
                                .read(supabaseClientProvider)
                                .rpc(
                                  'fn_read_staff_alert',
                                  params: {'p_alert': row['id']},
                                );
                            ref.invalidate(staffAlertsProvider);
                          } catch (_) {}
                          if (context.mounted &&
                              ref.read(authControllerProvider).value?.id ==
                                  user.id) {
                            context.go(destination);
                          }
                        },
                      ),
                  ],
                ),
        ),
  );
}
