import 'package:flutter_riverpod/flutter_riverpod.dart' hide Consumer;

import '../../core/errors/app_failure.dart';
import '../../core/result/result.dart';
import '../../domain/entities/bill.dart';
import '../../domain/entities/consumer.dart';
import '../../domain/repositories/payment_repository.dart';
import '../auth/auth_controller.dart';
import '../providers.dart';

/// CON-07 — the household's past months, and the receipts that settled them.
final class HistoryState {
  final List<Bill> bills;
  final List<PaymentSummary> receipts;

  final bool isLoading;
  final AppFailure? failure;

  const HistoryState({
    this.bills = const <Bill>[],
    this.receipts = const <PaymentSummary>[],
    this.isLoading = false,
    this.failure,
  });
}

class HistoryController extends Notifier<HistoryState> {
  int _generation = 0;
  Future<void>? _inFlight;

  @override
  HistoryState build() {
    ref.watch(authControllerProvider.select((s) => s.value?.accessScope));
    _generation++;
    _inFlight = null;
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
    if (!ref.mounted || ref.read(authControllerProvider).value == null) return;
    final generation = _generation;
    // Which household? The signed-in user has a profile id; bills hang off a
    // consumer id, and they are not the same value.
    final consumerResult = await ref
        .read(consumerRepositoryProvider)
        .signedInConsumer();
    if (!ref.mounted || generation != _generation) return;

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
          receipts: state.receipts,
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
      receipts: state.receipts,
      isLoading: true,
    );

    final results = await Future.wait<Object>(<Future<Object>>[
      ref.read(billRepositoryProvider).historyFor(me.id),
      ref.read(paymentRepositoryProvider).historyFor(me.id),
    ]);
    if (!ref.mounted || generation != _generation) return;

    final billsResult = results[0] as Result<List<Bill>>;
    final receiptsResult = results[1] as Result<List<PaymentSummary>>;

    // Preserve the last loaded receipts on a refresh failure, but report it
    // rather than presenting unavailable payment history as an empty result.
    final List<PaymentSummary> receipts = switch (receiptsResult) {
      Ok(:final value) => value,
      Err() => state.receipts,
    };
    final AppFailure? receiptFailure = switch (receiptsResult) {
      Err(:final failure) => failure,
      Ok() => null,
    };
    switch (billsResult) {
      case Ok(:final value):
        state = HistoryState(
          bills: value,
          receipts: receipts,
          failure: receiptFailure,
        );
      case Err(:final failure):
        state = HistoryState(
          bills: state.bills,
          receipts: receipts,
          failure: failure,
        );
    }
  }
}

final historyControllerProvider =
    NotifierProvider<HistoryController, HistoryState>(HistoryController.new);
