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
import '../../domain/value_objects/ids.dart';
import '../auth/auth_controller.dart';
import '../providers.dart';

// coach:anchor(state-class)
class CurrentBillState {
  final Bill? currentBill;
  final List<Bill> history;
  final bool isLoading;
  final AppFailure? failure;

  const CurrentBillState({
    this.currentBill,
    this.history = const [],
    this.isLoading = false,
    this.failure,
  });

  CurrentBillState copyWith({
    Bill? currentBill,
    List<Bill>? history,
    bool? isLoading,
    AppFailure? failure,
  }) {
    return CurrentBillState(
      currentBill: currentBill ?? this.currentBill,
      history: history ?? this.history,
      isLoading: isLoading ?? this.isLoading,
      failure: failure,
    );
  }
}

// coach:anchor(controller-class)
class CurrentBillController extends Notifier<CurrentBillState> {
  @override
  CurrentBillState build() {
    Future.microtask(_load);
    return const CurrentBillState();
  }

  Future<void> _load() async {
    state = state.copyWith(isLoading: true, failure: null);

    // Which household is this? A consumer signs in with a `profiles` row, but
    // bills hang off a `consumers` row and the two have different ids. This
    // used to pass the profile id straight in, which matched nothing once the
    // repository started filtering on consumer_id - the screen went silently
    // empty for a consumer who did have a bill.
    final consumerResult = await ref
        .read(consumerRepositoryProvider)
        .signedInConsumer();

    final ConsumerId? consumerId;
    switch (consumerResult) {
      case Ok(:final value):
        consumerId = value?.id;
      case Err(:final failure):
        state = state.copyWith(isLoading: false, failure: failure);
        return;
    }

    if (consumerId == null) {
      state = state.copyWith(
        isLoading: false,
        failure: const PermissionFailure(
          'This screen shows a household its own bill, and the account you '
          'are signed in with is not attached to one.',
        ),
      );
      return;
    }

    final billRepo = ref.read(billRepositoryProvider);

    final billResult = await billRepo.currentBillFor(consumerId);
    Bill? currentBill;
    switch (billResult) {
      case Ok(:final value):
        currentBill = value;
      case Err(:final failure):
        state = state.copyWith(isLoading: false, failure: failure);
        return;
    }

    final historyResult = await billRepo.historyFor(consumerId);
    List<Bill> history = [];
    switch (historyResult) {
      case Ok(:final value):
        history = value;
      case Err(:final failure):
        state = state.copyWith(isLoading: false, failure: failure);
        return;
    }

    state = CurrentBillState(
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
