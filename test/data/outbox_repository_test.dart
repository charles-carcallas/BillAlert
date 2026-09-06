import 'package:billalert/core/errors/app_failure.dart';
import 'package:billalert/core/result/result.dart';
import 'package:billalert/data/local/app_database.dart';
import 'package:billalert/data/repositories/outbox_repository_impl.dart';
import 'package:billalert/data/repositories/reading_repository_impl.dart';
import 'package:billalert/domain/outbox/outbox_entry.dart';
import 'package:billalert/domain/outbox/outbox_operation.dart';
import 'package:billalert/domain/value_objects/cycle_label.dart';
import 'package:billalert/domain/value_objects/ids.dart';
import 'package:billalert/domain/value_objects/kwh.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// The outbox against a real SQLite database, not a fake.
///
/// The use-case tests prove the rules; this proves the storage underneath them
/// — that the generated Drift schema matches the tables the app expects, that
/// an operation survives being written down and read back, and above all that
/// FR-23's unique constraint is really there. That last one matters because
/// the friendly message in `RecordMeterReading` is only a courtesy: this
/// constraint is what actually makes a duplicate impossible.
void main() {
  late AppDatabase db;
  late OutboxRepositoryImpl outbox;
  late ReadingRepositoryImpl readings;

  const cycle = CycleLabel(2026, 9);
  final capturedAt = DateTime.utc(2026, 9, 13, 2, 30);

  RecordReadingOperation reading({
    String uuid = 'uuid-1',
    String consumerId = 'consumer-1',
    String value = '1392.50',
  }) =>
      RecordReadingOperation(
        clientUuid: ClientUuid(uuid),
        capturedAt: capturedAt,
        consumerId: ConsumerId(consumerId),
        currentReading: Kwh.parse(value),
        cycleLabel: cycle,
        consumerLabel: 'Elena Ravelo',
      );

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    outbox = OutboxRepositoryImpl(db);
    readings = ReadingRepositoryImpl(db);
  });

  tearDown(() => db.close());

  test('an enqueued reading comes back with every field intact', () async {
    expect(await outbox.enqueue(reading()), isA<Ok<void>>());

    final result = await outbox.pending();
    final entries = (result as Ok<List<OutboxEntry>>).value;
    expect(entries, hasLength(1));

    final operation = entries.single.operation;
    expect(operation, isA<RecordReadingOperation>());
    expect(operation.clientUuid, const ClientUuid('uuid-1'));
    // The capture time survives the round trip through SQLite. If it did not,
    // the server would attribute the reading to the wrong day.
    expect(operation.capturedAt, capturedAt);

    final decoded = operation as RecordReadingOperation;
    expect(decoded.currentReading, Kwh.parse('1392.50'));
    expect(decoded.cycleLabel, cycle);
    expect(entries.single.status, OutboxStatus.pending);
  });

  test('FR-23: a second reading for the same household and cycle is refused',
      () async {
    expect(await outbox.enqueue(reading()), isA<Ok<void>>());

    // Same household, same month, different client uuid — which is exactly
    // what a reader tapping save twice would produce.
    final second = await outbox.enqueue(reading(uuid: 'uuid-2'));

    expect(second, isA<Err<void>>());
    expect((second as Err<void>).failure, isA<ConflictFailure>());

    // And the first one is still there, untouched.
    final entries = (await outbox.pending() as Ok<List<OutboxEntry>>).value;
    expect(entries, hasLength(1));
    expect(entries.single.operation.clientUuid, const ClientUuid('uuid-1'));
  });

  test('the same household in a different cycle is allowed', () async {
    await outbox.enqueue(reading());

    final october = RecordReadingOperation(
      clientUuid: const ClientUuid('uuid-2'),
      capturedAt: DateTime.utc(2026, 10, 13),
      consumerId: const ConsumerId('consumer-1'),
      currentReading: Kwh.parse('1500.00'),
      cycleLabel: const CycleLabel(2026, 10),
      consumerLabel: 'Elena Ravelo',
    );

    expect(await outbox.enqueue(october), isA<Ok<void>>());
    expect(
      (await outbox.pending() as Ok<List<OutboxEntry>>).value,
      hasLength(2),
    );
  });

  test('a different household in the same cycle is allowed', () async {
    await outbox.enqueue(reading());
    expect(
      await outbox.enqueue(reading(uuid: 'uuid-2', consumerId: 'consumer-2')),
      isA<Ok<void>>(),
    );
  });

  test('the reading keys table answers the FR-23 question', () async {
    await outbox.enqueue(reading());

    final queued = await readings.isReadingQueuedFor(
      consumerId: const ConsumerId('consumer-1'),
      cycle: cycle,
    );
    expect((queued as Ok<bool>).value, isTrue);

    final other = await readings.isReadingQueuedFor(
      consumerId: const ConsumerId('consumer-2'),
      cycle: cycle,
    );
    expect((other as Ok<bool>).value, isFalse);

    final ids = await readings.queuedConsumerIdsFor(cycle);
    expect((ids as Ok<Set<ConsumerId>>).value,
        <ConsumerId>{const ConsumerId('consumer-1')});
  });

  test('a rejected item stays in the queue with its reason', () async {
    await outbox.enqueue(reading());
    await outbox.markSyncing(const ClientUuid('uuid-1'));
    await outbox.markFailed(
      const ClientUuid('uuid-1'),
      'That household has already been read for September 2026.',
    );

    // Still there. A refused item is never silently dropped: the reader has
    // to be able to see what did not go through, and why.
    final entries = (await outbox.all() as Ok<List<OutboxEntry>>).value;
    expect(entries, hasLength(1));
    expect(entries.single.status, OutboxStatus.failed);
    expect(entries.single.attempts, 1);
    expect(entries.single.lastError, contains('already been read'));

    // And it is still offered to the next sync attempt.
    expect((await outbox.pending() as Ok<List<OutboxEntry>>).value, hasLength(1));
  });

  test('a synced item leaves the pending queue but keeps its server id',
      () async {
    await outbox.enqueue(reading());
    await outbox.markSynced(const ClientUuid('uuid-1'), 'bill-uuid-from-server');

    expect((await outbox.pending() as Ok<List<OutboxEntry>>).value, isEmpty);

    final all = (await outbox.all() as Ok<List<OutboxEntry>>).value;
    expect(all.single.status, OutboxStatus.synced);
    expect(all.single.serverId, 'bill-uuid-from-server');
  });

  test('the queue drains oldest capture first', () async {
    final later = RecordReadingOperation(
      clientUuid: const ClientUuid('uuid-later'),
      capturedAt: DateTime.utc(2026, 9, 13, 8),
      consumerId: const ConsumerId('consumer-2'),
      currentReading: Kwh.parse('900.00'),
      cycleLabel: cycle,
      consumerLabel: 'Second House',
    );

    // Enqueued out of order on purpose.
    await outbox.enqueue(later);
    await outbox.enqueue(reading());

    final entries = (await outbox.pending() as Ok<List<OutboxEntry>>).value;
    expect(entries.first.operation.clientUuid, const ClientUuid('uuid-1'));
    expect(entries.last.operation.clientUuid, const ClientUuid('uuid-later'));
  });

  test('clearing the cache on sign-out leaves the outbox alone', () async {
    await outbox.enqueue(reading());

    // GEN-06 empties the cached data. It must not throw away field work that
    // has not synced.
    await db.clearCachedData();

    expect((await outbox.pending() as Ok<List<OutboxEntry>>).value, hasLength(1));
  });
}
