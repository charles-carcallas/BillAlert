import 'package:flutter_riverpod/flutter_riverpod.dart' hide Consumer;

import '../../core/errors/app_failure.dart';
import '../../core/result/result.dart';
import '../../domain/entities/bill.dart';
import '../../domain/entities/consumer.dart';
import '../../domain/repositories/payment_repository.dart';
import '../providers.dart';

/// CON-07 — the household's past months, and the receipts that settled them.
final class HistoryState {
  final List<Bill> bills;

  /// Receipt number by bill id.
  ///
  /// Built from the receipts rather than stored on the bill, because one
  /// receipt can settle several months — the same OR number appears against
  /// each of them, which is exactly what the mockup shows.
  final Map<String, String> receiptByBillId;

  final bool isLoading;
  final AppFailure? failure;

  const HistoryState({
    this.bills = const <Bill>[],
    this.receiptByBillId = const <String, String>{},
    this.isLoading = false,
    this.failure,
  });
}

class HistoryController extends Notifier<HistoryState> {
  Future<void>? _inFlight;

  @override
  HistoryState build() {
    Future<void>.microtask(load);
    return const HistoryState(isLoading: true);
  }

  Future<void> load() {
    final Future<void>? existing = _inFlight;
    if (existing != null) return existing;

    final Future<void> load = _doLoad().whenComplete(() => _inFlight = null);
    _inFlight = load;
    return load;
  }

  Future<void> _doLoad() async {
    // Which household? The signed-in user has a profile id; bills hang off a
    // consumer id, and they are not the same value.
    final consumerResult = await ref
        .read(consumerRepositoryProvider)
        .signedInConsumer();

    final Consumer? me;
    switch (consumerResult) {
      case Ok(:final value):
        me = value;
      case Err(:final failure):
        // Losing signal while refreshing is not evidence that this account
        // stopped belonging to its household. Keep the statement already on
        // screen and report that it could not be refreshed.
        state = HistoryState(
          bills: state.bills,
          receiptByBillId: state.receiptByBillId,
          failure: failure,
        );
        return;
    }

    if (me == null) {
      state = const HistoryState(
        failure: PermissionFailure(
          'This screen shows a household its own history, and the account '
          'you are signed in with is not attached to one.',
        ),
      );
      return;
    }

    state = HistoryState(
      bills: state.bills,
      receiptByBillId: state.receiptByBillId,
      isLoading: true,
    );

    final results = await Future.wait<Object>(<Future<Object>>[
      ref.read(billRepositoryProvider).historyFor(me.id),
      ref.read(paymentRepositoryProvider).historyFor(me.id),
    ]);

    final billsResult = results[0] as Result<List<Bill>>;
    final receiptsResult = results[1] as Result<List<PaymentSummary>>;

    // A missing receipt number is a blank on one row. A missing bill list is
    // an empty screen, so only that one is reported as a failure.
    final receiptByBillId = <String, String>{...state.receiptByBillId};
    if (receiptsResult case Ok(:final value)) {
      receiptByBillId.clear();
      for (final PaymentSummary receipt in value) {
        for (final SettledBill settled in receipt.bills) {
          receiptByBillId[settled.billId.value] = receipt.receiptNo;
        }
      }
    }

    switch (billsResult) {
      case Ok(:final value):
        state = HistoryState(bills: value, receiptByBillId: receiptByBillId);
      case Err(:final failure):
        state = HistoryState(
          bills: state.bills,
          receiptByBillId: state.receiptByBillId,
          failure: failure,
        );
    }
  }
}

final historyControllerProvider =
    NotifierProvider<HistoryController, HistoryState>(HistoryController.new);
