import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/repositories/billing_schedule_repository.dart';
import '../../data/supabase/failure_mapper.dart';
import '../../domain/entities/app_user.dart';
import '../../domain/entities/billing_schedule.dart';
import '../auth/auth_controller.dart';
import '../common/settlement_panel.dart';
import '../providers.dart';

final billingScheduleRepositoryProvider = Provider(
  (ref) => BillingScheduleRepository(
    ref.watch(supabaseClientProvider),
    ref.watch(appDatabaseProvider),
  ),
);
final billingScheduleProvider = FutureProvider.autoDispose((ref) async {
  final user = await ref.watch(authControllerProvider.future);
  if (user == null || !user.hasWorkAccess) {
    throw StateError('Staff access required.');
  }
  return ref.watch(billingScheduleRepositoryProvider).load(user.accessScope);
});

class BillingScheduleScreen extends ConsumerStatefulWidget {
  const BillingScheduleScreen({super.key});
  @override
  ConsumerState<BillingScheduleScreen> createState() => _BillingScheduleState();
}

class _BillingScheduleState extends ConsumerState<BillingScheduleScreen> {
  BillingSchedule? original;
  int dueDay = 28;
  TimeOfDay time = const TimeOfDay(hour: 12, minute: 0);
  bool saving = false;
  String? message, retryUuid, owner;
  void changed() {
    retryUuid = null;
    message = null;
  }

  Future<void> save() async {
    if (saving || original == null) return;
    final user = ref.read(authControllerProvider).value;
    if (user is! AdminUser || !user.hasWorkAccess) return;
    if (!ref.read(networkStatusProvider).isOnline) {
      setState(() => message = 'Connect to save the billing schedule.');
      return;
    }
    final scope = user.accessScope;
    retryUuid ??= ref.read(clientUuidFactoryProvider)().value;
    setState(() => saving = true);
    try {
      final result = await ref
          .read(billingScheduleRepositoryProvider)
          .save(
            BillingSchedule(
              dueDay: dueDay,
              cutoffDay: dueDay,
              cutoffMinutes: time.hour * 60 + time.minute,
              version: original!.version,
            ),
            retryUuid!,
            scope: scope,
          );
      if (!mounted ||
          ref.read(authControllerProvider).value?.accessScope != scope) {
        return;
      }
      original = result;
      retryUuid = null;
      ref.invalidate(billingScheduleProvider);
      ref.invalidate(settlementSnapshotProvider);
      setState(
        () => message =
            'Schedule saved. Collection changes apply from ${MaterialLocalizations.of(context).formatMonthYear(DateTime.parse(result.effectiveMonth!))}.',
      );
    } catch (e, s) {
      if (mounted &&
          ref.read(authControllerProvider).value?.accessScope == scope) {
        setState(() => message = FailureMapper.from(e, s).message);
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Widget day(String label, int value, void Function(int) update) =>
      DropdownButtonFormField<int>(
        key: ValueKey('$label:${original?.version}'),
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: [
          for (var day = 1; day <= 31; day++)
            DropdownMenuItem(value: day, child: Text('Day $day')),
        ],
        onChanged: saving
            ? null
            : (v) => setState(() {
                update(v!);
                changed();
              }),
      );
  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).value;
    if (owner != user?.accessScope) {
      owner = user?.accessScope;
      original = null;
      retryUuid = null;
      message = null;
    }
    if (user is! AdminUser || !user.hasWorkAccess) {
      return const Scaffold(
        body: Center(child: Text('Area President access required.')),
      );
    }
    final schedule = ref.watch(billingScheduleProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Billing schedule'),
        actions: [
          IconButton(
            tooltip: 'Reload saved schedule',
            onPressed: saving
                ? null
                : () {
                    setState(() {
                      original = null;
                      retryUuid = null;
                      message = null;
                    });
                    ref.invalidate(billingScheduleProvider);
                  },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      bottomNavigationBar: schedule.hasValue
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (message != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(message!),
                      ),
                    FilledButton(
                      onPressed: saving ? null : save,
                      child: Text(saving ? 'Saving…' : 'Save schedule'),
                    ),
                  ],
                ),
              ),
            )
          : null,
      body: SafeArea(
        child: schedule.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, s) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Could not load the billing schedule.'),
                TextButton(
                  onPressed: () => ref.invalidate(billingScheduleProvider),
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
          data: (value) {
            if (original == null) {
              original = value;
              dueDay = value.dueDay;
              time = TimeOfDay(
                hour: value.cutoffMinutes ~/ 60,
                minute: value.cutoffMinutes % 60,
              );
            }
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  'One schedule for your area',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Applies to new bills and future trips. Posted due dates and closed trips stay unchanged.',
                ),
                const SizedBox(height: 24),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        day('Monthly due day', dueDay, (v) => dueDay = v),
                        const SizedBox(height: 8),
                        const Text(
                          'Collection closes at the selected time on the due day. Confirm each bill’s due date against the BOHECO statement.',
                        ),
                        if (original!.dueDay != original!.cutoffDay) ...[
                          const SizedBox(height: 8),
                          Text(
                            'The saved collection day is Day ${original!.cutoffDay}. Saving will align it with the monthly due day.',
                          ),
                        ],
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.schedule),
                          label: Text('Closing time · ${time.format(context)}'),
                          onPressed: saving
                              ? null
                              : () async {
                                  final scope = user.accessScope;
                                  final picked = await showTimePicker(
                                    context: context,
                                    initialTime: time,
                                  );
                                  if (mounted &&
                                      picked != null &&
                                      ref
                                              .read(authControllerProvider)
                                              .value
                                              ?.accessScope ==
                                          scope) {
                                    setState(() {
                                      time = picked;
                                      changed();
                                    });
                                  }
                                },
                        ),
                        const SizedBox(height: 12),
                        const Text('Timezone · Philippine time (UTC+8)'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Days beyond a month’s length use its last day. Bills become overdue after their due date ends. Meter Reader can still close collection earlier for a trip.',
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
