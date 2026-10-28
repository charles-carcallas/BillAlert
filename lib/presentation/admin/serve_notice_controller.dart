import 'dart:async';

// `Consumer` here means a household. Riverpod's widget of that name is not
// used in this file.
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Consumer;

import '../../core/errors/app_failure.dart';
import '../../core/result/result.dart';
import '../../data/supabase/failure_mapper.dart';
import '../../domain/entities/consumer.dart';
import '../../domain/outbox/outbox_entry.dart';
import '../../domain/outbox/outbox_operation.dart';
import '../../domain/repositories/notice_repository.dart';
import '../../domain/value_objects/ids.dart';
import '../../domain/value_objects/money.dart';
import '../auth/auth_controller.dart';
import '../common/overdue_screen.dart';
import '../common/settlement_panel.dart';
import '../providers.dart';

/// Serving a disconnection notice.
final class ServeNoticeState {
  final List<Consumer> households;

  final Map<String, Money> overdueAmounts;
  final Set<String> blockedHouseholds;
  final String query;
  final Consumer? selected;
  final bool isLoading;
  final bool isSubmitting;
  final AppFailure? failure;

  /// Set once a notice has been queued, so the screen can confirm it.
  final String? servedTo;

  const ServeNoticeState({
    this.households = const <Consumer>[],
    this.overdueAmounts = const <String, Money>{},
    this.blockedHouseholds = const <String>{},
    this.query = '',
    this.selected,
    this.isLoading = false,
    this.isSubmitting = false,
    this.failure,
    this.servedTo,
  });

  ServeNoticeState copyWith({
    List<Consumer>? households,
    Map<String, Money>? overdueAmounts,
    Set<String>? blockedHouseholds,
    String? query,
    Consumer? selected,
    bool? isLoading,
    bool? isSubmitting,
    AppFailure? failure,
    String? servedTo,
    bool clearSelected = false,
  }) {
    return ServeNoticeState(
      households: households ?? this.households,
      overdueAmounts: overdueAmounts ?? this.overdueAmounts,
      blockedHouseholds: blockedHouseholds ?? this.blockedHouseholds,
      query: query ?? this.query,
      selected: clearSelected ? null : (selected ?? this.selected),
      isLoading: isLoading ?? this.isLoading,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      failure: failure,
      servedTo: servedTo,
    );
  }

  List<Consumer> get visible {
    final q = query.trim().toLowerCase();
    return households
        .where(
          (c) =>
              canServe(c) &&
              (q.isEmpty ||
                  c.fullName.toLowerCase().contains(q) ||
                  c.consumerNo.value.toLowerCase().contains(q)),
        )
        .toList();
  }

  Money overdueAmountFor(Consumer c) =>
      overdueAmounts[c.id.value] ?? Money.zero;

  bool canServe(Consumer c) =>
      c.isActive &&
      overdueAmountFor(c) > Money.zero &&
      !blockedHouseholds.contains(c.id.value);
}

/// DOM-05 — the Area President serves a disconnection notice.
///
/// The household list comes from the encrypted cache, refreshed from the
/// server on demand. The Admin is at a desk with signal, but reusing the
/// cache means this screen behaves the same way the reader's does and needs
/// no second code path.
class ServeNoticeController extends Notifier<ServeNoticeState> {
  Future<void>? _inFlight;
  int _generation = 0;

  @override
  ServeNoticeState build() {
    ref.watch(
      authControllerProvider.select((s) => (s.value?.id, s.value?.areaId)),
    );
    _generation++;
    _inFlight = null;
    Future<void>.microtask(load);
    return const ServeNoticeState(isLoading: true);
  }

  Future<void> load() {
    final Future<void>? existing = _inFlight;
    if (existing != null) return existing;
    final Future<void> load = _doLoad().whenComplete(() => _inFlight = null);
    _inFlight = load;
    return load;
  }

  Future<void> _doLoad({bool fromServer = false}) async {
    final generation = _generation;
    final user = await ref.read(authControllerProvider.future);
    if (!ref.mounted || generation != _generation) return;
    final AreaId? areaId = user?.areaId;

    if (areaId == null) {
      state = const ServeNoticeState(
        failure: PermissionFailure(
          'Only an Area President serves a notice, and no service area is '
          'attached to the account you are signed in with.',
        ),
      );
      return;
    }

    state = state.copyWith(isLoading: true);
    final consumers = ref.read(consumerRepositoryProvider);

    if (fromServer) {
      // A failed refresh keeps whatever is already cached: an out-of-date
      // list is worth more than an empty one.
      await consumers.refreshAreaRoster(areaId);
    }

    try {
      final rosterResult = await consumers.areaRoster(areaId);
      if (!ref.mounted || generation != _generation) return;
      final noticesResult = await ref
          .read(noticeRepositoryProvider)
          .activeFor(areaId);
      if (!ref.mounted || generation != _generation) return;
      final pendingResult = await ref.read(outboxRepositoryProvider).pending();
      if (!ref.mounted || generation != _generation) return;
      ref.invalidate(overdueBillsProvider);
      final bills = await ref.read(overdueBillsProvider.future);
      if (!ref.mounted || generation != _generation) return;
      if (rosterResult case Err(:final failure)) throw failure;
      if (noticesResult case Err(:final failure)) throw failure;
      if (pendingResult case Err(:final failure)) throw failure;
      ref.invalidate(settlementSnapshotProvider);
      final snapshot = await ref.read(settlementSnapshotProvider.future);
      if (!ref.mounted || generation != _generation) return;
      final referred = {
        for (final b in snapshot.rows('bills'))
          if (b['route'] == 'boheco' &&
              b['state'] == 'referred' &&
              b['referred_at'] != null)
            b['bill_id'],
      };
      final today = ref.read(phClockProvider).today();
      final amounts = <String, Money>{};
      for (final row in bills) {
        if (!referred.contains(row.bill.id.value) ||
            !row.bill.isOverdueOn(today)) {
          continue;
        }
        final id = row.bill.consumerId.value;
        amounts[id] = (amounts[id] ?? Money.zero) + row.bill.balance;
      }
      final blocked = <String>{
        for (final notice in (noticesResult as Ok<List<ActiveNotice>>).value)
          notice.consumerId.value,
        for (final entry in (pendingResult as Ok<List<OutboxEntry>>).value)
          if (entry.operation is IssueNoticeOperation)
            (entry.operation as IssueNoticeOperation).consumerId.value,
      };
      final next = state.copyWith(
        households: (rosterResult as Ok<List<Consumer>>).value,
        overdueAmounts: amounts,
        blockedHouseholds: blocked,
        isLoading: false,
      );
      state = next.copyWith(
        clearSelected: next.selected != null && !next.canServe(next.selected!),
      );
    } catch (error, stack) {
      if (!ref.mounted || generation != _generation) return;
      state = state.copyWith(
        overdueAmounts: const {},
        isLoading: false,
        clearSelected: true,
        failure: error is AppFailure ? error : FailureMapper.from(error, stack),
      );
    }
  }

  Future<void> refreshFromServer() => _doLoad(fromServer: true);

  void search(String query) => state = state.copyWith(query: query);

  void select(Consumer household) {
    if (!state.isLoading && state.canServe(household)) {
      state = state.copyWith(selected: household);
    }
  }

  void clearSelection() => state = state.copyWith(clearSelected: true);

  /// Queues the notice. `capturedAt` is stamped now, and the 48-hour period
  /// runs from it — not from whenever this reaches the server.
  Future<void> serve({String? reason}) async {
    final generation = _generation;
    if (state.isSubmitting) return;
    final Consumer? household = state.selected;
    if (household == null || state.isLoading || !state.canServe(household)) {
      return;
    }

    state = state.copyWith(isSubmitting: true);

    final uuid = ref.read(clientUuidFactoryProvider)();
    final result = await ref.read(issueDisconnectionNoticeProvider)(
      consumer: household,
      clientUuid: uuid,
      reason: (reason == null || reason.trim().isEmpty) ? null : reason.trim(),
    );

    if (!ref.mounted || generation != _generation) return;
    switch (result) {
      case Err(:final failure):
        state = state.copyWith(isSubmitting: false, failure: failure);
      case Ok():
        // Draining now is what makes the notice appear in the Notices list
        // and starts its clock server-side.
        await ref.read(syncServiceProvider).syncNow();
        if (!ref.mounted || generation != _generation) return;
        final queue = await ref.read(outboxRepositoryProvider).all();
        if (!ref.mounted || generation != _generation) return;
        final confirmed =
            queue is Ok<List<OutboxEntry>> &&
            queue.value.any(
              (e) =>
                  e.operation.clientUuid == uuid &&
                  e.status == OutboxStatus.synced,
            );
        if (!confirmed) {
          state = state.copyWith(
            isSubmitting: false,
            failure: const NetworkFailure(
              'Notice saved on this phone but not confirmed by the server. Open Profile to sync or review its error.',
            ),
          );
          return;
        }
        state = state.copyWith(
          isSubmitting: false,
          servedTo: household.fullName,
          clearSelected: true,
        );
    }
  }
}

final serveNoticeControllerProvider =
    NotifierProvider<ServeNoticeController, ServeNoticeState>(
      ServeNoticeController.new,
    );
