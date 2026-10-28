import '../../core/result/result.dart';
import '../value_objects/ids.dart';
import '../value_objects/money.dart';

/// Cash payments and the receipts they produce.
///
/// Recording a payment goes through the outbox and then through
/// `fn_record_payment`, which settles every bill in one handover atomically.
/// Do not replace that with a loop of updates in Dart: three separate updates
/// leave a consumer half-paid the first time the network drops mid-loop.
abstract class PaymentRepository {
  Future<Result<void>> checkCollection(List<BillId> bills, List<Money> amounts);

  /// Exact server-confirmed handover; never falls back to an older cached receipt.
  Future<Result<PaymentSummary?>> byTransaction(String transactionId);

  /// One handover, one receipt, covering however many bills it settled.
  /// Backed by `v_payment_history`.
  Future<Result<List<PaymentSummary>>> historyFor(ConsumerId consumerId);

  /// The takings for the day. Backed by `v_cashier_daily_summary`.
  Future<Result<CollectionSummary>> dailySummary(AreaId areaId);

  /// CSH-03, the Cashier's receipt list: every receipt issued in this area,
  /// newest first. Backed by `v_payment_history`.
  Future<Result<List<PaymentSummary>>> recentInArea(
    AreaId areaId, {
    int limit = 50,
  });

  /// Every receipt issued in this area with [from] <= paid_at < [until],
  /// newest first. The Meter Reader's remittance: the cash they carry to the
  /// BOHECO office. Backed by `v_payment_history`, so row-level security
  /// keeps it to the caller's own area.
  Future<Result<List<PaymentSummary>>> collectedInArea(
    AreaId areaId, {
    required DateTime from,
    required DateTime until,
  });

  /// When [collectedInArea] for the window starting at [from] was last saved
  /// on this phone, or null if it never was. Shown so a remittance read
  /// without signal says how old it is.
  Future<Result<DateTime?>> collectedInAreaSavedAt(
    AreaId areaId, {
    required DateTime from,
  });

  /// The rounding fund month by month, oldest first: the rounding collected,
  /// the Meter Reader's pay from it and what is saved. Backed by
  /// `fn_rounding_fund`, which only the Cashier and the Area President may
  /// call.
  Future<Result<List<RoundingFundMonth>>> roundingFund(AreaId areaId);

  /// Every handover of BOHECO's money to the Meter Reader recorded in this
  /// area. Cashier and Area President only.
  Future<Result<List<RemitHandover>>> remitHandovers(AreaId areaId);

  /// The Cashier records handing [year]/[month]'s BOHECO money to the Meter
  /// Reader. The server freezes the amounts. Needs signal.
  Future<Result<RemitHandover>> recordRemitHandover({
    required int year,
    required int month,
  });
}

/// The Cashier handing one month's BOHECO money to the Meter Reader, as
/// recorded at that moment.
final class RemitHandover {
  final int year;
  final int month;
  final Money toBoheco;
  final Money readerPay;
  final Money gap;
  final String? handedToName;
  final DateTime handedAt;

  const RemitHandover({
    required this.year,
    required this.month,
    required this.toBoheco,
    required this.readerPay,
    required this.gap,
    required this.handedAt,
    this.handedToName,
  });
}

/// One remittance month of the rounding fund.
///
/// Regular collection totals and historical rounding allocations. Current
/// Reader compensation is a separate PHP500 reserve-fund ledger payout.
final class RoundingFundMonth {
  /// The month handed over on its 28th.
  final int year;
  final int month;

  final Money collected;
  final Money toBoheco;
  final Money rounding;

  /// What the month's bills still owed BOHECO at the handover.
  final Money gap;

  final Money fundBefore;

  /// Held back from the fund to cover [gap]. Not handed over by itself: the
  /// Cashier decides.
  final Money keptForGap;

  final Money readerPay;
  final Money fundAfter;

  const RoundingFundMonth({
    required this.year,
    required this.month,
    required this.collected,
    required this.toBoheco,
    required this.rounding,
    required this.gap,
    required this.fundBefore,
    required this.keptForGap,
    required this.readerPay,
    required this.fundAfter,
  });

  /// Legacy rounding allocation cap; current compensation uses its own ledger.
  static const Money payCap = Money.fromCentavos(30000);
}

/// One cash handover: one receipt, however many bills it settled.
///
/// This is the shape of a receipt, not of a bill payment, and that is the
/// point. `v_payment_history` returns one row per bill settled, all of them
/// carrying the same receipt number, because that is what the Consumer
/// History mockup shows - the same OR number against June, July and August.
/// The data layer groups those rows back into one of these per receipt.
///
/// [totalCollected], [cashTendered] and [changeDue] are facts about the
/// handover, not about any one bill, which is why they live here and not on
/// [SettledBill].
final class PaymentSummary {
  final String collectionKind;
  bool get isPondoRepayment => collectionKind == 'pondo_repayment';
  final String receiptNo;

  /// Who paid, as both an identifier and the name shown on the Cashier's
  /// receipt list.
  final ConsumerId consumerId;
  final String consumerName;

  /// Printed on the receipt and scanned at the counter to check it is real.
  final String verificationCode;

  final DateTime paidAt;

  /// What was actually handed over and receipted.
  final Money totalCollected;

  /// Null when the cashier did not record the cash given.
  final Money? cashTendered;
  final Money? changeDue;

  /// Which bills this one handover settled, and how much went to each.
  final List<SettledBill> bills;

  const PaymentSummary({
    this.collectionKind = 'regular',
    required this.receiptNo,
    required this.consumerId,
    required this.consumerName,
    required this.verificationCode,
    required this.paidAt,
    required this.totalCollected,
    required this.bills,
    this.cashTendered,
    this.changeDue,
  });

  /// How many months this receipt covered. The number the receipt screen
  /// says out loud, because settling three months at once is the normal case
  /// and a receipt that hid it would look wrong to the consumer holding it.
  int get billCount => bills.length;
}

/// One allocation line: how much of a handover went to one bill.
final class SettledBill {
  final BillId billId;
  final BillNumber billNo;

  /// "August 2026", as the view returns it. Text for a receipt line, so it is
  /// kept as text rather than parsed into a cycle and formatted back again.
  final String cycleLabel;

  final Money amountPaid;

  /// How much of [amountPaid] is owed to BOHECO. The rest is the Meter
  /// Reader's share from rounding the bill up to the peso. Null for a bill
  /// posted before BillAlert kept BOHECO's own figure.
  final Money? bohecoShare;

  const SettledBill({
    required this.billId,
    required this.billNo,
    required this.cycleLabel,
    required this.amountPaid,
    this.bohecoShare,
  });

  /// The Meter Reader's share of this line, or null when it is not known.
  Money? get readerShare =>
      bohecoShare == null ? null : amountPaid - bohecoShare!;
}

/// One cashier's takings for one day.
///
/// The two fields are what `v_cashier_daily_summary` actually has, and what
/// the Cashier screen says: "Today's collections P3,697.15 - 3 receipts".
/// Receipts, not bills: one handover settling three months is one receipt and
/// counts once.
final class CollectionSummary {
  final int receiptCount;
  final Money totalCollected;

  const CollectionSummary({
    required this.receiptCount,
    required this.totalCollected,
  });

  /// A day on which nothing has been collected yet. A real answer, not a
  /// failure - the view simply has no row for a cashier who has taken no
  /// money today.
  static const CollectionSummary empty = CollectionSummary(
    receiptCount: 0,
    totalCollected: Money.zero,
  );
}
