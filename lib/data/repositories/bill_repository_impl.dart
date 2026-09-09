import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/result/result.dart';
import '../../domain/entities/bill.dart';
import '../../domain/repositories/bill_repository.dart';
import '../../domain/value_objects/cycle_label.dart';
import '../../domain/value_objects/ids.dart';
import '../../domain/value_objects/kwh.dart';
import '../../domain/value_objects/money.dart';
import '../local/app_database.dart';
import '../supabase/failure_mapper.dart';

/// Bills, read from the Supabase views and cached on the phone.
///
/// Which view answers which question is the whole design of this class, so it
/// is written down once, here:
///
/// - [awaitingAmount] - `v_readings_awaiting_amount`. The Admin's work queue:
///   bills the cooperative has not priced yet, oldest first.
/// - [currentBillFor] - `v_consumer_current_bill`. One row per consumer, and
///   it deliberately includes unpriced bills, because the seven-day wait is
///   the thing the consumer screen has to be able to show.
/// - [historyFor], [byId], [payableFor] - `v_bill_status`. The per-bill view:
///   `bills.*` plus the consumer and cycle columns, plus the questions that
///   depend on today's date (`is_unpriced`, `is_overdue`, `days_overdue`).
/// - [refreshFor] - reads `v_bill_status` and writes `cached_bills`.
///
/// DEVIATION from the build brief, written down so nobody has to rediscover
/// it: the brief routes [historyFor], [byId] and [payableFor] to
/// `v_consumer_outstanding`. That view cannot answer them. It is a
/// per-consumer roll-up - one row per consumer carrying counts and a total -
/// so it has no bill id, no cycle, no consumption and no amount, and there is
/// no way to build a [Bill] out of it. `v_bill_status` is the per-bill view
/// and is what these three questions need. `v_consumer_outstanding` is still
/// the right view for the Cashier's consumer list, which is a roll-up screen
/// and a different question.
///
/// Row-Level Security does the scoping. The `.eq()` filters below are there
/// to say what each query means, not to enforce security: a cashier who
/// deleted them would still see only their own area.
class BillRepositoryImpl implements BillRepository {
  final AppDatabase _db;
  final SupabaseClient _client;

  const BillRepositoryImpl(this._db, this._client);

  /// The columns [Bill.fromJson] reads, named the way it expects them.
  ///
  /// `v_bill_status` selects `bills.*`, so it calls the primary key `id`,
  /// while the entity and the other two views call it `bill_id`. PostgREST
  /// can rename a column in the request itself (`alias:column`), so the
  /// rename happens once, here, instead of a second `fromJson` existing to
  /// cope with one different column name.
  /// `cycle_year` and `cycle_month` are taken instead of `cycle_label`: they
  /// are integers the server already computed, so the entity never has to
  /// read a month back out of rendered text. `v_bill_status` is the one view
  /// that offers them - confirmed against the live database, not assumed.
  static const String _billColumns =
      'bill_id:id, bill_no, consumer_id, cycle_year, cycle_month, consumption, '
      'total_amount, due_date, amount_paid';

  /// [refreshFor] additionally caches when the bill was generated.
  static const String _cachedBillColumns = '$_billColumns, generated_at';

  /// FR-21b. The Admin queue: readings with no amount yet, oldest first.
  ///
  /// The view carries no `total_amount`, `due_date` or `amount_paid` column
  /// at all - by definition these bills have none - and [Bill.fromJson] reads
  /// those missing keys as null, which is exactly what `isUnpriced` means.
  /// Returns the queue row, not a bare [Bill]: the Admin has to see whose
  /// bill they are pricing and what it consumed, and the view already
  /// returns both alongside the bill columns.
  @override
  Future<Result<List<AwaitingAmountEntry>>> awaitingAmount(AreaId areaId) async {
    try {
      final rows = await _client
          .from('v_readings_awaiting_amount')
          .select()
          .eq('area_id', areaId.value)
          // Oldest first: the household that has waited longest is priced
          // first, and that wait is what the screen leads with.
          .order('reading_date', ascending: true);

      return Ok<List<AwaitingAmountEntry>>(
        rows.map(AwaitingAmountEntry.fromJson).toList(),
      );
    } catch (error, stackTrace) {
      return Err<List<AwaitingAmountEntry>>(
        FailureMapper.from(error, stackTrace),
      );
    }
  }

  /// CON-01. The consumer's current bill, which may still be unpriced.
  ///
  /// The view is `distinct on (consumer_id)`, so there is at most one row per
  /// consumer and `maybeSingle` is the honest way to ask for it. A null
  /// result means "no open bill", which the screen renders as an empty state
  /// rather than as an error.
  @override
  Future<Result<Bill?>> currentBillFor(ConsumerId consumerId) async {
    try {
      final row = await _client
          .from('v_consumer_current_bill')
          .select()
          .eq('consumer_id', consumerId.value)
          .maybeSingle();

      return Ok<Bill?>(row == null ? null : Bill.fromJson(row));
    } catch (error, stackTrace) {
      return Err<Bill?>(FailureMapper.from(error, stackTrace));
    }
  }

  /// CON-07. Recent cycles, newest first.
  ///
  /// Ordered by `period_start` and not by `cycle_label`, because the label is
  /// the text "September 2026" and sorting that alphabetically would put
  /// April before January.
  @override
  Future<Result<List<Bill>>> historyFor(
    ConsumerId consumerId, {
    int limit = 12,
  }) async {
    try {
      final rows = await _client
          .from('v_bill_status')
          .select(_billColumns)
          .eq('consumer_id', consumerId.value)
          .order('period_start', ascending: false)
          .limit(limit);

      return Ok<List<Bill>>(rows.map(Bill.fromJson).toList());
    } catch (error, stackTrace) {
      return Err<List<Bill>>(FailureMapper.from(error, stackTrace));
    }
  }

  /// One bill, priced or not.
  @override
  Future<Result<Bill?>> byId(BillId id) async {
    try {
      final row = await _client
          .from('v_bill_status')
          .select(_billColumns)
          .eq('id', id.value)
          .maybeSingle();

      return Ok<Bill?>(row == null ? null : Bill.fromJson(row));
    } catch (error, stackTrace) {
      return Err<Bill?>(FailureMapper.from(error, stackTrace));
    }
  }

  /// What a cashier may collect against.
  ///
  /// The two filters are the rule "an unpriced bill can never appear in a
  /// payment selection", written as a query. `total_amount is not null` is
  /// the same test the [Bill] entity calls `isPayable`, and the database
  /// agrees: the `bills_unpriced_unpaid` constraint refuses any payment
  /// against a bill with no amount. An unpriced bill that reached this list
  /// would be rejected by the server one screen later, in front of a consumer
  /// standing at the counter holding cash.
  @override
  Future<Result<List<Bill>>> payableFor(ConsumerId consumerId) async {
    try {
      final rows = await _client
          .from('v_bill_status')
          .select(_billColumns)
          .eq('consumer_id', consumerId.value)
          .not('total_amount', 'is', null)
          .neq('status', 'paid')
          // Oldest debt first, which is the order a cashier settles them in.
          .order('due_date', ascending: true);

      return Ok<List<Bill>>(rows.map(Bill.fromJson).toList());
    } catch (error, stackTrace) {
      return Err<List<Bill>>(FailureMapper.from(error, stackTrace));
    }
  }

  /// Refreshes the cached bills for one consumer and one cycle.
  ///
  /// Filtered on `cycle_year` and `cycle_month` rather than on `cycle_label`,
  /// because those are numbers the server already computed, while the label
  /// is display text whose exact spelling is not this query's business.
  ///
  /// Money and kWh go into SQLite as whole centavos and whole hundredths,
  /// never as a `real`. That is the same rule as everywhere else in the app,
  /// and it is why the columns are named `_centavos` and `_hundredths`.
  @override
  Future<Result<void>> refreshFor(
    ConsumerId consumerId,
    CycleLabel cycle,
  ) async {
    try {
      final rows = await _client
          .from('v_bill_status')
          .select(_cachedBillColumns)
          .eq('consumer_id', consumerId.value)
          .eq('cycle_year', cycle.year)
          .eq('cycle_month', cycle.month);

      await _db.transaction(() async {
        for (final Map<String, dynamic> row in rows) {
          final Money? total = row['total_amount'] == null
              ? null
              : Money.tryParse(row['total_amount'].toString());
          final Money paid = row['amount_paid'] == null
              ? Money.zero
              : Money.tryParse(row['amount_paid'].toString()) ?? Money.zero;
          final Kwh consumption =
              Kwh.tryParse(row['consumption'].toString()) ?? Kwh.zero;

          await _db.into(_db.cachedBills).insertOnConflictUpdate(
                CachedBillsCompanion.insert(
                  id: row['bill_id'] as String,
                  billNo: row['bill_no'] as String,
                  consumerId: row['consumer_id'] as String,
                  // Stored in the device's own "2026-09" form, so the cache
                  // reads back the same way whichever view filled it.
                  cycleLabel: cycle.value,
                  consumptionHundredths: consumption.hundredths,
                  amountPaidCentavos: Value<int>(paid.centavos),
                  totalAmountCentavos: Value<int?>(total?.centavos),
                  dueDate: Value<String?>(row['due_date'] as String?),
                  generatedAt: Value<String?>(row['generated_at'] as String?),
                ),
              );
        }
      });

      return const Ok<void>(null);
    } catch (error, stackTrace) {
      return Err<void>(FailureMapper.from(error, stackTrace));
    }
  }
}
