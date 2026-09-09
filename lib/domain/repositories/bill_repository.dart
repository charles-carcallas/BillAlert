import '../../core/result/result.dart';
import '../entities/bill.dart';
import '../value_objects/cycle_label.dart';
import '../value_objects/ids.dart';
import '../value_objects/kwh.dart';
import '../value_objects/ph_date.dart';

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
  Future<Result<List<AwaitingAmountEntry>>> awaitingAmount(AreaId areaId);

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

/// One row of the Admin's "readings awaiting an amount" queue.
///
/// A [Bill] plus the household it belongs to. The extra fields are not
/// decoration: the Admin is transcribing a peso figure from the
/// cooperative's printout, and a transcription typo is the likeliest error
/// in the whole system. They need to see WHOSE bill they are pricing, and
/// they need the consumption next to the amount box so a wildly wrong figure
/// is obvious before it is posted.
///
/// It is a read model, not an entity: nothing is ever saved from this shape.
/// It exists because `v_readings_awaiting_amount` already returns exactly
/// these columns, and splitting them across two round trips to reassemble a
/// Bill would be slower and no clearer.
final class AwaitingAmountEntry {
  final Bill bill;

  /// "Bienvenido Sarigumba", as the view composes it.
  final String consumerName;
  final ConsumerNumber consumerNo;
  final String? purok;

  /// MTR-08. Shown as "04,610 → 04,668" so the reading can be checked
  /// against the printout as well as the amount.
  final Kwh previousReading;
  final Kwh currentReading;

  final PhDate readingDate;

  /// How long this household has been waiting for a figure. The mockup leads
  /// with it, because the queue is worked oldest first.
  final int daysWaiting;

  const AwaitingAmountEntry({
    required this.bill,
    required this.consumerName,
    required this.consumerNo,
    required this.previousReading,
    required this.currentReading,
    required this.readingDate,
    required this.daysWaiting,
    this.purok,
  });

  factory AwaitingAmountEntry.fromJson(Map<String, dynamic> json) {
    return AwaitingAmountEntry(
      bill: Bill.fromJson(json),
      consumerName: json['consumer_name'] as String? ?? '',
      consumerNo: ConsumerNumber(json['consumer_no'] as String? ?? ''),
      purok: json['purok'] as String?,
      previousReading:
          Kwh.tryParse(json['previous_reading'].toString()) ?? Kwh.zero,
      currentReading:
          Kwh.tryParse(json['current_reading'].toString()) ?? Kwh.zero,
      readingDate:
          PhDate.tryParse(json['reading_date'].toString()) ?? const PhDate(1970, 1, 1),
      daysWaiting: (json['days_waiting'] as num?)?.toInt() ?? 0,
    );
  }

  /// "today", "1 day", "6 days" — the wait badge on the mockup.
  String get waitLabel => switch (daysWaiting) {
        <= 0 => 'today',
        1 => '1 day',
        _ => '$daysWaiting days',
      };
}
