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
/// arrives as a [Money] the Admin typed from the cooperative's printout. It
/// is not calculated, not adjusted, and not checked against the consumption.
/// BillAlert has no tariff and no rate table. Posting the amount is the
/// moment the bill becomes payable and the moment the consumer is told, and
/// `fn_post_bill_amount` does both in one transaction — including queueing
/// the notification. Do not send that notification from Dart.
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
      return Err(ConflictFailure(
        'Bill ${bill.billNo} already has an amount of '
        '${bill.totalAmount!.format()}.',
      ));
    }
    if (amount.isNegative) {
      return const Err(ValidationFailure(
        'The amount cannot be negative. Please check the figure on the '
        'cooperative printout.',
      ));
    }

    final operation = PostAmountOperation(
      clientUuid: newClientUuid(),
      capturedAt: clock.nowUtc(),
      billId: bill.id,
      amount: amount,
      dueDate: dueDate,
      billLabel: bill.billNo.value,
    );

    return switch (await outbox.enqueue(operation)) {
      Err(:final failure) => Err<void>(failure),
      Ok() => const Ok<void>(null),
    };
  }
}
