import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors/app_failure.dart';
import '../../core/result/result.dart';
import '../../domain/entities/consumer.dart';
import '../../domain/repositories/consumer_repository.dart';
import '../../domain/value_objects/cycle_label.dart';
import '../../domain/value_objects/ids.dart';
import '../../domain/value_objects/kwh.dart';
import '../dto/consumer_dto.dart';
import '../local/app_database.dart';
import '../supabase/failure_mapper.dart';

/// Households: read from the encrypted cache, refreshed from Supabase.
///
/// The split matters. [areaRoster] answers from SQLite and never touches the
/// network, because the meter reader opens it in a barangay with no signal.
/// [refreshAreaRoster] is the only method here that goes online, and failing
/// it is not an error worth interrupting anyone for.
class ConsumerRepositoryImpl implements ConsumerRepository {
  final AppDatabase _db;
  final SupabaseClient _client;

  const ConsumerRepositoryImpl(this._db, this._client);

  static const String _syncKey = 'cached_consumers';

  @override
  Future<Result<Consumer>> create({
    required ConsumerNumber consumerNo,
    required String firstName,
    required String lastName,
    required AreaId areaId,
    required ProfileId createdBy,
    String? contactNumber,
    String? purok,
  }) async {
    try {
      final row = await _client
          .from('consumers')
          .insert(<String, Object?>{
            'consumer_no': consumerNo.value,
            'first_name': firstName,
            'last_name': lastName,
            // Sent exactly as typed. trg_consumers_normalize_contact owns
            // Philippine mobile normalisation on the server.
            'contact_number': contactNumber,
            'area_id': areaId.value,
            'purok': purok,
            'created_by': createdBy.value,
          })
          .select(
            'id, consumer_no, first_name, last_name, contact_number, '
            'meter_serial_no, area_id, purok, account_status',
          )
          .single();

      return Ok<Consumer>(_fromSupabaseRow(row));
    } on PostgrestException catch (error, stackTrace) {
      if (error.code == '23505') {
        return Err<Consumer>(
          ConflictFailure(
            'Consumer number ${consumerNo.value} is already in use. Please '
            'check the number on the household record.',
            error.toString(),
          ),
        );
      }
      return Err<Consumer>(FailureMapper.from(error, stackTrace));
    } catch (error, stackTrace) {
      return Err<Consumer>(FailureMapper.from(error, stackTrace));
    }
  }

  @override
  Future<Result<List<Consumer>>> areaRoster(AreaId areaId) async {
    try {
      final query = _db.select(_db.cachedConsumers)
        ..where(($CachedConsumersTable t) => t.areaId.equals(areaId.value))
        ..orderBy(<OrderingTerm Function($CachedConsumersTable)>[
          ($CachedConsumersTable t) => OrderingTerm.asc(t.lastName),
          ($CachedConsumersTable t) => OrderingTerm.asc(t.firstName),
        ]);
      final rows = await query.get();
      return Ok<List<Consumer>>(
        rows.map(ConsumerDto.fromCacheRow).toList(),
      );
    } catch (error) {
      return Err<List<Consumer>>(ServerFailure(
        'Could not read the household list saved on this phone.',
        error.toString(),
      ));
    }
  }

  @override
  Future<Result<Consumer?>> byId(ConsumerId id) async {
    try {
      final query = _db.select(_db.cachedConsumers)
        ..where(($CachedConsumersTable t) => t.id.equals(id.value));
      final row = await query.getSingleOrNull();
      return Ok<Consumer?>(row == null ? null : ConsumerDto.fromCacheRow(row));
    } catch (error) {
      return Err<Consumer?>(ServerFailure(
        'Could not read that household from this phone.',
        error.toString(),
      ));
    }
  }

  @override
  Future<Result<Consumer?>> signedInConsumer() async {
    try {
      // No `.eq` filter, deliberately. `consumers_select_scoped` lets a
      // consumer see one row - theirs - so asking for "the row" is both the
      // simplest query and the correct one. Staff see their whole area, which
      // is why this returns null for them rather than an arbitrary household.
      final rows = await _client
          .from('consumers')
          .select(
            'id, consumer_no, first_name, last_name, contact_number, '
            'meter_serial_no, area_id, purok, account_status',
          )
          .limit(2);

      if (rows.length != 1) return const Ok<Consumer?>(null);

      return Ok<Consumer?>(_fromSupabaseRow(rows.first));
    } catch (error, stackTrace) {
      return Err<Consumer?>(FailureMapper.from(error, stackTrace));
    }
  }

  /// A consumers-table row has no reading joined onto it. New households and
  /// the signed-in household therefore start at zero rather than inventing a
  /// reading that the server did not return.
  static Consumer _fromSupabaseRow(Map<String, dynamic> row) => Consumer(
        id: ConsumerId(row['id'] as String),
        consumerNo: ConsumerNumber(row['consumer_no'] as String),
        firstName: row['first_name'] as String,
        lastName: row['last_name'] as String,
        contactNumber: row['contact_number'] as String?,
        meterSerialNo: row['meter_serial_no'] as String?,
        areaId: AreaId(row['area_id'] as String),
        purok: row['purok'] as String?,
        accountStatus: AccountStatus.fromCode(row['account_status'] as String),
        previousReading: Kwh.zero,
      );

  @override
  Future<Result<DateTime?>> lastRefreshedAt() async {
    try {
      final query = _db.select(_db.syncMeta)
        ..where(($SyncMetaTable t) => t.tableName_.equals(_syncKey));
      final row = await query.getSingleOrNull();
      final value = row?.lastRefreshedAt;
      return Ok<DateTime?>(value == null ? null : DateTime.parse(value).toUtc());
    } catch (error) {
      return Err<DateTime?>(ServerFailure(
        'Could not tell when this list was last updated.',
        error.toString(),
      ));
    }
  }

  @override
  Future<Result<void>> refreshAreaRoster(AreaId areaId) async {
    try {
      // MTR-02. Row-Level Security already restricts this to the reader's own
      // area; the filter is here so the query says what it means.
      final households = await _client
          .from('consumers')
          .select(
            'id, consumer_no, first_name, last_name, contact_number, '
            'meter_serial_no, area_id, purok, account_status',
          )
          .eq('area_id', areaId.value);

      // MTR-08: the previous reading has to be on the phone before the reader
      // walks out of signal, so it is denormalised onto each household.
      //
      // The cycle comes from the embedded billing_cycles row rather than
      // being derived from reading_date in Dart, because the server decides
      // which cycle a date belongs to (fn_ensure_billing_cycle) and the app
      // must not have a second opinion about it.
      final readings = await _client
          .from('meter_readings')
          .select(
            'consumer_id, current_reading, reading_date, '
            'billing_cycles(cycle_year, cycle_month)',
          )
          .order('reading_date', ascending: false);

      final latest = <String, Map<String, dynamic>>{};
      for (final row in readings) {
        final consumerId = row['consumer_id'] as String;
        // Sorted newest first, so the first one seen for a consumer wins.
        latest.putIfAbsent(consumerId, () => row);
      }

      await _db.transaction(() async {
        for (final household in households) {
          final id = household['id'] as String;
          final reading = latest[id];

          final Kwh previousReading = reading == null
              ? Kwh.zero
              : ConsumerDto.kwhFrom(reading['current_reading']);

          final cycle = reading?['billing_cycles'] as Map<String, dynamic>?;
          final String? lastReadCycle = cycle == null
              ? null
              : CycleLabel(
                  cycle['cycle_year'] as int,
                  cycle['cycle_month'] as int,
                ).value;

          await _db.into(_db.cachedConsumers).insertOnConflictUpdate(
                ConsumerDto.toCacheRow(
                  json: household,
                  previousReading: previousReading,
                  previousReadingDate: reading?['reading_date'] as String?,
                  lastReadCycle: lastReadCycle,
                ),
              );
        }

        // GEN-11: remember when, so every screen can say how fresh this is.
        final now = DateTime.now().toUtc().toIso8601String();
        await _db.into(_db.syncMeta).insertOnConflictUpdate(
              SyncMetaCompanion.insert(
                tableName_: _syncKey,
                lastRefreshedAt: Value<String?>(now),
                lastAttemptAt: Value<String?>(now),
                lastError: const Value<String?>(null),
              ),
            );
      });

      return const Ok<void>(null);
    } catch (error, stackTrace) {
      await _recordFailedAttempt(error);
      return Err<void>(FailureMapper.from(error, stackTrace));
    }
  }

  /// A failed refresh is remembered but does not empty the cache. The reader
  /// keeps yesterday's roster, which is worth far more than an empty screen.
  Future<void> _recordFailedAttempt(Object error) async {
    try {
      // lastRefreshedAt is deliberately left absent, not set to null: the
      // cache is still as fresh as it was, and the screen must keep saying so.
      await _db.into(_db.syncMeta).insertOnConflictUpdate(
            SyncMetaCompanion.insert(
              tableName_: _syncKey,
              lastAttemptAt:
                  Value<String?>(DateTime.now().toUtc().toIso8601String()),
              lastError: Value<String?>(error.toString()),
            ),
          );
    } catch (_) {
      // Recording why a refresh failed must never itself break the app.
    }
  }
}
