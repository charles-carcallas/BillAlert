// ============================================================
// WEEK 11 — START HERE   ·   Consumer · Current Bill (controller)
// Owner: Basio
// Worksheet: docs/week11/worksheets/02_consumer_current_bill.md
//
// PURPOSE
//   Show the consumer their current bill — whether unpriced (awaiting
//   the cooperative's figure) or priced (with balance and due date).
//
// WHERE YOU ARE IN THE CHAIN
//   reader → outbox → sync → unpriced bill → admin posts amount
//         → [ THIS FILE ] → consumer sees their bill
//
// CALLS
//   BillRepository.currentBillFor / historyFor
//   You never call Supabase from a controller.
//
// BEFORE CODING
//   - See reference implementation: reading_entry_controller.dart
//
// DO NOT CHANGE
//   The file name or location.
//
// DONE WHEN
//   The screen shows the current bill from real data — unpriced first,
//   then priced once the Admin posts, with no hard-coded amount anywhere.
// ============================================================
// ignore_for_file: unused_import
import 'package:flutter_riverpod/flutter_riverpod.dart';

// coach:anchor(imports)
import '../../core/errors/app_failure.dart';
import '../../core/result/result.dart';
import '../../domain/entities/bill.dart';
import '../../domain/entities/consumer.dart' as domain;
import '../../domain/value_objects/ids.dart';
import '../auth/auth_controller.dart';
import '../providers.dart';

// coach:anchor(state-class)
class CurrentBillState {
  final domain.Consumer? household;
  final Bill? currentBill;
  final List<Bill> history;
  final bool isLoading;
  final AppFailure? failure;
  final bool needsHousehold;

  const CurrentBillState({
    this.household,
    this.currentBill,
    this.history = const [],
    this.isLoading = false,
    this.failure,
    this.needsHousehold = false,
  });

  CurrentBillState copyWith({
    domain.Consumer? household,
    Bill? currentBill,
    List<Bill>? history,
    bool? isLoading,
    AppFailure? failure,
  }) {
    return CurrentBillState(
      household: household ?? this.household,
      currentBill: currentBill ?? this.currentBill,
      history: history ?? this.history,
      isLoading: isLoading ?? this.isLoading,
      failure: failure,
      needsHousehold: false,
    );
  }
}

// coach:anchor(controller-class)
class CurrentBillController extends Notifier<CurrentBillState> {
  int _generation = 0;
  @override
  CurrentBillState build() {
    ref.watch(authControllerProvider.select((s) => s.value?.accessScope));
    _generation++;
    Future.microtask(_load);
    return const CurrentBillState();
  }

  Future<void> _load() async {
    if (!ref.mounted || ref.read(authControllerProvider).value == null) return;
    final generation = _generation;
    state = state.copyWith(isLoading: true, failure: null);

    // Which household is this? A consumer signs in with a `profiles` row, but
    // bills hang off a `consumers` row and the two have different ids. This
    // used to pass the profile id straight in, which matched nothing once the
    // repository started filtering on consumer_id - the screen went silently
    // empty for a consumer who did have a bill.
    final consumerResult = await ref
        .read(consumerRepositoryProvider)
        .signedInConsumer();
    if (!ref.mounted || generation != _generation) return;

    final domain.Consumer? household;
    switch (consumerResult) {
      case Ok(:final value):
        household = value;
      case Err(:final failure):
        state = state.copyWith(isLoading: false, failure: failure);
        return;
    }

    if (household == null) {
      state = const CurrentBillState(isLoading: false, needsHousehold: true);
      return;
    }

    state = state.copyWith(household: household);
    final consumerId = household.id;
    final billRepo = ref.read(billRepositoryProvider);

    final billResult = await billRepo.currentBillFor(consumerId);
    if (!ref.mounted || generation != _generation) return;
    Bill? currentBill;
    switch (billResult) {
      case Ok(:final value):
        currentBill = value;
      case Err(:final failure):
        state = state.copyWith(isLoading: false, failure: failure);
        return;
    }

    final historyResult = await billRepo.historyFor(consumerId);
    if (!ref.mounted || generation != _generation) return;
    List<Bill> history = [];
    switch (historyResult) {
      case Ok(:final value):
        history = value;
      case Err(:final failure):
        state = state.copyWith(isLoading: false, failure: failure);
        return;
    }

    state = CurrentBillState(
      household: household,
      isLoading: false,
      currentBill: currentBill,
      history: history,
    );
  }

  Future<void> refresh() => _load();
}

// coach:anchor(providers)
final currentBillControllerProvider =
    NotifierProvider<CurrentBillController, CurrentBillState>(
      CurrentBillController.new,
    );
