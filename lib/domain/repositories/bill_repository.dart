import '../../core/result/result.dart';
import '../entities/bill.dart';
import '../value_objects/cycle_label.dart';
import '../value_objects/ids.dart';

/// Bills, priced and unpriced.
///
/// Not implemented yet. The Admin and Consumer screens are owned by other
/// members of the team; this is the seam they write against, so the shape of
/// the data is agreed before four people start guessing.
///
/// Reads come from the views, never from raw joins in Dart:
/// `v_readings_awaiting_amount` is the Admin queue and
/// `v_consumer_current_bill` is the consumer current bill, unpriced included.
abstract class BillRepository {
  /// FR-21b, Admin queue: readings the cooperative has not priced yet,
  /// oldest first. Backed by `v_readings_awaiting_amount`.
  Future<Result<List<Bill>>> awaitingAmount(AreaId areaId);

  /// CON-01: the consumer current bill, which may still be unpriced.
  Future<Result<Bill?>> currentBillFor(ConsumerId consumerId);

  /// CON-07: recent cycles for the history screen.
  Future<Result<List<Bill>>> historyFor(ConsumerId consumerId, {int limit = 12});

  /// One bill, for the post-amount screen.
  Future<Result<Bill?>> byId(BillId id);

  /// Bills a cashier can collect against. Excludes unpriced bills: an
  /// unpriced bill is not collectable and must not appear in a payment.
  Future<Result<List<Bill>>> payableFor(ConsumerId consumerId);

  /// Refreshes the cached bills for one consumer and cycle.
  Future<Result<void>> refreshFor(ConsumerId consumerId, CycleLabel cycle);
}
