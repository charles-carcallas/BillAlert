import 'package:drift/drift.dart';
import 'package:sqlite3/common.dart';

import '../../core/errors/app_failure.dart';
import '../../core/result/result.dart';
import '../../domain/outbox/outbox_entry.dart';
import '../../domain/outbox/outbox_operation.dart';
import '../../domain/repositories/outbox_repository.dart';
import '../../domain/value_objects/ids.dart';
import '../../domain/value_objects/ph_date.dart';
import '../local/app_database.dart';
import '../sync/outbox_codec.dart';
import '../sync/outbox_session.dart';

/// The outbox, stored in the encrypted database.
///
/// [enqueue] is the whole offline story in one method: it writes the
/// operation to disk inside a transaction and returns. Nothing waits for the
/// network, and the screen confirms from this write. If Android kills the
/// process on the next line, the reading is still there.
class OutboxRepositoryImpl implements OutboxRepository {
  final AppDatabase _db;

  final OutboxSession session;
  @override
  int get sessionGeneration => session.generation;
  const OutboxRepositoryImpl(this._db, {required this.session});

  Expression<bool> _owned($OutboxRowsTable t) {
    final scope = session.scope;
    if (scope == null) return const Constant(false);
    return t.ownerId.equals(scope.id) &
        t.ownerRole.equals(scope.role) &
        (scope.area == null
            ? t.ownerArea.isNull()
            : t.ownerArea.equals(scope.area!));
  }

  @override
  Future<Result<void>> reviseRejectedDueDate(
    ClientUuid uuid,
    PhDate dueDate,
  ) async {
    try {
      return await _db.transaction(() async {
        final row =
            await (_db.select(_db.outboxRows)
                  ..where((t) => _owned(t) & t.clientUuid.equals(uuid.value)))
                .getSingleOrNull();
        final op = row == null ? null : _toEntry(row)?.operation;
        final error = row?.lastError?.toLowerCase() ?? '';
        if (row?.status != 'failed' ||
            op is! PostAmountOperation ||
            row?.serverId != null ||
            !error.contains('due date') ||
            !(error.contains('past') || error.contains('passed'))) {
          return const Err<void>(
            ConflictFailure(
              'This item needs receipt or server verification before it can be changed.',
            ),
          );
        }
        final revised = PostAmountOperation(
          clientUuid: op.clientUuid,
          capturedAt: op.capturedAt,
          billId: op.billId,
          amount: op.amount,
          cooperativeAmount: op.cooperativeAmount,
          dueDate: dueDate,
          billLabel: op.billLabel,
        );
        await (_db.update(
          _db.outboxRows,
        )..where((t) => t.clientUuid.equals(uuid.value) & _owned(t))).write(
          OutboxRowsCompanion(
            payloadJson: Value(OutboxCodec.encode(revised)),
            status: const Value('pending'),
            lastError: const Value(null),
          ),
        );
        return const Ok<void>(null);
      });
    } catch (error) {
      return Err(ServerFailure('Could not save the corrected date.', '$error'));
    }
  }

  @override
  Future<Result<int>> quarantinedCount() async {
    try {
      final rows =
          await (_db.select(_db.outboxRows)..where(
                (t) => t.ownerId.isNull() & t.status.isNotValue('synced'),
              ))
              .get();
      return Ok(rows.length);
    } catch (error) {
      return Err(ServerFailure('Could not check older saved work.', '$error'));
    }
  }

  @override
  Future<Result<void>> enqueue(OutboxOperation operation) async {
    final scope = session.scope;
    if (scope == null) {
      return const Err<void>(AuthFailure('Sign in before saving work.'));
    }
    try {
      await _db.transaction(() async {
        if (operation is RecordPaymentOperation ||
            operation is PostAmountOperation ||
            operation is IssueNoticeOperation) {
          final rows = await (_db.select(
            _db.outboxRows,
          )..where((t) => _owned(t) & t.status.isNotValue('synced'))).get();
          for (final row in rows) {
            final existing = _toEntry(row)?.operation;
            final duplicate = switch ((operation, existing)) {
              (
                final RecordPaymentOperation next,
                final RecordPaymentOperation old,
              ) =>
                next.billIds.any(old.billIds.contains),
              (final PostAmountOperation next, final PostAmountOperation old) =>
                next.billId == old.billId,
              (
                final IssueNoticeOperation next,
                final IssueNoticeOperation old,
              ) =>
                next.consumerId == old.consumerId,
              _ => false,
            };
            if (duplicate) {
              throw const ConflictFailure(
                'Work for this bill or household is already saved. Check its sync status before recording it again.',
              );
            }
          }
        }
        final now = DateTime.now().toUtc().toIso8601String();

        await _db
            .into(_db.outboxRows)
            .insert(
              OutboxRowsCompanion.insert(
                ownerId: Value(scope.id),
                ownerRole: Value(scope.role),
                ownerArea: Value(scope.area),
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
          // A reading already synced for this household and month is the
          // server's to guard from here on. Its key is dropped so that a
          // reading deleted on the server can be taken again; an unsent one
          // keeps its key and still refuses the duplicate below.
          await _db.customStatement(
            'delete from outbox_reading_keys '
            'where consumer_id = ? and cycle_label = ? '
            'and client_uuid in (select client_uuid from outbox '
            "where status = 'synced')",
            <Object?>[operation.consumerId.value, operation.cycleLabel.value],
          );
          await _db
              .into(_db.outboxReadingKeys)
              .insert(
                OutboxReadingKeysCompanion.insert(
                  clientUuid: operation.clientUuid.value,
                  consumerId: operation.consumerId.value,
                  cycleLabel: operation.cycleLabel.value,
                ),
              );
        }
      });
      return const Ok<void>(null);
    } on AppFailure catch (failure) {
      return Err<void>(failure);
    } on SqliteException catch (error) {
      // 2067 / 1555 are SQLITE_CONSTRAINT_UNIQUE and _PRIMARYKEY.
      if (error.extendedResultCode == 2067 ||
          error.extendedResultCode == 1555) {
        return Err<void>(
          ConflictFailure(
            'A reading for this household and month is already waiting to '
            'sync on this phone.',
            error.toString(),
          ),
        );
      }
      return Err<void>(
        ServerFailure(
          'Could not save to this phone. Please close the app and open it '
          'again.',
          error.toString(),
        ),
      );
    } catch (error) {
      return Err<void>(
        ServerFailure(
          'Could not save to this phone. Please close the app and open it '
          'again.',
          error.toString(),
        ),
      );
    }
  }

  @override
  Future<Result<List<OutboxEntry>>> pending() async {
    final query = _db.select(_db.outboxRows)
      // 'syncing' too. Only one drain runs at a time and it reads this list
      // first, so a row still marked 'syncing' here was cut off by the app
      // being killed mid-send. Sending it again is safe: every operation
      // carries the same client_uuid, and the server returns the first
      // result instead of doing the work twice.
      ..where(
        ($OutboxRowsTable t) =>
            _owned(t) & t.status.isIn(<String>['pending', 'failed', 'syncing']),
      )
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
      ..where(_owned)
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
      return Err<List<OutboxEntry>>(
        ServerFailure(
          'Could not read the list of items waiting to sync.',
          error.toString(),
        ),
      );
    }
  }

  @override
  Stream<List<OutboxEntry>> watchAll() {
    final query = _db.select(_db.outboxRows)
      ..where(_owned)
      ..orderBy(<OrderingTerm Function($OutboxRowsTable)>[
        ($OutboxRowsTable t) => OrderingTerm.asc(t.capturedAt),
      ]);
    return query.watch().map(
      (List<OutboxRow> rows) => rows.map(_toEntry).nonNulls.toList(),
    );
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
        ..where(
          ($OutboxRowsTable t) =>
              t.clientUuid.equals(clientUuid.value) & _owned(t),
        );

      final changed = await statement.write(
        OutboxRowsCompanion(
          status: Value<String>(status),
          serverId: serverId == null
              ? const Value<String?>.absent()
              : Value<String?>(serverId),
          lastError: Value<String?>(lastError),
          updatedAt: Value<String?>(DateTime.now().toUtc().toIso8601String()),
        ),
      );
      if (changed != 1) {
        return const Err<void>(
          AuthFailure('This queued item belongs to another session.'),
        );
      }
      if (status == 'synced') {
        final row = await (_db.select(
          _db.outboxRows,
        )..where((t) => t.clientUuid.equals(clientUuid.value))).getSingle();
        final operation = _toEntry(row)?.operation;
        if (operation is RecordReadingOperation) {
          await (_db.update(_db.cachedConsumers)..where(
                (t) =>
                    t.id.equals(operation.consumerId.value) &
                    (t.lastReadCycle.isNull() |
                        t.lastReadCycle.isSmallerOrEqualValue(
                          operation.cycleLabel.value,
                        )),
              ))
              .write(
                CachedConsumersCompanion(
                  lastReadCycle: Value(operation.cycleLabel.value),
                ),
              );
        }
      }
      if (status == 'syncing') {
        await _db.customStatement(
          'update outbox set attempts = attempts + 1 where client_uuid = ?',
          <Object?>[clientUuid.value],
        );
      }
      return const Ok<void>(null);
    } catch (error) {
      return Err<void>(
        ServerFailure(
          'Could not update the sync queue on this phone.',
          error.toString(),
        ),
      );
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
