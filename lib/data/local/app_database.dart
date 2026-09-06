import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'database_key.dart';
import 'tables.dart';

part 'app_database.g.dart';

/// The encrypted on-device database: the cache the app reads when there is no
/// signal, and the outbox of work that has not reached the server.
@DriftDatabase(
  tables: <Type>[
    CachedConsumers,
    CachedBills,
    CachedPayments,
    CachedNotifications,
    CacheOwner,
    SyncMeta,
    OutboxRows,
    OutboxReadingKeys,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openEncrypted());

  /// An unencrypted in-memory database, for tests. SQLCipher is still the
  /// engine; there is simply no key and no file.
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 2;

  /// v1 -> v2: the CHECK constraints and the five indexes that the retired
  /// `local_cache_schema.sql` had and this port had lost.
  ///
  /// **Nothing is dropped.** Teammates already have a v1 database on their
  /// phones, and a meter reader could upgrade mid-round with a morning of
  /// unsynced readings in the outbox. Discarding that would be the exact
  /// failure the outbox exists to prevent.
  ///
  /// SQLite has no `ALTER TABLE ADD CONSTRAINT`, so the two tables that gain
  /// CHECKs have to be rebuilt. [Migrator.alterTable] runs SQLite's twelve-step
  /// procedure: it turns foreign keys off, creates the new table, copies every
  /// existing row into it, drops the old one, renames, re-creates any indexes
  /// that belonged to it, and turns foreign keys back on. Two things follow
  /// from that, and both matter here:
  ///
  /// - Every outbox row survives, with its client_uuid, captured_at and
  ///   payload intact — so a queued reading still syncs after the upgrade.
  /// - `outbox_reading_keys` keeps its rows. Its `ON DELETE CASCADE` would
  ///   otherwise wipe them when the old `outbox` table is dropped; disarming
  ///   foreign keys for the rebuild is what prevents that. No row is orphaned,
  ///   because every parent row is copied across.
  ///
  /// The rebuild fails, and the app refuses to open, if any existing row
  /// violates a new constraint. That cannot happen from data this app wrote:
  /// `operation` only ever comes from an OutboxOperation subclass and `status`
  /// only from the four values in OutboxStatus.
  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) => m.createAll(),
        onUpgrade: (Migrator m, int from, int to) async {
          if (from < 2) {
            await m.alterTable(TableMigration(cacheOwner));
            await m.alterTable(TableMigration(outboxRows));

            await m.createIndex(idxCachedConsumersName);
            await m.createIndex(idxCachedConsumersArea);
            await m.createIndex(idxCachedBillsConsumer);
            await m.createIndex(idxCachedNotifUnread);
            await m.createIndex(idxOutboxPending);
          }
        },
      );

  /// GEN-06: what signing out destroys.
  ///
  /// The outbox is deliberately not in this list. Signing out with unsynced
  /// field work would throw away a morning of readings, so the screen warns
  /// and asks first, and only then calls [clearOutbox].
  Future<void> clearCachedData() async {
    await transaction(() async {
      await delete(cachedConsumers).go();
      await delete(cachedBills).go();
      await delete(cachedPayments).go();
      await delete(cachedNotifications).go();
      await delete(cacheOwner).go();
      await delete(syncMeta).go();
    });
  }

  /// Only ever called after the user has confirmed they accept losing
  /// whatever is still queued.
  Future<void> clearOutbox() async {
    await transaction(() async {
      await delete(outboxReadingKeys).go();
      await delete(outboxRows).go();
    });
  }
}

/// Opens the database file through SQLCipher.
///
/// `PRAGMA key` has to be the first statement executed on the connection,
/// which is exactly what drift's `setup` callback is for. The SQLCipher build
/// itself is selected in pubspec.yaml under `hooks: user_defines: sqlite3:
/// source: sqlcipher`, so no separate native package is involved.
///
/// This runs on the same isolate as the UI rather than through
/// `createInBackground`. For a roster of a few hundred households the
/// difference is not measurable, and a single isolate is far easier to reason
/// about. If a screen ever does start to stutter, that is the thing to
/// change, and it is a change in this one function.
QueryExecutor _openEncrypted() {
  return LazyDatabase(() async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File(p.join(directory.path, 'billalert_cache.db'));
    final key = await DatabaseKey.readOrCreate();

    return NativeDatabase(
      file,
      setup: (db) {
        // A PRAGMA cannot take a bound parameter, so the key is interpolated.
        // It is generated by us and base64, but the quotes are doubled anyway
        // rather than relying on that.
        final escaped = key.replaceAll("'", "''");
        db.execute("pragma key = '$escaped';");
        db.execute('pragma foreign_keys = on;');
      },
    );
  });
}
