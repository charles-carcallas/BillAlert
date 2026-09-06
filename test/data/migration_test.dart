import 'dart:io';

import 'package:billalert/data/local/app_database.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

/// The v1 -> v2 upgrade, run against a real v1 database file.
///
/// The claim this file exists to check is not "the migration runs" but "the
/// migration does not throw away unsynced field work". A meter reader can
/// install an update halfway through a round with a morning of readings still
/// queued. Rebuilding the outbox table to add a CHECK constraint must not cost
/// them a single one of those, and `outbox_reading_keys` — which cascades from
/// outbox — must not be emptied when the old table is dropped.
///
/// v1 is written here by hand, as raw SQL, because that is what is actually on
/// a teammate's phone right now.
void main() {
  late Directory directory;
  late File file;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('billalert_migration');
    file = File('${directory.path}/cache.db');
  });

  tearDown(() => directory.deleteSync(recursive: true));

  /// Builds the schema as it stood at schemaVersion 1: same columns, but no
  /// CHECK constraints and none of the five indexes.
  void createVersion1WithQueuedWork() {
    final db = sqlite3.open(file.path);

    db.execute('''
      create table cache_owner (
        id integer not null,
        profile_id text not null,
        role text not null,
        area_id text null,
        cached_at text not null,
        primary key (id)
      );
    ''');

    db.execute('''
      create table outbox (
        client_uuid text not null,
        operation text not null,
        payload_json text not null,
        captured_at text not null,
        status text not null default 'pending',
        attempts integer not null default 0,
        last_error text null,
        server_id text null,
        created_at text not null,
        updated_at text null,
        primary key (client_uuid)
      );
    ''');

    db.execute('''
      create table outbox_reading_keys (
        client_uuid text not null references outbox (client_uuid) on delete cascade,
        consumer_id text not null,
        cycle_label text not null,
        primary key (client_uuid),
        unique (consumer_id, cycle_label)
      );
    ''');

    // The other cached tables are not touched by this migration, but they have
    // to exist or createAll would try to make them and the upgrade would not
    // be representative.
    db.execute('''
      create table cached_consumers (
        id text not null, consumer_no text not null, first_name text not null,
        last_name text not null, contact_number text null,
        meter_serial_no text null, area_id text not null, purok text null,
        account_status text not null,
        previous_reading_hundredths integer not null default 0,
        previous_reading_date text null, last_read_cycle text null,
        updated_at text null, primary key (id)
      );
    ''');
    db.execute('''
      create table cached_bills (
        id text not null, bill_no text not null, consumer_id text not null,
        cycle_label text not null, consumption_hundredths integer not null,
        amount_paid_centavos integer not null default 0,
        total_amount_centavos integer null, due_date text null,
        generated_at text null, primary key (id)
      );
    ''');
    db.execute('''
      create table cached_payments (
        id text not null, bill_id text null, receipt_no text not null,
        amount_paid_centavos integer not null, paid_at text not null,
        primary key (id)
      );
    ''');
    db.execute('''
      create table cached_notifications (
        id text not null, notif_type text not null, channel text not null,
        message text not null, status text not null,
        is_read integer not null default 0 check (is_read in (0, 1)),
        created_at text not null, primary key (id)
      );
    ''');
    db.execute('''
      create table sync_meta (
        table_name text not null, last_refreshed_at text null,
        last_attempt_at text null, last_error text null,
        primary key (table_name)
      );
    ''');

    // A morning in the field: two readings captured, neither synced.
    db.execute(
      'insert into cache_owner values '
      "(1, 'profile-ledesman', 'meter_reader', 'area-3', '2026-09-13T01:00:00.000Z');",
    );
    db.execute('''
      insert into outbox
        (client_uuid, operation, payload_json, captured_at, status, attempts,
         last_error, server_id, created_at, updated_at)
      values
        ('uuid-1', 'record_reading',
         '{"consumer_id":"consumer-1","current_reading":"1392.50","cycle_label":"2026-09"}',
         '2026-09-13T02:30:00.000Z', 'pending', 0, null, null,
         '2026-09-13T02:30:00.000Z', null),
        ('uuid-2', 'record_reading',
         '{"consumer_id":"consumer-2","current_reading":"880.00","cycle_label":"2026-09"}',
         '2026-09-13T03:15:00.000Z', 'failed', 2, 'No connection.', null,
         '2026-09-13T03:15:00.000Z', null);
    ''');
    db.execute('''
      insert into outbox_reading_keys values
        ('uuid-1', 'consumer-1', '2026-09'),
        ('uuid-2', 'consumer-2', '2026-09');
    ''');

    db.execute('pragma user_version = 1;');
    db.close();
  }

  Future<AppDatabase> openAndUpgrade() async {
    final db = AppDatabase.forTesting(
      NativeDatabase(
        file,
        // Mirrors _openEncrypted in app_database.dart. Without this the
        // cascade test below would pass for the wrong reason: with foreign
        // keys never armed, dropping the old outbox table could not have
        // taken outbox_reading_keys with it anyway, and the test would prove
        // nothing about the migration.
        setup: (db) => db.execute('pragma foreign_keys = on;'),
      ),
    );
    // Opening is lazy; any query forces the migration to run.
    await db.customSelect('select 1').get();
    return db;
  }

  test('the upgrade keeps every queued reading', () async {
    createVersion1WithQueuedWork();

    final db = await openAndUpgrade();
    addTearDown(db.close);

    final rows = await db
        .customSelect('select client_uuid, status, attempts, last_error, '
            'captured_at, payload_json from outbox order by captured_at')
        .get();

    expect(rows, hasLength(2), reason: 'unsynced field work was discarded');

    // Not just the row count — the fields the sync actually depends on.
    expect(rows[0].read<String>('client_uuid'), 'uuid-1');
    expect(rows[0].read<String>('captured_at'), '2026-09-13T02:30:00.000Z');
    expect(
      rows[0].read<String>('payload_json'),
      contains('1392.50'),
      reason: 'the reading itself must survive the rebuild',
    );

    // A failed item keeps its reason, so the reader can still see why.
    expect(rows[1].read<String>('status'), 'failed');
    expect(rows[1].read<int>('attempts'), 2);
    expect(rows[1].read<String>('last_error'), 'No connection.');
  });

  test('the cascade does not empty outbox_reading_keys during the rebuild',
      () async {
    createVersion1WithQueuedWork();

    final db = await openAndUpgrade();
    addTearDown(db.close);

    // outbox_reading_keys cascades from outbox. Dropping the old outbox table
    // with foreign keys armed would take these rows with it, and FR-23 would
    // stop catching duplicates for the rest of the round.
    final keys = await db
        .customSelect('select consumer_id, cycle_label from outbox_reading_keys '
            'order by consumer_id')
        .get();

    expect(keys, hasLength(2));
    expect(keys[0].read<String>('consumer_id'), 'consumer-1');
    expect(keys[0].read<String>('cycle_label'), '2026-09');
  });

  test('the cache owner survives, so the user is not silently logged out',
      () async {
    createVersion1WithQueuedWork();

    final db = await openAndUpgrade();
    addTearDown(db.close);

    final owner =
        await db.customSelect('select * from cache_owner').getSingle();
    expect(owner.read<String>('profile_id'), 'profile-ledesman');
    expect(owner.read<String>('role'), 'meter_reader');
  });

  test('the new constraints and indexes are in place afterwards', () async {
    createVersion1WithQueuedWork();

    final db = await openAndUpgrade();
    addTearDown(db.close);

    final outboxDdl = await db
        .customSelect(
          "select sql from sqlite_master where type = 'table' and name = 'outbox'",
        )
        .getSingle();
    expect(outboxDdl.read<String>('sql'), contains('CHECK("operation" IN'));

    final ownerDdl = await db
        .customSelect(
          "select sql from sqlite_master where type = 'table' "
          "and name = 'cache_owner'",
        )
        .getSingle();
    expect(ownerDdl.read<String>('sql'), contains('CHECK("id" = 1)'));

    final indexes = await db
        .customSelect("select name from sqlite_master where type = 'index'")
        .get();
    final names = indexes.map((QueryRow r) => r.read<String>('name')).toSet();
    expect(
      names,
      containsAll(<String>[
        'idx_cached_consumers_name',
        'idx_cached_consumers_area',
        'idx_cached_bills_consumer',
        'idx_cached_notif_unread',
        'idx_outbox_pending',
      ]),
    );
  });

  test('foreign keys are armed again once the migration is done', () async {
    createVersion1WithQueuedWork();

    final db = await openAndUpgrade();
    addTearDown(db.close);

    // alterTable disarms them to rebuild the table. If it left them off, the
    // ON DELETE CASCADE that keeps outbox_reading_keys tidy would be dead for
    // the rest of the session.
    final pragma =
        await db.customSelect('pragma foreign_keys').getSingle();
    expect(pragma.read<bool>('foreign_keys'), isTrue);
  });

  test('the upgraded database still refuses a bad operation code', () async {
    createVersion1WithQueuedWork();

    final db = await openAndUpgrade();
    addTearDown(db.close);

    await expectLater(
      db.customStatement(
        'insert into outbox (client_uuid, operation, payload_json, captured_at, '
        "status, attempts, created_at) values ('uuid-3', 'not_an_operation', "
        "'{}', '2026-09-13T04:00:00.000Z', 'pending', 0, "
        "'2026-09-13T04:00:00.000Z')",
      ),
      throwsA(isA<SqliteException>()),
    );
  });
}
