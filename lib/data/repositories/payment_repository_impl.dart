import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors/app_failure.dart';
import '../../core/result/result.dart';
import '../../domain/repositories/payment_repository.dart';
import '../../domain/value_objects/ids.dart';
import '../../domain/value_objects/money.dart';
import '../local/app_database.dart';
import '../local/query_cache.dart';
import '../supabase/failure_mapper.dart';

/// Payment history and the cashier's daily takings.
///
/// Both methods are reads. Recording a payment is not here and must not be:
/// it goes through the outbox and then through `fn_record_payment`, which
/// settles every bill of a handover in one transaction.
class PaymentRepositoryImpl implements PaymentRepository {
  final AppDatabase _db;
  final SupabaseClient _client;

  const PaymentRepositoryImpl(this._db, this._client);

  static String _consumerCacheKey(ConsumerId id) =>
      'consumer_payments:${id.value}';

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

      await _replaceConsumerCache(consumerId, rows);
      await _markConsumerPaymentsRefreshed(consumerId);
      return Ok<List<PaymentSummary>>(_groupIntoReceipts(rows));
    } catch (error, stackTrace) {
      final failure = FailureMapper.from(error, stackTrace);
      if (failure is NetworkFailure) {
        final cached = await _cachedHistoryFor(consumerId);
        switch (cached) {
          case Err(:final failure):
            return Err<List<PaymentSummary>>(failure);
          case Ok(:final value):
            if (value.isNotEmpty ||
                await _hasConsumerPaymentsCache(consumerId)) {
              return Ok<List<PaymentSummary>>(value);
            }
        }
      }
      return Err<List<PaymentSummary>>(failure);
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
      // Keyed by the Philippine date, so a total saved yesterday is never
      // shown as today's takings.
      final DateTime manila = DateTime.now().toUtc().add(
        const Duration(hours: 8),
      );
      final String today = '${manila.year}-${manila.month}-${manila.day}';
      final rows = await QueryCache(_db).rows(
        'daily_summary:${areaId.value}:$today',
        () => _client
            .from('v_cashier_daily_summary')
            .select('receipt_count, total_collected')
            .eq('area_id', areaId.value),
      );

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
  /// The payer's name comes from `v_payment_history`; keeping that read in
  /// the view avoids a second query or a join in Dart.
  @override
  Future<Result<List<PaymentSummary>>> recentInArea(
    AreaId areaId, {
    int limit = 50,
  }) async {
    try {
      final rows = await QueryCache(_db).rows(
        'recent_receipts:${areaId.value}:$limit',
        () => _client
            .from('v_payment_history')
            .select()
            .eq('area_id', areaId.value)
            .order('paid_at', ascending: false)
            // The limit counts ROWS, and a row is one bill settled, so a
            // handover covering three months uses three of them. Erring high
            // is cheaper than a receipt appearing with a month missing.
            .limit(limit),
      );

      return Ok<List<PaymentSummary>>(_groupIntoReceipts(rows));
    } catch (error, stackTrace) {
      return Err<List<PaymentSummary>>(FailureMapper.from(error, stackTrace));
    }
  }

  @override
  Future<Result<List<PaymentSummary>>> collectedInArea(
    AreaId areaId, {
    required DateTime from,
    required DateTime until,
  }) async {
    try {
      // No row limit: a remittance with a receipt missing would not match
      // the cash in hand, which is the one thing it exists to do.
      final rows = await _client
          .from('v_payment_history')
          .select()
          .eq('area_id', areaId.value)
          .gte('paid_at', from.toUtc().toIso8601String())
          .lt('paid_at', until.toUtc().toIso8601String())
          .order('paid_at', ascending: false);

      // Saved for the handover itself, which may be made with no signal.
      await _replaceRangeCache(from, until, rows);
      await _markRefreshed(_areaRangeCacheKey(areaId, from));
      return Ok<List<PaymentSummary>>(_groupIntoReceipts(rows));
    } catch (error, stackTrace) {
      final failure = FailureMapper.from(error, stackTrace);
      if (failure is NetworkFailure &&
          await _hasCache(_areaRangeCacheKey(areaId, from))) {
        // The cache only ever holds the signed-in staff member's own area,
        // so every saved receipt in the window belongs to this remittance.
        return _cachedReceipts(
          (CachedPaymentRow row) => _inRange(row.paidAt, from, until),
        );
      }
      return Err<List<PaymentSummary>>(failure);
    }
  }

  @override
  Future<Result<DateTime?>> collectedInAreaSavedAt(
    AreaId areaId, {
    required DateTime from,
  }) async {
    try {
      final key = _areaRangeCacheKey(areaId, from);
      final row = await (_db.select(
        _db.syncMeta,
      )..where((table) => table.tableName_.equals(key))).getSingleOrNull();
      final value = row?.lastRefreshedAt;
      return Ok<DateTime?>(value == null ? null : DateTime.parse(value));
    } catch (error) {
      return Err<DateTime?>(
        ServerFailure('Could not tell when this was saved.', '$error'),
      );
    }
  }

  static String _areaRangeCacheKey(AreaId areaId, DateTime from) =>
      'area_payments:${areaId.value}:${from.toUtc().toIso8601String()}';

  static bool _inRange(String paidAt, DateTime from, DateTime until) {
    final DateTime? at = DateTime.tryParse(paidAt);
    return at != null && !at.isBefore(from) && at.isBefore(until);
  }

  /// Replaces every saved receipt row inside the window with [rows], so a
  /// receipt the server no longer returns does not linger in a saved total.
  Future<void> _replaceRangeCache(
    DateTime from,
    DateTime until,
    List<Map<String, dynamic>> rows,
  ) async {
    await _db.transaction(() async {
      final existing = await _db.select(_db.cachedPayments).get();
      final stale = existing
          .where((row) => _inRange(row.paidAt, from, until))
          .map((row) => row.id)
          .toList();
      if (stale.isNotEmpty) {
        await (_db.delete(
          _db.cachedPayments,
        )..where((table) => table.id.isIn(stale))).go();
      }
      await _insertRows(rows);
    });
  }

  /// Collapses the per-bill rows of `v_payment_history` into one summary per
  /// receipt, keeping the order the rows arrived in (newest first).
  static List<PaymentSummary> _groupIntoReceipts(
    List<Map<String, dynamic>> rows,
  ) {
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
        consumerName: first['consumer_name'] as String? ?? '',
        verificationCode: first['verification_code'] as String? ?? '',
        paidAt: DateTime.parse(first['paid_at'] as String),
        totalCollected: _money(first['transaction_total']),
        cashTendered: _moneyOrNull(first['cash_tendered']),
        changeDue: _moneyOrNull(first['change_due']),
        bills: entry.value
            .map(
              (Map<String, dynamic> row) => SettledBill(
                billId: BillId(row['bill_id'] as String),
                billNo: BillNumber(row['bill_no'] as String),
                cycleLabel: row['cycle_label'] as String? ?? '',
                amountPaid: _money(row['amount_paid']),
              ),
            )
            .toList(),
      );
    }).toList();
  }

  /// Reads a `numeric(12,2)` through its text form.
  ///
  /// PostgREST sends numerics as JSON numbers, and going through
  /// `Money.tryParse` on the string keeps the value away from `double` even
  /// so - the same rule that applies at every other boundary in this app.
  static Money _money(Object? value) => value == null
      ? Money.zero
      : Money.tryParse(value.toString()) ?? Money.zero;

  static Money? _moneyOrNull(Object? value) =>
      value == null ? null : Money.tryParse(value.toString());

  Future<void> _replaceConsumerCache(
    ConsumerId consumerId,
    List<Map<String, dynamic>> rows,
  ) async {
    await _db.transaction(() async {
      await (_db.delete(
        _db.cachedPayments,
      )..where((table) => table.consumerId.equals(consumerId.value))).go();
      await _insertRows(rows);
    });
  }

  Future<void> _insertRows(List<Map<String, dynamic>> rows) async {
    for (final row in rows) {
      final amountPaid = _money(row['amount_paid']);
      final transactionTotal = _money(row['transaction_total']);
      final cashTendered = _moneyOrNull(row['cash_tendered']);
      final changeDue = _moneyOrNull(row['change_due']);
      await _db
          .into(_db.cachedPayments)
          .insertOnConflictUpdate(
            CachedPaymentsCompanion.insert(
              id: row['payment_id'] as String,
              consumerId: Value<String?>(row['consumer_id'] as String),
              billId: Value<String?>(row['bill_id'] as String),
              billNo: Value<String?>(row['bill_no'] as String),
              cycleLabel: Value<String?>(row['cycle_label'] as String),
              receiptNo: row['receipt_no'] as String,
              consumerName: Value<String?>(
                row['consumer_name'] as String? ?? '',
              ),
              verificationCode: Value<String?>(
                row['verification_code'] as String? ?? '',
              ),
              amountPaidCentavos: amountPaid.centavos,
              transactionTotalCentavos: Value<int?>(transactionTotal.centavos),
              cashTenderedCentavos: Value<int?>(cashTendered?.centavos),
              changeDueCentavos: Value<int?>(changeDue?.centavos),
              paidAt: row['paid_at'] as String,
            ),
          );
    }
  }

  Future<Result<List<PaymentSummary>>> _cachedHistoryFor(
    ConsumerId consumerId,
  ) => _cachedReceipts(
    (CachedPaymentRow row) => row.consumerId == consumerId.value,
  );

  /// Saved receipt rows matching [keep], grouped back into receipts, newest
  /// first.
  Future<Result<List<PaymentSummary>>> _cachedReceipts(
    bool Function(CachedPaymentRow row) keep,
  ) async {
    try {
      final rows =
          (await _db.select(_db.cachedPayments).get()).where(keep).toList()
            ..sort(
              (a, b) => (DateTime.tryParse(b.paidAt) ?? DateTime(0)).compareTo(
                DateTime.tryParse(a.paidAt) ?? DateTime(0),
              ),
            );

      // Rows created by the old, unused cache shape cannot reconstruct an
      // honest receipt. Skip them rather than inventing missing facts.
      final complete = rows.where(
        (row) =>
            row.consumerId != null &&
            row.billId != null &&
            row.billNo != null &&
            row.cycleLabel != null &&
            row.consumerName != null &&
            row.verificationCode != null &&
            row.transactionTotalCentavos != null,
      );
      final byReceipt = <String, List<CachedPaymentRow>>{};
      for (final row in complete) {
        byReceipt
            .putIfAbsent(row.receiptNo, () => <CachedPaymentRow>[])
            .add(row);
      }

      return Ok<List<PaymentSummary>>(
        byReceipt.entries.map((entry) {
          final first = entry.value.first;
          return PaymentSummary(
            receiptNo: entry.key,
            consumerId: ConsumerId(first.consumerId!),
            consumerName: first.consumerName!,
            verificationCode: first.verificationCode!,
            paidAt: DateTime.parse(first.paidAt),
            totalCollected: Money.fromCentavos(first.transactionTotalCentavos!),
            cashTendered: first.cashTenderedCentavos == null
                ? null
                : Money.fromCentavos(first.cashTenderedCentavos!),
            changeDue: first.changeDueCentavos == null
                ? null
                : Money.fromCentavos(first.changeDueCentavos!),
            bills: entry.value
                .map(
                  (row) => SettledBill(
                    billId: BillId(row.billId!),
                    billNo: BillNumber(row.billNo!),
                    cycleLabel: row.cycleLabel!,
                    amountPaid: Money.fromCentavos(row.amountPaidCentavos),
                  ),
                )
                .toList(),
          );
        }).toList(),
      );
    } catch (error) {
      return Err<List<PaymentSummary>>(
        ServerFailure(
          'Could not read the receipts saved on this phone.',
          error.toString(),
        ),
      );
    }
  }

  Future<void> _markRefreshed(String key) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _db
        .into(_db.syncMeta)
        .insertOnConflictUpdate(
          SyncMetaCompanion.insert(
            tableName_: key,
            lastRefreshedAt: Value<String?>(now),
            lastAttemptAt: Value<String?>(now),
            lastError: const Value<String?>(null),
          ),
        );
  }

  Future<bool> _hasCache(String key) async {
    final query = _db.select(_db.syncMeta)
      ..where((table) => table.tableName_.equals(key));
    return await query.getSingleOrNull() != null;
  }

  Future<void> _markConsumerPaymentsRefreshed(ConsumerId consumerId) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _db
        .into(_db.syncMeta)
        .insertOnConflictUpdate(
          SyncMetaCompanion.insert(
            tableName_: _consumerCacheKey(consumerId),
            lastRefreshedAt: Value<String?>(now),
            lastAttemptAt: Value<String?>(now),
            lastError: const Value<String?>(null),
          ),
        );
  }

  Future<bool> _hasConsumerPaymentsCache(ConsumerId consumerId) async {
    final query = _db.select(
      _db.syncMeta,
    )..where((table) => table.tableName_.equals(_consumerCacheKey(consumerId)));
    return await query.getSingleOrNull() != null;
  }
}
