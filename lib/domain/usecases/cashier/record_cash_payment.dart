import '../../../core/errors/app_failure.dart';
import '../../../core/result/result.dart';
import '../../entities/bill.dart';
import '../../outbox/outbox_operation.dart';
import '../../repositories/outbox_repository.dart';
import '../../time/ph_clock.dart';
import '../../value_objects/ids.dart';
import '../../value_objects/money.dart';

/// FR-30 — the cashier takes cash across the counter.
///
/// Owned by Obiso. The screen and the PaymentRepository implementation are
/// still to be written; this class fixes the shape of the operation.
///
/// One handover is one transaction and one receipt, however many months it
/// settles. That is why the bills and the amounts travel together as two
/// parallel lists: `fn_record_payment(p_bill_ids[], p_amounts[])` applies
/// them in a single transaction. Do not split this into one call per bill.
/// Three separate updates leave a consumer half-paid and holding a receipt
/// for money the system lost, the first time the network drops mid-loop.
final class RecordCashPayment {
  final OutboxRepository outbox;
  final PhClock clock;
  final ClientUuidFactory newClientUuid;

  const RecordCashPayment({
    required this.outbox,
    required this.clock,
    required this.newClientUuid,
  });

  Future<Result<void>> call({
    required String consumerLabel,
    required List<Bill> bills,
    required List<Money> amounts,
    Money? cashTendered,
  }) async {
    if (bills.isEmpty) {
      return const Err(ValidationFailure(
        'Choose at least one bill before recording a payment.',
      ));
    }
    if (bills.length != amounts.length) {
      return const Err(ValidationFailure(
        'Every bill needs an amount. Please check the payment list.',
      ));
    }

    // FR-30: an unpriced bill is not collectable. There is no figure to pay.
    for (final Bill bill in bills) {
      if (bill.isUnpriced) {
        return Err(ValidationFailure(
          'Bill ${bill.billNo} is still waiting for its amount from the '
          'cooperative, so it cannot be paid yet.',
        ));
      }
    }

    for (var i = 0; i < bills.length; i++) {
      if (amounts[i] <= Money.zero) {
        return Err(ValidationFailure(
          'The amount for bill ${bills[i].billNo} must be more than zero.',
        ));
      }
      if (amounts[i] > bills[i].balance) {
        return Err(ValidationFailure(
          '${amounts[i].format()} is more than the '
          '${bills[i].balance.format()} still owed on bill ${bills[i].billNo}.',
        ));
      }
    }

    // Adding up amounts a person already decided. Not deriving a bill.
    final total =
        amounts.fold(Money.zero, (Money running, Money each) => running + each);

    if (cashTendered != null && cashTendered < total) {
      return Err(ValidationFailure(
        'Cash received (${cashTendered.format()}) is less than the '
        '${total.format()} being paid.',
      ));
    }

    final operation = RecordPaymentOperation(
      clientUuid: newClientUuid(),
      capturedAt: clock.nowUtc(),
      billIds: bills.map((Bill b) => b.id).toList(),
      amounts: amounts,
      cashTendered: cashTendered,
      consumerLabel: consumerLabel,
    );

    return switch (await outbox.enqueue(operation)) {
      Err(:final failure) => Err<void>(failure),
      Ok() => const Ok<void>(null),
    };
  }
}
