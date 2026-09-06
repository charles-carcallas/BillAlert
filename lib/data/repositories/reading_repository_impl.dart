import 'package:drift/drift.dart';

import '../../core/errors/app_failure.dart';
import '../../core/result/result.dart';
import '../../domain/repositories/reading_repository.dart';
import '../../domain/value_objects/cycle_label.dart';
import '../../domain/value_objects/ids.dart';
import '../local/app_database.dart';

/// FR-23, answered from the device.
///
/// Reads `outbox_reading_keys`, which is the table whose UNIQUE constraint
/// makes a duplicate impossible in the first place. Asking it before the
/// reader types anything is what turns a sync-time rejection into a message
/// at the meter.
class ReadingRepositoryImpl implements ReadingRepository {
  final AppDatabase _db;

  const ReadingRepositoryImpl(this._db);

  @override
  Future<Result<Set<ConsumerId>>> queuedConsumerIdsFor(CycleLabel cycle) async {
    try {
      final query = _db.select(_db.outboxReadingKeys)
        ..where(($OutboxReadingKeysTable t) => t.cycleLabel.equals(cycle.value));
      final rows = await query.get();
      return Ok<Set<ConsumerId>>(
        rows
            .map((OutboxReadingKeyRow r) => ConsumerId(r.consumerId))
            .toSet(),
      );
    } catch (error) {
      return Err<Set<ConsumerId>>(ServerFailure(
        'Could not check which households are already recorded on this phone.',
        error.toString(),
      ));
    }
  }

  @override
  Future<Result<bool>> isReadingQueuedFor({
    required ConsumerId consumerId,
    required CycleLabel cycle,
  }) async {
    try {
      final query = _db.select(_db.outboxReadingKeys)
        ..where(($OutboxReadingKeysTable t) =>
            t.consumerId.equals(consumerId.value) &
            t.cycleLabel.equals(cycle.value));
      final row = await query.getSingleOrNull();
      return Ok<bool>(row != null);
    } catch (error) {
      return Err<bool>(ServerFailure(
        'Could not check whether this household is already recorded.',
        error.toString(),
      ));
    }
  }
}
