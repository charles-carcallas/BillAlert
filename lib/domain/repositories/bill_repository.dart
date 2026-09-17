import '../../core/result/result.dart';
import '../entities/bill.dart';
import '../value_objects/cycle_label.dart';
import '../value_objects/ids.dart';
import '../value_objects/kwh.dart';
import '../value_objects/money.dart';
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
  Future<Result<List<Bill>>> historyFor(
    ConsumerId consumerId, {
    int limit = 12,
  });

  /// One bill, for the post-amount screen.
  Future<Result<Bill?>> byId(BillId id);

  /// Bills a cashier can collect against. Excludes unpriced bills: an
  /// unpriced bill is not collectable and must not appear in a payment.
  Future<Result<List<Bill>>> payableFor(ConsumerId consumerId);

  /// Refreshes the cached bills for one consumer and cycle.
  Future<Result<void>> refreshFor(ConsumerId consumerId, CycleLabel cycle);

  /// CSH-02, the Cashier's consumer list: every household in the area with
  /// something outstanding, rolled up. Backed by `v_consumer_outstanding`,
  /// which is a per-consumer aggregate and cannot produce a [Bill] - it is
  /// the answer to "who owes what", not "which bills".
  Future<Result<List<ConsumerOutstanding>>> outstandingInArea(AreaId areaId);

  /// Every bill in the area for [cycle], each carrying the meter reading it
  /// was made from. The Meter Reader's sheet for BOHECO. Backed by
  /// `v_bill_status`; online only.
  Future<Result<List<Bill>>> readingsForCycle(AreaId areaId, CycleLabel cycle);
}

/// What one household owes, across every unpaid month.
///
/// The row behind "₱1,975.35 · 3 bills · oldest June · 2 overdue" on the
/// Cashier's Consumers screen. It is a roll-up, so it carries counts and a
/// total but no bill: choosing which bills to settle is the next screen's
/// job, and it asks [BillRepository.payableFor] for them.
final class ConsumerOutstanding {
  final ConsumerId consumerId;
  final ConsumerNumber consumerNo;
  final String consumerName;
  final String? purok;

  /// Bills that have an amount and are not settled. Only these can be paid.
  final int payableBillCount;

  /// Readings still waiting on the cooperative. Shown so the cashier can say
  /// "that month has no figure yet" instead of "there is nothing there".
  final int unpricedBillCount;

  final int overdueCount;

  /// The sum of the balances. Unpriced bills contribute nothing, because
  /// nothing is owed on a reading nobody has priced.
  final Money totalOutstanding;

  const ConsumerOutstanding({
    required this.consumerId,
    required this.consumerNo,
    required this.consumerName,
    required this.payableBillCount,
    required this.unpricedBillCount,
    required this.overdueCount,
    required this.totalOutstanding,
    this.purok,
  });

  factory ConsumerOutstanding.fromJson(Map<String, dynamic> json) {
    return ConsumerOutstanding(
      consumerId: ConsumerId(json['consumer_id'] as String),
      consumerNo: ConsumerNumber(json['consumer_no'] as String? ?? ''),
      consumerName: json['consumer_name'] as String? ?? '',
      purok: json['purok'] as String?,
      payableBillCount: (json['payable_bill_count'] as num?)?.toInt() ?? 0,
      unpricedBillCount: (json['unpriced_bill_count'] as num?)?.toInt() ?? 0,
      overdueCount: (json['overdue_count'] as num?)?.toInt() ?? 0,
      totalOutstanding: json['total_outstanding'] == null
          ? Money.zero
          : Money.tryParse(json['total_outstanding'].toString()) ?? Money.zero,
    );
  }

  /// True when there is something a cashier can actually collect.
  bool get hasPayableBills => payableBillCount > 0;

  /// Matches a typed search against the number or the name, so the cashier
  /// can use whichever the person at the counter says first.
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return consumerNo.value.toLowerCase().contains(q) ||
        consumerName.toLowerCase().contains(q);
  }
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
          PhDate.tryParse(json['reading_date'].toString()) ??
          const PhDate(1970, 1, 1),
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
