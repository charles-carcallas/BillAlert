import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_failure.dart';
import '../../core/result/result.dart';
import '../../domain/repositories/bill_repository.dart';
import '../../domain/repositories/payment_repository.dart';
import '../../domain/value_objects/ids.dart';
import '../../domain/value_objects/money.dart';
import '../auth/auth_controller.dart';
import '../providers.dart';

/// What this area still owes, rolled up from the per-household view.
///
/// The counterpart to the day's takings: a cashier closing up wants both
/// halves of the picture — what came in, and what is still out there. The
/// per-household figures are the Cashier's own list screen; this is only
/// their sum, so the two can never disagree.
///
/// Unpriced bills contribute nothing. `ConsumerOutstanding.totalOutstanding`
/// already excludes them, because nothing is owed on a reading the
/// cooperative has not priced.
final class AreaOutstanding {
  final Money total;

  /// Households with something still to pay.
  final int households;

  /// How many of those are past a due date.
  final int overdueHouseholds;

  const AreaOutstanding({
    required this.total,
    required this.households,
    required this.overdueHouseholds,
  });

  /// Nothing owed, or nothing known yet. The screen shows it as a real zero
  /// only once a read has succeeded; until then it is simply not drawn.
  static const AreaOutstanding none = AreaOutstanding(
    total: Money.zero,
    households: 0,
    overdueHouseholds: 0,
  );

  factory AreaOutstanding.from(List<ConsumerOutstanding> households) {
    final List<ConsumerOutstanding> owing = households
        .where((ConsumerOutstanding h) => !h.totalOutstanding.isZero)
        .toList();

    return AreaOutstanding(
      total: owing.fold<Money>(
        Money.zero,
        (Money running, ConsumerOutstanding h) => running + h.totalOutstanding,
      ),
      households: owing.length,
      overdueHouseholds: owing
          .where((ConsumerOutstanding h) => h.overdueCount > 0)
          .length,
    );
  }
}

/// CSH-03 — what this area has receipted.
final class ReceiptsState {
  /// Today's takings, straight from `v_cashier_daily_summary`.
  final CollectionSummary today;

  /// Receipts, newest first. One entry per handover, not per bill.
  final List<PaymentSummary> receipts;

  /// What the area still owes. Null until a read has succeeded, so the card
  /// can stay silent rather than claim a confident ₱0.00 it has not earned.
  final AreaOutstanding? outstanding;

  final bool isLoading;
  final AppFailure? failure;

  const ReceiptsState({
    this.today = CollectionSummary.empty,
    this.receipts = const <PaymentSummary>[],
    this.outstanding,
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
      outstanding: state.outstanding,
      isLoading: true,
    );

    final payments = ref.read(paymentRepositoryProvider);
    final bills = ref.read(billRepositoryProvider);

    // Three independent reads, so they go together rather than one after the
    // other - the cashier is looking at a screen, not a progress bar.
    final results = await Future.wait<Object>(<Future<Object>>[
      payments.dailySummary(areaId),
      payments.recentInArea(areaId),
      bills.outstandingInArea(areaId),
    ]);

    final summaryResult = results[0] as Result<CollectionSummary>;
    final listResult = results[1] as Result<List<PaymentSummary>>;
    final outstandingResult = results[2] as Result<List<ConsumerOutstanding>>;

    // A failed list is worth reporting; a failed total is not worth blocking
    // the list for, so it falls back to an empty day.
    final CollectionSummary today = switch (summaryResult) {
      Ok(:final value) => value,
      Err() => state.today,
    };

    // Same treatment as the day's total: a figure that would not load is
    // not worth withholding the receipts for. The last good one is kept,
    // and the card simply does not draw a total it never had.
    final AreaOutstanding? outstanding = switch (outstandingResult) {
      Ok(:final value) => AreaOutstanding.from(value),
      Err() => state.outstanding,
    };

    switch (listResult) {
      case Ok(:final value):
        state = ReceiptsState(
          today: today,
          receipts: value,
          outstanding: outstanding,
        );
      case Err(:final failure):
        state = ReceiptsState(
          today: today,
          receipts: state.receipts,
          outstanding: outstanding,
          failure: failure,
        );
    }
  }
}

final receiptsControllerProvider =
    NotifierProvider<ReceiptsController, ReceiptsState>(ReceiptsController.new);
