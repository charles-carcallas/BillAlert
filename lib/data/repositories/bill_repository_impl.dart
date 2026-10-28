import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors/app_failure.dart';
import '../../core/result/result.dart';
import '../../domain/entities/bill.dart';
import '../../domain/repositories/bill_repository.dart';
import '../../domain/value_objects/cycle_label.dart';
import '../../domain/value_objects/ids.dart';
import '../../domain/value_objects/kwh.dart';
import '../../domain/value_objects/money.dart';
import '../../domain/value_objects/ph_date.dart';
import '../local/app_database.dart';
import '../local/query_cache.dart';
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
  static const String _baseBillColumns =
      'bill_id:id, bill_no, consumer_id, cycle_year, cycle_month, consumption, '
      'total_amount, due_date, amount_paid, waiver_amount, waiver_assignment_id, waived_at, external_paid, settlement_state, collection_cutoff_at';

  /// Appended to `v_bill_status` by `15_bill_meter_readings.sql` so Bill
  /// Details can show the dial figures behind the consumption (FR-25).
  static const String _readingColumns =
      'previous_reading, current_reading, reading_date';

  /// SQLSTATE 42703: the column is not there.
  static const String _undefinedColumn = '42703';

  /// Whether this server has run migration 15 yet.
  ///
  /// It is asked by requesting the columns and seeing what comes back, not by
  /// interrogating the schema: one wasted round trip the first time a phone
  /// meets an un-migrated server, and none after that.
  ///
  /// Static because it describes the server, not this object, and a phone
  /// talks to one server. It only ever flips to false, so applying the
  /// migration while the app is open is not noticed until the app is next
  /// started — which is the right trade against re-testing a known-missing
  /// column on every query for the life of the process.
  ///
  /// The cost of guessing wrong in the optimistic direction is one retried
  /// query. The cost of guessing wrong the other way was a household opening
  /// History and being told the server is broken, which is what this exists
  /// to prevent.
  static bool _serverHasReadingColumns = true;

  /// Lets a test start from a known state, since the flag outlives any one
  /// repository.
  @visibleForTesting
  static void resetSchemaProbe() => _serverHasReadingColumns = true;

  static String get _billColumns => _serverHasReadingColumns
      ? '$_baseBillColumns, $_readingColumns'
      : _baseBillColumns;

  /// For the background notification check, which reads bills without the
  /// cache and so without this class. It asks only whether a bill is unpaid
  /// and when it falls due, so it never wants the readings and is never
  /// exposed to a server that lacks them.
  static const String billColumns = _baseBillColumns;

  /// Runs a bill query, and if the server turns out not to have the reading
  /// columns, runs it once more without them.
  ///
  /// The retry is what keeps a missing migration to a "Not recorded" on one
  /// row of Bill Details instead of a failed screen. Anything other than
  /// 42703 is rethrown untouched: a real server problem must not be quietly
  /// retried into a half-populated bill.
  static Future<T> _withBillColumns<T>(
    Future<T> Function(String columns) run,
  ) async {
    try {
      return await run(_billColumns);
    } on PostgrestException catch (error) {
      if (error.code != _undefinedColumn || !_serverHasReadingColumns) {
        rethrow;
      }
      _serverHasReadingColumns = false;
      return await run(_billColumns);
    }
  }

  static String _consumerCacheKey(ConsumerId id) =>
      'consumer_bills:${id.value}';

  /// FR-21b. The Admin queue: readings with no amount yet, oldest first.
  ///
  /// The view carries no `total_amount`, `due_date` or `amount_paid` column
  /// at all - by definition these bills have none - and [Bill.fromJson] reads
  /// those missing keys as null, which is exactly what `isUnpriced` means.
  /// Returns the queue row, not a bare [Bill]: the Admin has to see whose
  /// bill they are pricing and what it consumed, and the view already
  /// returns both alongside the bill columns.
  @override
  Future<Result<List<AwaitingAmountEntry>>> awaitingAmount(
    AreaId areaId,
  ) async {
    try {
      final rows = await QueryCache(_db).rows(
        'awaiting_amount:${areaId.value}',
        () => _client
            .from('v_readings_awaiting_amount')
            .select()
            .eq('area_id', areaId.value)
            // Oldest first: the household that has waited longest is priced
            // first, and that wait is what the screen leads with.
            .order('reading_date', ascending: true),
      );

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
    final epoch = _db.cacheEpoch;
    try {
      final row = await _client
          .from('v_consumer_current_bill')
          .select()
          .eq('consumer_id', consumerId.value)
          .maybeSingle();

      if (epoch != _db.cacheEpoch) {
        throw const AuthFailure('The signed-in account changed.');
      }
      if (row != null) await _upsertCachedBill(row);
      await _markConsumerBillsRefreshed(consumerId);
      return Ok<Bill?>(row == null ? null : Bill.fromJson(row));
    } catch (error, stackTrace) {
      final failure = epoch != _db.cacheEpoch
          ? const AuthFailure('The signed-in account changed.')
          : FailureMapper.from(error, stackTrace);
      if (failure is NetworkFailure) {
        final cached = await _cachedBillsFor(consumerId);
        switch (cached) {
          case Err(:final failure):
            return Err<Bill?>(failure);
          case Ok(:final value):
            if (value.isNotEmpty || await _hasConsumerBillsCache(consumerId)) {
              final open = value.where((Bill bill) => !bill.isSettled).toList()
                ..sort(_currentBillOrder);
              return Ok<Bill?>(open.isEmpty ? null : open.first);
            }
        }
      }
      return Err<Bill?>(failure);
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
    final epoch = _db.cacheEpoch;
    try {
      final rows = await _withBillColumns(
        (String columns) async => await _client
            .from('v_bill_status')
            .select(columns)
            .eq('consumer_id', consumerId.value)
            .order('period_start', ascending: false)
            .limit(limit),
      );

      if (epoch != _db.cacheEpoch) {
        throw const AuthFailure('The signed-in account changed.');
      }
      await _replaceCachedBills(consumerId, rows);
      await _markConsumerBillsRefreshed(consumerId);
      return Ok<List<Bill>>(rows.map(Bill.fromJson).toList());
    } catch (error, stackTrace) {
      final failure = epoch != _db.cacheEpoch
          ? const AuthFailure('The signed-in account changed.')
          : FailureMapper.from(error, stackTrace);
      if (failure is NetworkFailure) {
        final cached = await _cachedBillsFor(consumerId);
        switch (cached) {
          case Err(:final failure):
            return Err<List<Bill>>(failure);
          case Ok(:final value):
            if (value.isNotEmpty || await _hasConsumerBillsCache(consumerId)) {
              final history = List<Bill>.of(value)
                ..sort((Bill a, Bill b) => b.cycle.compareTo(a.cycle));
              return Ok<List<Bill>>(history.take(limit).toList());
            }
        }
      }
      return Err<List<Bill>>(failure);
    }
  }

  @override
  Future<Result<List<Bill>>> readingsForCycle(
    AreaId areaId,
    CycleLabel cycle,
  ) async {
    final epoch = _db.cacheEpoch;
    try {
      final rows = await _withBillColumns(
        (String columns) async => await _client
            .from('v_bill_status')
            .select(columns)
            .eq('area_id', areaId.value)
            .eq('cycle_year', cycle.year)
            .eq('cycle_month', cycle.month),
      );

      // Saved so the reading sheet can still be written up with no signal.
      if (epoch != _db.cacheEpoch) {
        throw const AuthFailure('The signed-in account changed.');
      }
      await _db.transaction(() async {
        final ids = rows.map((row) => row['bill_id'] as String).toList();
        await (_db.delete(_db.cachedBills)..where(
              (table) =>
                  table.cycleLabel.equals(cycle.value) & table.id.isNotIn(ids),
            ))
            .go();
        for (final row in rows) {
          await _upsertCachedBill(row);
        }
      });
      await _markRefreshed(_areaCycleCacheKey(areaId, cycle));
      return Ok<List<Bill>>(rows.map(Bill.fromJson).toList());
    } catch (error, stackTrace) {
      final failure = epoch != _db.cacheEpoch
          ? const AuthFailure('The signed-in account changed.')
          : FailureMapper.from(error, stackTrace);
      if (failure is NetworkFailure &&
          await _hasCache(_areaCycleCacheKey(areaId, cycle))) {
        try {
          // The cache holds only the signed-in reader's own area.
          final saved = await (_db.select(
            _db.cachedBills,
          )..where((table) => table.cycleLabel.equals(cycle.value))).get();
          return Ok<List<Bill>>(
            await Future.wait(saved.map(_billFromCacheRow)),
          );
        } catch (error) {
          return Err<List<Bill>>(
            ServerFailure(
              'Could not read the readings saved on this phone.',
              error.toString(),
            ),
          );
        }
      }
      return Err<List<Bill>>(failure);
    }
  }

  static String _areaCycleCacheKey(AreaId areaId, CycleLabel cycle) =>
      'area_bills:${areaId.value}:${cycle.value}';

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

  /// One bill, priced or not.
  @override
  Future<Result<Bill?>> byId(BillId id, {ConsumerId? consumerId}) async {
    final epoch = _db.cacheEpoch;
    try {
      final row = await _withBillColumns((String columns) async {
        var query = _client
            .from('v_bill_status')
            .select(columns)
            .eq('id', id.value);
        if (consumerId != null) {
          query = query.eq('consumer_id', consumerId.value);
        }
        return await query.maybeSingle();
      });
      if (epoch != _db.cacheEpoch) {
        throw const AuthFailure('Account access changed.');
      }

      return Ok<Bill?>(row == null ? null : Bill.fromJson(row));
    } catch (error, stackTrace) {
      final failure = epoch != _db.cacheEpoch
          ? const AuthFailure('Account access changed.')
          : FailureMapper.from(error, stackTrace);
      if (failure is NetworkFailure) {
        // The bill an Inbox alert or a tapped notification points at is
        // usually one the Bill or History tab has already cached. The cache
        // holds only the signed-in account's rows: it is emptied when someone
        // else signs in on this phone.
        try {
          final CachedBillRow? cached = await (_db.select(
            _db.cachedBills,
          )..where((table) => table.id.equals(id.value))).getSingleOrNull();
          if (cached != null &&
              (consumerId == null || cached.consumerId == consumerId.value)) {
            final bill = await _billFromCacheRow(cached);
            if (epoch != _db.cacheEpoch) return const Err<Bill?>(AuthFailure());
            return Ok<Bill?>(bill);
          }
        } catch (_) {
          // An unreadable cached row is no better than none. The connection
          // problem below is the thing the household can act on.
        }
      }
      // Not "no such bill": without signal, a bill missing from the cache may
      // still exist.
      return Err<Bill?>(failure);
    }
  }

  Future<Bill> _billFromCacheRow(CachedBillRow row) async {
    final metadata =
        await (_db.select(_db.cachedQueries)
              ..where((t) => t.queryKey.equals('bill_waiver:${row.id}')))
            .getSingleOrNull();
    final waiver = metadata == null
        ? <String, dynamic>{}
        : jsonDecode(metadata.rowsJson) as Map<String, dynamic>;
    final cycle = CycleLabel.tryParse(row.cycleLabel);
    if (cycle == null) {
      throw const FormatException('Cached bill has an invalid cycle.');
    }
    return Bill(
      id: BillId(row.id),
      billNo: BillNumber(row.billNo),
      consumerId: ConsumerId(row.consumerId),
      cycle: cycle,
      consumption: Kwh.fromHundredths(row.consumptionHundredths),
      totalAmount: row.totalAmountCentavos == null
          ? null
          : Money.fromCentavos(row.totalAmountCentavos!),
      dueDate: row.dueDate == null ? null : PhDate.tryParse(row.dueDate!),
      amountPaid: Money.fromCentavos(row.amountPaidCentavos),
      externalPaid:
          Money.tryParse('${waiver['external_paid'] ?? 0}') ?? Money.zero,
      settlementState: waiver['settlement_state'] as String?,
      collectionCutoffAt: DateTime.tryParse(
        '${waiver['collection_cutoff_at'] ?? ''}',
      ),
      waiverAmount:
          Money.tryParse('${waiver["waiver_amount"] ?? 0}') ?? Money.zero,
      waiverAssignmentId: waiver['waiver_assignment_id'] as String?,
      waivedAt: DateTime.tryParse('${waiver["waived_at"] ?? ""}'),
      previousReading: row.previousReadingHundredths == null
          ? null
          : Kwh.fromHundredths(row.previousReadingHundredths!),
      currentReading: row.currentReadingHundredths == null
          ? null
          : Kwh.fromHundredths(row.currentReadingHundredths!),
      readingDate: row.readingDate == null
          ? null
          : PhDate.tryParse(row.readingDate!),
    );
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
      final rows = await QueryCache(_db).rows(
        'payable:${consumerId.value}',
        () => _withBillColumns(
          (String columns) async => await _client
              .from('v_bill_status')
              .select(columns)
              .eq('consumer_id', consumerId.value)
              .not('total_amount', 'is', null)
              .not('status', 'in', '(paid,waived)')
              // Oldest debt first: the order a cashier settles them in.
              .order('due_date', ascending: true),
        ),
      );

      return Ok<List<Bill>>(rows.map(Bill.fromJson).toList());
    } catch (error, stackTrace) {
      return Err<List<Bill>>(FailureMapper.from(error, stackTrace));
    }
  }

  /// CSH-02. Who owes what, for the Cashier's consumer list.
  ///
  /// This is the one place `v_consumer_outstanding` belongs: it is a
  /// per-consumer roll-up, so it answers "who owes what" and cannot answer
  /// "which bills" - that is [payableFor], against `v_bill_status`.
  @override
  Future<Result<List<ConsumerOutstanding>>> outstandingInArea(
    AreaId areaId,
  ) async {
    try {
      final rows = await QueryCache(_db).rows(
        'outstanding:${areaId.value}',
        () => _client
            .from('v_consumer_outstanding')
            .select()
            .eq('area_id', areaId.value)
            .order('consumer_name', ascending: true),
      );

      return Ok<List<ConsumerOutstanding>>(
        rows.map(ConsumerOutstanding.fromJson).toList(),
      );
    } catch (error, stackTrace) {
      return Err<List<ConsumerOutstanding>>(
        FailureMapper.from(error, stackTrace),
      );
    }
  }

  @override
  Future<Result<List<ConsumerOutstanding>>> currentCollectionsInArea(
    AreaId areaId,
    PhDate today,
  ) async {
    try {
      final cycle = CycleLabel.of(today);
      final rows = await QueryCache(_db).rows(
        'current-collections:${areaId.value}:$cycle',
        () => _client
            .from('v_bill_status')
            .select(
              'consumer_id, consumer_no, first_name, last_name, purok, '
              'cycle_year, cycle_month, total_amount, balance, due_date, settlement_state',
            )
            .eq('area_id', areaId.value)
            .not('status', 'in', '(paid,waived)')
            .or('total_amount.is.null,balance.gt.0'),
      );
      final groups = <String, List<Map<String, dynamic>>>{};
      for (final row in rows) {
        groups.putIfAbsent(row['consumer_id'] as String, () => []).add(row);
      }
      final result = <ConsumerOutstanding>[];
      for (final bills in groups.values) {
        bool overdue(Map<String, dynamic> b) {
          final due = PhDate.tryParse('${b['due_date']}');
          return b['total_amount'] != null &&
              due != null &&
              due.compareTo(today) < 0 &&
              (Money.tryParse('${b['balance']}') ?? Money.zero) > Money.zero;
        }

        final current = bills
            .where(
              (b) =>
                  b['cycle_year'] == cycle.year &&
                  b['cycle_month'] == cycle.month &&
                  !overdue(b),
            )
            .toList();
        // A household belongs in Overdue until every past-due balance is paid.
        if (current.isEmpty ||
            bills.any(overdue) ||
            bills.any(
              (b) =>
                  b['settlement_state'] != null &&
                  b['settlement_state'] != 'settled',
            )) {
          continue;
        }
        final h = current.first;
        result.add(
          ConsumerOutstanding(
            consumerId: ConsumerId(h['consumer_id'] as String),
            consumerNo: ConsumerNumber(h['consumer_no'] as String),
            consumerName: '${h['first_name']} ${h['last_name']}',
            purok: h['purok'] as String?,
            payableBillCount: current
                .where((b) => b['total_amount'] != null)
                .length,
            unpricedBillCount: current
                .where((b) => b['total_amount'] == null)
                .length,
            overdueCount: bills.where(overdue).length,
            totalOutstanding: current.fold(
              Money.zero,
              (sum, b) =>
                  sum + (Money.tryParse('${b['balance']}') ?? Money.zero),
            ),
          ),
        );
      }
      return Ok(result);
    } catch (error, stackTrace) {
      return Err(FailureMapper.from(error, stackTrace));
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
    final epoch = _db.cacheEpoch;
    try {
      final rows = await _withBillColumns(
        // [refreshFor] additionally caches when the bill was generated.
        (String columns) async => await _client
            .from('v_bill_status')
            .select('$columns, generated_at')
            .eq('consumer_id', consumerId.value)
            .eq('cycle_year', cycle.year)
            .eq('cycle_month', cycle.month),
      );

      if (epoch != _db.cacheEpoch) {
        throw const AuthFailure('The signed-in account changed.');
      }
      await _db.transaction(() async {
        for (final Map<String, dynamic> row in rows) {
          await _cacheWaiver(row);
          final Money? total = row['total_amount'] == null
              ? null
              : Money.tryParse(row['total_amount'].toString());
          final Money paid = row['amount_paid'] == null
              ? Money.zero
              : Money.tryParse(row['amount_paid'].toString()) ?? Money.zero;
          final Kwh consumption =
              Kwh.tryParse(row['consumption'].toString()) ?? Kwh.zero;
          final Kwh? previous = _readingFrom(row['previous_reading']);
          final Kwh? current = _readingFrom(row['current_reading']);

          await _db
              .into(_db.cachedBills)
              .insertOnConflictUpdate(
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
                  previousReadingHundredths: Value<int?>(previous?.hundredths),
                  currentReadingHundredths: Value<int?>(current?.hundredths),
                  readingDate: Value<String?>(row['reading_date'] as String?),
                ),
              );
        }
      });

      return const Ok<void>(null);
    } catch (error, stackTrace) {
      return Err<void>(FailureMapper.from(error, stackTrace));
    }
  }

  Future<void> _replaceCachedBills(
    ConsumerId consumerId,
    List<Map<String, dynamic>> rows,
  ) async {
    await _db.transaction(() async {
      await (_db.delete(
        _db.cachedBills,
      )..where((table) => table.consumerId.equals(consumerId.value))).go();
      for (final row in rows) {
        await _cacheWaiver(row);
        await _db
            .into(_db.cachedBills)
            .insertOnConflictUpdate(_cachedBillCompanion(row));
      }
    });
  }

  Future<void> _upsertCachedBill(Map<String, dynamic> row) async {
    await _db.transaction(() async {
      await _cacheWaiver(row);
      await _db
          .into(_db.cachedBills)
          .insertOnConflictUpdate(_cachedBillCompanion(row));
    });
  }

  Future<void> _cacheWaiver(Map<String, dynamic> row) async {
    await _db
        .into(_db.cachedQueries)
        .insertOnConflictUpdate(
          CachedQueriesCompanion.insert(
            queryKey: 'bill_waiver:${row['bill_id']}',
            rowsJson: jsonEncode({
              'waiver_amount': row['waiver_amount'] ?? 0,
              'waiver_assignment_id': row['waiver_assignment_id'],
              'waived_at': row['waived_at'],
              'external_paid': row['external_paid'] ?? 0,
              'settlement_state': row['settlement_state'],
              'collection_cutoff_at': row['collection_cutoff_at'],
            }),
            savedAt: DateTime.now().toUtc().toIso8601String(),
          ),
        );
  }

  static CachedBillsCompanion _cachedBillCompanion(Map<String, dynamic> row) {
    final cycle = CycleLabel.fromRow(row);
    if (cycle == null) {
      throw const FormatException('Cannot cache a bill without its cycle.');
    }
    final total = row['total_amount'] == null
        ? null
        : Money.tryParse(row['total_amount'].toString());
    final paid = row['amount_paid'] == null
        ? Money.zero
        : Money.tryParse(row['amount_paid'].toString()) ?? Money.zero;
    final consumption = Kwh.tryParse(row['consumption'].toString()) ?? Kwh.zero;
    final previous = _readingFrom(row['previous_reading']);
    final current = _readingFrom(row['current_reading']);

    return CachedBillsCompanion.insert(
      id: row['bill_id'] as String,
      billNo: row['bill_no'] as String,
      consumerId: row['consumer_id'] as String,
      cycleLabel: cycle.value,
      consumptionHundredths: consumption.hundredths,
      amountPaidCentavos: Value<int>(paid.centavos),
      totalAmountCentavos: Value<int?>(total?.centavos),
      dueDate: Value<String?>(row['due_date'] as String?),
      generatedAt: Value<String?>(row['generated_at'] as String?),
      previousReadingHundredths: Value<int?>(previous?.hundredths),
      currentReadingHundredths: Value<int?>(current?.hundredths),
      readingDate: Value<String?>(row['reading_date'] as String?),
    );
  }

  /// A meter reading as the view returned it, or null when the query did not
  /// carry one. Unparseable text is null too: a reading the cache cannot
  /// trust is better absent than stored wrong, and the screen says so.
  static Kwh? _readingFrom(Object? value) =>
      value == null ? null : Kwh.tryParse(value.toString());

  Future<Result<List<Bill>>> _cachedBillsFor(ConsumerId consumerId) async {
    try {
      final query = _db.select(_db.cachedBills)
        ..where((table) => table.consumerId.equals(consumerId.value));
      final rows = await query.get();
      return Ok<List<Bill>>(await Future.wait(rows.map(_billFromCacheRow)));
    } catch (error) {
      return Err<List<Bill>>(
        ServerFailure(
          'Could not read the bills saved on this phone.',
          error.toString(),
        ),
      );
    }
  }

  Future<void> _markConsumerBillsRefreshed(ConsumerId consumerId) async {
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

  Future<bool> _hasConsumerBillsCache(ConsumerId consumerId) async {
    final query = _db.select(
      _db.syncMeta,
    )..where((table) => table.tableName_.equals(_consumerCacheKey(consumerId)));
    return await query.getSingleOrNull() != null;
  }

  static int _currentBillOrder(Bill a, Bill b) {
    final aDue = a.dueDate;
    final bDue = b.dueDate;
    if (aDue == null && bDue != null) return 1;
    if (aDue != null && bDue == null) return -1;
    if (aDue != null && bDue != null) {
      final byDue = aDue.compareTo(bDue);
      if (byDue != 0) return byDue;
    }
    return a.cycle.compareTo(b.cycle);
  }
}
