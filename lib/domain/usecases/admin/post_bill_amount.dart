import '../../../core/errors/app_failure.dart';
import '../../../core/result/result.dart';
import '../../entities/bill.dart';
import '../../outbox/outbox_operation.dart';
import '../../repositories/outbox_repository.dart';
import '../../time/ph_clock.dart';
import '../../value_objects/ids.dart';
import '../../value_objects/money.dart';
import '../../value_objects/ph_date.dart';

/// FR-21b — the Area President posts the amount the cooperative returned.
///
/// Owned by Charles. The screen and the BillRepository implementation behind
/// it are still to be written; this class fixes the shape of the operation so
/// the rest of the scaffold can be built against it.
///
/// Read what this does and, more importantly, what it does not. The amount
/// arrives as a [Money] the Admin typed from the cooperative's printout.
/// BillAlert has no tariff and never derives it from consumption; its only
/// adjustment is the required whole-peso ceiling. Posting the rounded amount
/// is the moment the bill becomes payable and the moment the consumer is
/// told, and `fn_post_bill_amount` does both in one transaction — including
/// queueing the notification. Do not send that notification from Dart.
final class PostBillAmount {
  final OutboxRepository outbox;
  final PhClock clock;
  final ClientUuidFactory newClientUuid;

  const PostBillAmount({
    required this.outbox,
    required this.clock,
    required this.newClientUuid,
  });

  Future<Result<void>> call({
    required Bill bill,
    required Money amount,
    required PhDate dueDate,
  }) async {
    // A bill is priced once. Posting a second amount is a mistake, not an
    // edit, and the database says the same with bills_pricing_consistent.
    if (bill.isPayable) {
      return Err(
        ConflictFailure(
          'Bill ${bill.billNo} already has an amount of '
          '${bill.totalAmount!.format()}.',
        ),
      );
    }
    // `fn_post_bill_amount` refuses anything at or below zero, and refuses a
    // due date already in the past. Both are checked here too - not to
    // replace the server, which stays the authority, but because the Admin
    // may be offline: without these, a nonsense amount would sit in the
    // outbox looking accepted and fail hours later at sync, with nobody
    // watching.
    if (amount <= Money.zero) {
      return const Err(
        ValidationFailure(
          'The amount due must be more than zero. Please check the figure on '
          'the cooperative printout.',
        ),
      );
    }

    final PhDate today = PhDate.at(clock.nowUtc());
    if (dueDate.isBefore(today)) {
      return Err(
        ValidationFailure(
          'The due date ${dueDate.toIso()} has already passed. Please use the '
          'date printed on the cooperative statement.',
        ),
      );
    }

    final operation = PostAmountOperation(
      clientUuid: newClientUuid(),
      capturedAt: clock.nowUtc(),
      billId: bill.id,
      amount: amount.roundUpToWholePeso(),
      dueDate: dueDate,
      billLabel: bill.billNo.value,
    );

    return switch (await outbox.enqueue(operation)) {
      Err(:final failure) => Err<void>(failure),
      Ok() => const Ok<void>(null),
    };
  }
}
