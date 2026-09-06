import '../../core/result/result.dart';
import '../value_objects/ids.dart';

/// Cash payments and the receipts they produce.
///
/// Not implemented yet - the Cashier screens belong to another member of the
/// team. Recording a payment goes through the outbox and then through
/// `fn_record_payment`, which settles every bill in one handover atomically.
/// Do not replace that with a loop of updates in Dart: three separate updates
/// leave a consumer half-paid the first time the network drops mid-loop.
abstract class PaymentRepository {
  /// One handover, one receipt, covering however many bills it settled.
  /// Backed by `v_payment_history`.
  Future<Result<List<PaymentSummary>>> historyFor(ConsumerId consumerId);

  /// The takings for the day. Backed by `v_cashier_daily_summary`.
  Future<Result<CollectionSummary>> dailySummary(AreaId areaId);
}

/// A receipt line, as `v_payment_history` returns it.
final class PaymentSummary {
  final TransactionId transactionId;
  final String receiptNo;
  final DateTime paidAt;

  const PaymentSummary({
    required this.transactionId,
    required this.receiptNo,
    required this.paidAt,
  });
}

/// A cashier totals for one day.
final class CollectionSummary {
  final int transactionCount;
  final int billsSettled;

  const CollectionSummary({
    required this.transactionCount,
    required this.billsSettled,
  });
}
