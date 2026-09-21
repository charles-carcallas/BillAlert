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

  /// Only readings not yet on the server. A key stays behind after its
  /// reading syncs, and counting it kept a synced reading "waiting to sync"
  /// forever, and blocked a new reading after the server's was deleted. Once
  /// synced, the server's own duplicate check is the one that applies.
  static const String _unsent = '''
    select k.consumer_id
      from outbox_reading_keys k
      join outbox o on o.client_uuid = k.client_uuid
     where k.cycle_label = ?
       and o.status <> 'synced'
  ''';

  @override
  Future<Result<Set<ConsumerId>>> queuedConsumerIdsFor(CycleLabel cycle) async {
    try {
      final rows = await _db
          .customSelect(
            _unsent,
            variables: <Variable<Object>>[Variable<String>(cycle.value)],
            readsFrom: <ResultSetImplementation<dynamic, dynamic>>{
              _db.outboxReadingKeys,
              _db.outboxRows,
            },
          )
          .get();
      return Ok<Set<ConsumerId>>(
        rows
            .map((QueryRow r) => ConsumerId(r.read<String>('consumer_id')))
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
      final rows = await _db
          .customSelect(
            '$_unsent and k.consumer_id = ?',
            variables: <Variable<Object>>[
              Variable<String>(cycle.value),
              Variable<String>(consumerId.value),
            ],
            readsFrom: <ResultSetImplementation<dynamic, dynamic>>{
              _db.outboxReadingKeys,
              _db.outboxRows,
            },
          )
          .get();
      return Ok<bool>(rows.isNotEmpty);
    } catch (error) {
      return Err<bool>(ServerFailure(
        'Could not check whether this household is already recorded.',
        error.toString(),
      ));
    }
  }
}
