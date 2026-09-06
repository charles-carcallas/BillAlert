import 'package:billalert/data/local/app_database.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// What the database actually is, read back from `sqlite_master`.
///
/// These assertions deliberately query the live schema rather than reading the
/// Dart source or the generated file. A `.check()` in `tables.dart` compiles to
/// a callback that drift turns into SQL at table-creation time, so the only way
/// to know a constraint reached the database is to ask the database.
///
/// The last test is the one that matters most: a constraint nobody has watched
/// fail is not yet a constraint.
void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  /// The `CREATE TABLE` statement SQLite is actually holding.
  Future<String> ddlFor(String table) async {
    final row = await db
        .customSelect(
          'select sql from sqlite_master where type = ? and name = ?',
          variables: <Variable<Object>>[
            const Variable<String>('table'),
            Variable<String>(table),
          ],
        )
        .getSingle();
    return row.read<String>('sql');
  }

  group('CHECK constraints reached the database', () {
    test('cache_owner is a single-row table', () async {
      final ddl = await ddlFor('cache_owner');
      expect(ddl, contains('CHECK("id" = 1)'));
    });

    test('cache_owner.role is one of the four roles', () async {
      final ddl = await ddlFor('cache_owner');
      expect(ddl, contains('admin'));
      expect(ddl, contains('meter_reader'));
      expect(ddl, contains('cashier'));
      expect(ddl, contains('consumer'));
      expect(ddl, contains('CHECK("role" IN'));
    });

    test('outbox.operation is one of the seven operation codes', () async {
      final ddl = await ddlFor('outbox');
      expect(ddl, contains('CHECK("operation" IN'));
      for (final String code in <String>[
        'record_reading',
        'create_consumer',
        'update_consumer',
        'issue_notice',
        'record_payment',
        'post_amount',
        'close_notice',
      ]) {
        expect(ddl, contains("'$code'"), reason: '$code missing from the CHECK');
      }
    });

    test('outbox.status is one of the four sync states', () async {
      final ddl = await ddlFor('outbox');
      expect(ddl, contains('CHECK("status" IN'));
      for (final String state in <String>[
        'pending',
        'syncing',
        'failed',
        'synced',
      ]) {
        expect(ddl, contains("'$state'"));
      }
    });
  });

  group('indexes reached the database', () {
    test('all five exist', () async {
      final rows = await db
          .customSelect(
            'select name from sqlite_master where type = ? order by name',
            variables: <Variable<Object>>[const Variable<String>('index')],
          )
          .get();
      final names = rows.map((QueryRow r) => r.read<String>('name')).toSet();

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

    test('idx_outbox_pending covers the filter and sort the sync drain uses',
        () async {
      final row = await db
          .customSelect(
            'select sql from sqlite_master where name = ?',
            variables: <Variable<Object>>[
              const Variable<String>('idx_outbox_pending'),
            ],
          )
          .getSingle();

      // OutboxRepositoryImpl.pending() filters on status and orders by
      // captured_at, so both columns have to be in the index, in that order.
      expect(row.read<String>('sql'), contains('(status, captured_at)'));
    });
  });

  group('the operation CHECK actually rejects a bad code', () {
    /// Goes around Drift and inserts raw, which is exactly the situation the
    /// constraint is defending against: a code that no OutboxOperation
    /// subclass produces, arriving from a typo or a future refactor.
    Future<void> insertOperation(String code) {
      return db.customStatement(
        'insert into outbox (client_uuid, operation, payload_json, '
        'captured_at, status, attempts, created_at) '
        'values (?, ?, ?, ?, ?, ?, ?)',
        <Object?>[
          'uuid-$code',
          code,
          '{}',
          '2026-09-13T02:30:00.000Z',
          'pending',
          0,
          '2026-09-13T02:30:00.000Z',
        ],
      );
    }

    test('a recognised code is accepted', () async {
      await insertOperation('record_reading');

      final count = await db
          .customSelect('select count(*) as c from outbox')
          .getSingle();
      expect(count.read<int>('c'), 1);
    });

    test('an unrecognised code is refused at insert, not later at decode',
        () async {
      await expectLater(
        insertOperation('recrd_reading'), // one letter short
        throwsA(isA<SqliteException>()),
      );

      // And nothing was written. Without the constraint this row would sit in
      // the table until OutboxCodec failed to decode it, long after the line
      // that caused it.
      final count = await db
          .customSelect('select count(*) as c from outbox')
          .getSingle();
      expect(count.read<int>('c'), 0);
    });

    test('an unrecognised status is refused too', () async {
      await expectLater(
        db.customStatement(
          'insert into outbox (client_uuid, operation, payload_json, '
          'captured_at, status, attempts, created_at) '
          'values (?, ?, ?, ?, ?, ?, ?)',
          <Object?>[
            'uuid-bad-status',
            'record_reading',
            '{}',
            '2026-09-13T02:30:00.000Z',
            'uploading', // not one of the four
            0,
            '2026-09-13T02:30:00.000Z',
          ],
        ),
        throwsA(isA<SqliteException>()),
      );
    });

    test('a second cache_owner row is refused', () async {
      await db.customStatement(
        'insert into cache_owner (id, profile_id, role, cached_at) '
        "values (1, 'profile-1', 'meter_reader', '2026-09-13T02:30:00.000Z')",
      );

      await expectLater(
        db.customStatement(
          'insert into cache_owner (id, profile_id, role, cached_at) '
          "values (2, 'profile-2', 'cashier', '2026-09-13T02:30:00.000Z')",
        ),
        throwsA(isA<SqliteException>()),
      );
    });

    test('an unrecognised role is refused', () async {
      await expectLater(
        db.customStatement(
          'insert into cache_owner (id, profile_id, role, cached_at) '
          "values (1, 'profile-1', 'superuser', '2026-09-13T02:30:00.000Z')",
        ),
        throwsA(isA<SqliteException>()),
      );
    });
  });
}
