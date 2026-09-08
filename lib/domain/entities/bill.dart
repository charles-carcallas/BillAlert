import '../value_objects/cycle_label.dart';
import '../value_objects/ids.dart';
import '../value_objects/kwh.dart';
import '../value_objects/money.dart';
import '../value_objects/ph_date.dart';

/// One consumer's bill for one billing cycle.
///
/// A bill is born **unpriced**: the meter reader captures a reading, which
/// creates the bill with a consumption but with no amount and no due date.
/// About seven days later the cooperative returns a peso figure, the Admin
/// posts it, and the bill becomes payable. That seven-day window is the whole
/// reason this application exists.
///
/// The class owns the questions people ask of a bill. No screen should read
/// `bill.totalAmount == null` — it asks [isUnpriced], which says what the
/// null *means*. The database enforces the same thing: the
/// `bills_pricing_consistent` constraint requires total_amount, due_date and
/// priced_at to be all null or all set, so there is no half-priced state to
/// represent.
final class Bill {
  final BillId id;
  final BillNumber billNo;
  final ConsumerId consumerId;
  final CycleLabel cycle;
  final Kwh consumption;

  /// Null until the Admin posts the cooperative's figure.
  final Money? totalAmount;

  /// Null until the Admin posts the cooperative's figure.
  final PhDate? dueDate;

  final Money amountPaid;

  const Bill({
    required this.id,
    required this.billNo,
    required this.consumerId,
    required this.cycle,
    required this.consumption,
    required this.totalAmount,
    required this.dueDate,
    this.amountPaid = Money.zero,
  });

  factory Bill.fromJson(Map<String, dynamic> json) {
    return Bill(
      id: BillId(json['bill_id'] as String),
      billNo: BillNumber(json['bill_no'] as String),
      consumerId: ConsumerId(json['consumer_id'] as String),
      cycle: CycleLabel.tryParse(json['cycle_label'] as String) ?? const CycleLabel(1970, 1),
      consumption: Kwh.tryParse(json['consumption'].toString()) ?? Kwh.zero,
      totalAmount: json['total_amount'] != null
          ? Money.tryParse(json['total_amount'].toString())
          : null,
      dueDate: json['due_date'] != null
          ? PhDate.tryParse(json['due_date'].toString())
          : null,
      amountPaid: json['amount_paid'] != null
          ? Money.tryParse(json['amount_paid'].toString()) ?? Money.zero
          : Money.zero,
    );
  }

  /// The reading is in, the amount is not. The consumer can see their
  /// consumption but there is nothing to pay yet.
  bool get isUnpriced => totalAmount == null;

  /// The Admin has posted an amount, so this bill can be collected against.
  bool get isPayable => totalAmount != null;

  /// What is still owed. Zero for an unpriced bill: nothing is owed on a
  /// reading the cooperative has not priced.
  Money get balance => (totalAmount ?? Money.zero) - amountPaid;

  /// Paid in full.
  bool get isSettled => isPayable && amountPaid >= totalAmount!;

  /// Something has been paid, but not all of it.
  bool get isPartiallyPaid =>
      isPayable && !amountPaid.isZero && amountPaid < totalAmount!;

  /// Past its due date and not yet settled. Takes today as an argument
  /// rather than reading a clock, so the caller decides which day it is and
  /// the method stays testable.
  bool isOverdueOn(PhDate today) =>
      isPayable && !isSettled && today.isAfter(dueDate!);

  /// How many days past due, or 0 when not overdue. Mirrors the
  /// `days_overdue` column of `v_bill_status`.
  int daysOverdueOn(PhDate today) =>
      isOverdueOn(today) ? today.daysSince(dueDate!) : 0;

  /// What the status chip says. Matches the `bill_status` enum server-side,
  /// which a trigger keeps in step with these same fields.
  String statusLabelOn(PhDate today) {
    if (isUnpriced) return 'Awaiting amount';
    if (isSettled) return 'Paid';
    if (isOverdueOn(today)) return 'Overdue';
    if (isPartiallyPaid) return 'Partially paid';
    return 'Unpaid';
  }
}
