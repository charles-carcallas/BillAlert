import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/result/result.dart';
import '../../domain/repositories/payment_repository.dart';
import '../../domain/value_objects/ids.dart';
import '../../domain/value_objects/money.dart';
import '../local/app_database.dart';
import '../supabase/failure_mapper.dart';

/// Payment history and the cashier's daily takings.
///
/// Both methods are reads. Recording a payment is not here and must not be:
/// it goes through the outbox and then through `fn_record_payment`, which
/// settles every bill of a handover in one transaction.
class PaymentRepositoryImpl implements PaymentRepository {
  // ignore: unused_field
  final AppDatabase _db;
  final SupabaseClient _client;

  const PaymentRepositoryImpl(this._db, this._client);

  /// CON-03. Every receipt this consumer has been given, newest first.
  ///
  /// `v_payment_history` returns one row per bill settled, so a handover that
  /// cleared June, July and August arrives as three rows carrying the same
  /// receipt number. Returning those three as three payments would tell the
  /// consumer they paid three times. They are grouped back into one
  /// [PaymentSummary] per receipt here, which is what "one handover, one
  /// receipt" means when it reaches a screen.
  ///
  /// The grouping is display shaping, not business logic moved off the
  /// server: the money was already allocated by `fn_record_payment`, and
  /// nothing here re-decides who was paid what.
  @override
  Future<Result<List<PaymentSummary>>> historyFor(ConsumerId consumerId) async {
    try {
      final rows = await _client
          .from('v_payment_history')
          .select()
          .eq('consumer_id', consumerId.value)
          .order('paid_at', ascending: false);

      return Ok<List<PaymentSummary>>(_groupIntoReceipts(rows));
    } catch (error, stackTrace) {
      return Err<List<PaymentSummary>>(FailureMapper.from(error, stackTrace));
    }
  }

  /// CSH-01. What this area has taken today.
  ///
  /// The view has one row per cashier per collection date, so it is filtered
  /// to today in Philippine time. `collection_date` is already a Philippine
  /// date - the view computes it with `fn_ph_today(pt.paid_at)` - so the
  /// comparison is date to date and never crosses a timezone.
  ///
  /// No row means no money taken yet today, which is an answer and not an
  /// error, so it returns [CollectionSummary.empty] rather than a failure.
  @override
  Future<Result<CollectionSummary>> dailySummary(AreaId areaId) async {
    try {
      final rows = await _client
          .from('v_cashier_daily_summary')
          .select('receipt_count, total_collected')
          .eq('area_id', areaId.value);

      if (rows.isEmpty) {
        return const Ok<CollectionSummary>(CollectionSummary.empty);
      }

      // An area can have more than one cashier, and the view is per cashier.
      // The screen shows the area's takings, so the rows are added up.
      var receipts = 0;
      var collected = Money.zero;
      for (final Map<String, dynamic> row in rows) {
        receipts += (row['receipt_count'] as num?)?.toInt() ?? 0;
        collected = collected + _money(row['total_collected']);
      }

      return Ok<CollectionSummary>(
        CollectionSummary(receiptCount: receipts, totalCollected: collected),
      );
    } catch (error, stackTrace) {
      return Err<CollectionSummary>(FailureMapper.from(error, stackTrace));
    }
  }

  /// CSH-03. Every receipt issued in this area, newest first.
  ///
  /// NOTE for whoever builds the receipt list against the mockup: it shows
  /// each receipt under the payer's name, and `v_payment_history` does not
  /// carry one. It has `consumer_id` but no `consumer_name`, so the name has
  /// to come from somewhere else or be added to the view - the same one-line
  /// change that `cycle_year` and `cycle_month` needed. Until then this
  /// returns the receipt without a name rather than joining in Dart.
  @override
  Future<Result<List<PaymentSummary>>> recentInArea(
    AreaId areaId, {
    int limit = 50,
  }) async {
    try {
      final rows = await _client
          .from('v_payment_history')
          .select()
          .eq('area_id', areaId.value)
          .order('paid_at', ascending: false)
          // The limit counts ROWS, and a row is one bill settled, so a
          // handover covering three months uses three of them. Erring high
          // is cheaper than a receipt appearing with a month missing.
          .limit(limit);

      return Ok<List<PaymentSummary>>(_groupIntoReceipts(rows));
    } catch (error, stackTrace) {
      return Err<List<PaymentSummary>>(FailureMapper.from(error, stackTrace));
    }
  }

  /// Collapses the per-bill rows of `v_payment_history` into one summary per
  /// receipt, keeping the order the rows arrived in (newest first).
  static List<PaymentSummary> _groupIntoReceipts(List<Map<String, dynamic>> rows) {
    // A LinkedHashMap by insertion order, which is what a plain Dart Map is.
    // That is what preserves "newest first" without a second sort.
    final byReceipt = <String, List<Map<String, dynamic>>>{};
    for (final Map<String, dynamic> row in rows) {
      final receiptNo = row['receipt_no'] as String;
      byReceipt.putIfAbsent(receiptNo, () => <Map<String, dynamic>>[]).add(row);
    }

    return byReceipt.entries.map((entry) {
      // Every row of one receipt carries the same transaction facts, so the
      // first is as good as any for them.
      final first = entry.value.first;

      return PaymentSummary(
        receiptNo: entry.key,
        consumerId: ConsumerId(first['consumer_id'] as String),
        verificationCode: first['verification_code'] as String? ?? '',
        paidAt: DateTime.parse(first['paid_at'] as String),
        totalCollected: _money(first['transaction_total']),
        cashTendered: _moneyOrNull(first['cash_tendered']),
        changeDue: _moneyOrNull(first['change_due']),
        bills: entry.value
            .map((Map<String, dynamic> row) => SettledBill(
                  billId: BillId(row['bill_id'] as String),
                  billNo: BillNumber(row['bill_no'] as String),
                  cycleLabel: row['cycle_label'] as String? ?? '',
                  amountPaid: _money(row['amount_paid']),
                ))
            .toList(),
      );
    }).toList();
  }

  /// Reads a `numeric(12,2)` through its text form.
  ///
  /// PostgREST sends numerics as JSON numbers, and going through
  /// `Money.tryParse` on the string keeps the value away from `double` even
  /// so - the same rule that applies at every other boundary in this app.
  static Money _money(Object? value) =>
      value == null ? Money.zero : Money.tryParse(value.toString()) ?? Money.zero;

  static Money? _moneyOrNull(Object? value) =>
      value == null ? null : Money.tryParse(value.toString());
}
