import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_failure.dart';
import '../../core/result/result.dart';
import '../../domain/repositories/payment_repository.dart';
import '../../domain/value_objects/ids.dart';
import '../auth/auth_controller.dart';
import '../providers.dart';

/// CSH-03 — what this area has receipted.
final class ReceiptsState {
  /// Today's takings, straight from `v_cashier_daily_summary`.
  final CollectionSummary today;

  /// Receipts, newest first. One entry per handover, not per bill.
  final List<PaymentSummary> receipts;

  final bool isLoading;
  final AppFailure? failure;

  const ReceiptsState({
    this.today = CollectionSummary.empty,
    this.receipts = const <PaymentSummary>[],
    this.isLoading = false,
    this.failure,
  });
}

class ReceiptsController extends Notifier<ReceiptsState> {
  Future<void>? _inFlight;

  @override
  ReceiptsState build() {
    Future<void>.microtask(load);
    return const ReceiptsState(isLoading: true);
  }

  /// Coalesced, like the other list screens: build() starts one load and
  /// pull-to-refresh starts another, and the slower must not land last.
  Future<void> load() {
    final Future<void>? existing = _inFlight;
    if (existing != null) return existing;

    final Future<void> load = _doLoad().whenComplete(() => _inFlight = null);
    _inFlight = load;
    return load;
  }

  Future<void> _doLoad() async {
    final user = await ref.read(authControllerProvider.future);
    final AreaId? areaId = user?.areaId;

    if (areaId == null) {
      state = const ReceiptsState(
        failure: PermissionFailure(
          'This screen is for a cashier, and no service area is attached to '
          'the account you are signed in with.',
        ),
      );
      return;
    }

    state = ReceiptsState(
      today: state.today,
      receipts: state.receipts,
      isLoading: true,
    );

    final payments = ref.read(paymentRepositoryProvider);

    // Two independent reads, so they go together rather than one after the
    // other - the cashier is looking at a screen, not a progress bar.
    final results = await Future.wait<Object>(<Future<Object>>[
      payments.dailySummary(areaId),
      payments.recentInArea(areaId),
    ]);

    final summaryResult = results[0] as Result<CollectionSummary>;
    final listResult = results[1] as Result<List<PaymentSummary>>;

    // A failed list is worth reporting; a failed total is not worth blocking
    // the list for, so it falls back to an empty day.
    final CollectionSummary today = switch (summaryResult) {
      Ok(:final value) => value,
      Err() => state.today,
    };

    switch (listResult) {
      case Ok(:final value):
        state = ReceiptsState(today: today, receipts: value);
      case Err(:final failure):
        state = ReceiptsState(
          today: today,
          receipts: state.receipts,
          failure: failure,
        );
    }
  }
}

final receiptsControllerProvider =
    NotifierProvider<ReceiptsController, ReceiptsState>(ReceiptsController.new);
