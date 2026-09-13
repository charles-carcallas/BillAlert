import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_failure.dart';
import '../../core/result/result.dart';
import '../../domain/repositories/bill_repository.dart';
import '../../domain/value_objects/ids.dart';
import '../../domain/value_objects/money.dart';
import '../../domain/value_objects/ph_date.dart';
import '../auth/auth_controller.dart';
import '../providers.dart';

/// What the Post Bill Amount screen is showing right now.
final class PostBillAmountState {
  /// FR-21b: the readings the cooperative has not priced yet, oldest first.
  final List<AwaitingAmountEntry> queue;

  final bool isLoading;

  /// Which bill is mid-post, so one card shows a spinner and the rest stay
  /// usable. A single `isSubmitting` flag would freeze the whole queue.
  final BillId? posting;

  final AppFailure? failure;

  /// Set for one rebuild after a successful post, so the screen can say what
  /// happened before the row disappears from the queue.
  final String? postedMessage;

  const PostBillAmountState({
    this.queue = const <AwaitingAmountEntry>[],
    this.isLoading = false,
    this.posting,
    this.failure,
    this.postedMessage,
  });

  PostBillAmountState copyWith({
    List<AwaitingAmountEntry>? queue,
    bool? isLoading,
    BillId? posting,
    AppFailure? failure,
    String? postedMessage,
  }) {
    return PostBillAmountState(
      queue: queue ?? this.queue,
      isLoading: isLoading ?? this.isLoading,
      // Both of these are cleared by being left out, not carried forward: a
      // stale failure or a stale confirmation on the next action would be
      // worse than none.
      posting: posting,
      failure: failure,
      postedMessage: postedMessage,
    );
  }
}

/// FR-21b — the Area President posts the amount the cooperative returned.
///
/// The screen hands over the text that was typed. Everything after that is
/// this class calling one use case, which writes to the outbox. There is no
/// Supabase call in here and no tariff arithmetic: BillAlert transcribes the
/// cooperative amount and applies only the required whole-peso ceiling.
class PostBillAmountController extends Notifier<PostBillAmountState> {
  /// The load currently in flight, if any.
  ///
  /// build() starts one and the screen can start another by pulling to
  /// refresh, so two can easily overlap. Rather than let both run and have
  /// the slower one land last with a stale answer, a second caller is handed
  /// the first one's future and waits for the same result. One load at a
  /// time, and `refresh()` genuinely completes when the data has arrived.
  Future<void>? _inFlight;

  @override
  PostBillAmountState build() {
    Future<void>.microtask(_load);
    return const PostBillAmountState(isLoading: true);
  }

  Future<void> _load() {
    final Future<void>? existing = _inFlight;
    if (existing != null) return existing;

    final Future<void> load = _doLoad().whenComplete(() => _inFlight = null);
    _inFlight = load;
    return load;
  }

  Future<void> _doLoad() async {
    // Awaited, not read synchronously. `authControllerProvider` restores the
    // session asynchronously, so reading `.value` here can land before it has
    // resolved and see null - which this method would then report as "you
    // have no service area", which is not what happened at all.
    final user = await ref.read(authControllerProvider.future);

    // An Admin is an Area President: the queue is their area's, and RLS
    // enforces the same thing server-side.
    final AreaId? areaId = user?.areaId;
    if (areaId == null) {
      state = const PostBillAmountState(
        failure: PermissionFailure(
          'This screen is for an Area President, and no service area is '
          'attached to the account you are signed in with.',
        ),
      );
      return;
    }

    state = state.copyWith(isLoading: true);

    switch (await ref.read(billRepositoryProvider).awaitingAmount(areaId)) {
      case Ok(:final value):
        state = PostBillAmountState(queue: value);
      case Err(:final failure):
        state = PostBillAmountState(failure: failure);
    }
  }

  Future<void> refresh() => _load();

  /// Posts one amount.
  ///
  /// Takes the raw text and turns it into [Money] here, so the widget holds
  /// no parsing rules and the person gets a message written for them. Money
  /// is centavos all the way down; the text never becomes a double.
  Future<void> post({
    required AwaitingAmountEntry entry,
    required String amountText,
    required PhDate? dueDate,
  }) async {
    final Money? amount = Money.tryParse(amountText);
    if (amount == null) {
      state = state.copyWith(
        queue: state.queue,
        failure: const ValidationFailure(
          'Enter the amount as it appears on the cooperative statement, for '
          'example 658.30.',
        ),
      );
      return;
    }
    final Money roundedAmount = amount.roundUpToWholePeso();
    if (dueDate == null) {
      state = state.copyWith(
        queue: state.queue,
        failure: const ValidationFailure(
          'Choose the due date printed on the cooperative statement.',
        ),
      );
      return;
    }

    state = state.copyWith(queue: state.queue, posting: entry.bill.id);

    final result = await ref.read(postBillAmountProvider)(
      bill: entry.bill,
      amount: amount,
      dueDate: dueDate,
    );

    switch (result) {
      case Err(:final failure):
        state = state.copyWith(queue: state.queue, failure: failure);

      case Ok():
        // The amount is safe in the outbox now. Draining it is what makes the
        // bill leave the queue and the consumer's alert go out, so unlike the
        // meter reader - who is out of signal by design - this one is awaited:
        // the Admin is at a desk and is watching the list to see it go.
        await ref.read(syncServiceProvider).syncNow();
        await _load();
        state = state.copyWith(
          queue: state.queue,
          postedMessage:
              '${roundedAmount.format()} posted for ${entry.consumerName}.',
        );
    }
  }

  /// Clears a banner the person has read.
  void dismissMessages() {
    state = state.copyWith(queue: state.queue);
  }
}

final postBillAmountControllerProvider =
    NotifierProvider<PostBillAmountController, PostBillAmountState>(
      PostBillAmountController.new,
    );
