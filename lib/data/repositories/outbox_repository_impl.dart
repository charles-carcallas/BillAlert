import 'package:drift/drift.dart';
import 'package:sqlite3/common.dart';

import '../../core/errors/app_failure.dart';
import '../../core/result/result.dart';
import '../../domain/outbox/outbox_entry.dart';
import '../../domain/outbox/outbox_operation.dart';
import '../../domain/repositories/outbox_repository.dart';
import '../../domain/value_objects/ids.dart';
import '../local/app_database.dart';
import '../sync/outbox_codec.dart';

/// The outbox, stored in the encrypted database.
///
/// [enqueue] is the whole offline story in one method: it writes the
/// operation to disk inside a transaction and returns. Nothing waits for the
/// network, and the screen confirms from this write. If Android kills the
/// process on the next line, the reading is still there.
class OutboxRepositoryImpl implements OutboxRepository {
  final AppDatabase _db;

  const OutboxRepositoryImpl(this._db);

  @override
  Future<Result<void>> enqueue(OutboxOperation operation) async {
    try {
      await _db.transaction(() async {
        final now = DateTime.now().toUtc().toIso8601String();

        await _db.into(_db.outboxRows).insert(
              OutboxRowsCompanion.insert(
                clientUuid: operation.clientUuid.value,
                operation: operation.operationCode,
                payloadJson: OutboxCodec.encode(operation),
                capturedAt: operation.capturedAt.toIso8601String(),
                createdAt: now,
                updatedAt: Value<String?>(now),
              ),
            );

        // FR-23: the second half of the duplicate guard. The UNIQUE
        // (consumer_id, cycle_label) constraint on this table is what makes
        // a second queued reading for the same house and month impossible.
        // The use case checks first and gives a friendly message; this is
        // the constraint that actually enforces it.
        if (operation is RecordReadingOperation) {
          await _db.into(_db.outboxReadingKeys).insert(
                OutboxReadingKeysCompanion.insert(
                  clientUuid: operation.clientUuid.value,
                  consumerId: operation.consumerId.value,
                  cycleLabel: operation.cycleLabel.value,
                ),
              );
        }
      });
      return const Ok<void>(null);
    } on SqliteException catch (error) {
      // 2067 / 1555 are SQLITE_CONSTRAINT_UNIQUE and _PRIMARYKEY.
      if (error.extendedResultCode == 2067 ||
          error.extendedResultCode == 1555) {
        return Err<void>(ConflictFailure(
          'A reading for this household and month is already waiting to '
          'sync on this phone.',
          error.toString(),
        ));
      }
      return Err<void>(ServerFailure(
        'Could not save to this phone. Please close the app and open it '
        'again.',
        error.toString(),
      ));
    } catch (error) {
      return Err<void>(ServerFailure(
        'Could not save to this phone. Please close the app and open it '
        'again.',
        error.toString(),
      ));
    }
  }

  @override
  Future<Result<List<OutboxEntry>>> pending() async {
    final query = _db.select(_db.outboxRows)
      ..where(($OutboxRowsTable t) => t.status.isIn(<String>['pending', 'failed']))
      // Oldest capture first, so the queue drains in the order the work was
      // actually done.
      ..orderBy(<OrderingTerm Function($OutboxRowsTable)>[
        ($OutboxRowsTable t) => OrderingTerm.asc(t.capturedAt),
      ]);
    return _read(query);
  }

  @override
  Future<Result<List<OutboxEntry>>> all() async {
    final query = _db.select(_db.outboxRows)
      ..orderBy(<OrderingTerm Function($OutboxRowsTable)>[
        ($OutboxRowsTable t) => OrderingTerm.asc(t.capturedAt),
      ]);
    return _read(query);
  }

  Future<Result<List<OutboxEntry>>> _read(
    SimpleSelectStatement<$OutboxRowsTable, OutboxRow> query,
  ) async {
    try {
      final rows = await query.get();
      return Ok<List<OutboxEntry>>(rows.map(_toEntry).nonNulls.toList());
    } catch (error) {
      return Err<List<OutboxEntry>>(ServerFailure(
        'Could not read the list of items waiting to sync.',
        error.toString(),
      ));
    }
  }

  @override
  Stream<List<OutboxEntry>> watchAll() {
    final query = _db.select(_db.outboxRows)
      ..orderBy(<OrderingTerm Function($OutboxRowsTable)>[
        ($OutboxRowsTable t) => OrderingTerm.asc(t.capturedAt),
      ]);
    return query
        .watch()
        .map((List<OutboxRow> rows) => rows.map(_toEntry).nonNulls.toList());
  }

  @override
  Future<Result<void>> markSyncing(ClientUuid clientUuid) =>
      _updateStatus(clientUuid, status: 'syncing');

  @override
  Future<Result<void>> markSynced(ClientUuid clientUuid, String serverId) =>
      _updateStatus(clientUuid, status: 'synced', serverId: serverId);

  @override
  Future<Result<void>> markFailed(ClientUuid clientUuid, String reason) =>
      _updateStatus(clientUuid, status: 'failed', lastError: reason);

  /// A failed item keeps its row, its reason and its place in the queue. It
  /// is never deleted: the user has to be able to see what did not go
  /// through, and fix it.
  Future<Result<void>> _updateStatus(
    ClientUuid clientUuid, {
    required String status,
    String? serverId,
    String? lastError,
  }) async {
    try {
      final statement = _db.update(_db.outboxRows)
        ..where(($OutboxRowsTable t) => t.clientUuid.equals(clientUuid.value));

      await statement.write(
        OutboxRowsCompanion(
          status: Value<String>(status),
          serverId: serverId == null
              ? const Value<String?>.absent()
              : Value<String?>(serverId),
          lastError: Value<String?>(lastError),
          updatedAt: Value<String?>(DateTime.now().toUtc().toIso8601String()),
        ),
      );
      if (status == 'syncing') {
        await _db.customStatement(
          'update outbox set attempts = attempts + 1 where client_uuid = ?',
          <Object?>[clientUuid.value],
        );
      }
      return const Ok<void>(null);
    } catch (error) {
      return Err<void>(ServerFailure(
        'Could not update the sync queue on this phone.',
        error.toString(),
      ));
    }
  }

  /// Null when the row holds an operation code this app version cannot
  /// rebuild. Filtered out by `nonNulls` rather than crashing the list.
  OutboxEntry? _toEntry(OutboxRow row) {
    final operation = OutboxCodec.decode(
      operationCode: row.operation,
      payloadJson: row.payloadJson,
      clientUuid: row.clientUuid,
      capturedAt: row.capturedAt,
    );
    if (operation == null) return null;

    return OutboxEntry(
      operation: operation,
      status: OutboxStatus.fromCode(row.status),
      attempts: row.attempts,
      lastError: row.lastError,
      serverId: row.serverId,
      createdAt: DateTime.parse(row.createdAt).toUtc(),
    );
  }
}
