import 'package:drift/drift.dart';

import 'connection/open_connection.dart';
import 'tables.dart';

part 'app_database.g.dart';

/// The on-device database: the cache the app reads when there is no signal,
/// and the outbox of work that has not reached the server.
///
/// Where it lives and whether it is encrypted depends on the platform, and
/// `connection/open_connection.dart` decides. On Android it is a SQLCipher
/// file keyed from the Keystore. On the web it is SQLite compiled to
/// WebAssembly and **not encrypted** — see `connection/web_connection.dart`
/// for why that cannot honestly be fixed, and check `databaseIsEncrypted`
/// rather than assuming.
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
  AppDatabase() : super(openBillAlertDatabase());

  /// An unencrypted in-memory database, for tests. SQLCipher is still the
  /// engine; there is simply no key and no file.
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 5;

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
        // alterTable uses the current (v3) table definition. Add the v3
        // identity columns to a v1 table first so its copy step has real
        // source columns instead of trying to select columns that do not
        // exist yet.
        await m.addColumn(cacheOwner, cacheOwner.username);
        await m.addColumn(cacheOwner, cacheOwner.firstName);
        await m.addColumn(cacheOwner, cacheOwner.lastName);
        await m.addColumn(cacheOwner, cacheOwner.mustChangePassword);

        await m.alterTable(TableMigration(cacheOwner));
        await m.alterTable(TableMigration(outboxRows));

        await m.createIndex(idxCachedConsumersName);
        await m.createIndex(idxCachedConsumersArea);
        await m.createIndex(idxCachedBillsConsumer);
        await m.createIndex(idxCachedNotifUnread);
        await m.createIndex(idxOutboxPending);
      }
      if (from >= 2 && from < 3) {
        // An existing Supabase session must be usable without signal.
        // These are nullable so an upgrade never invents identity data;
        // the next successful online profile load fills them in.
        await m.addColumn(cacheOwner, cacheOwner.username);
        await m.addColumn(cacheOwner, cacheOwner.firstName);
        await m.addColumn(cacheOwner, cacheOwner.lastName);
        await m.addColumn(cacheOwner, cacheOwner.mustChangePassword);
      }
      if (from < 4) {
        // The first payment/notification cache tables were only skeletal and
        // were never populated. Add the facts required to reconstruct the
        // Consumer History, receipt and Inbox screens after a process kill.
        // All are nullable so an upgrade preserves any legacy cache rows
        // without inventing receipt or ownership data.
        await m.addColumn(cachedPayments, cachedPayments.consumerId);
        await m.addColumn(cachedPayments, cachedPayments.billNo);
        await m.addColumn(cachedPayments, cachedPayments.cycleLabel);
        await m.addColumn(cachedPayments, cachedPayments.consumerName);
        await m.addColumn(cachedPayments, cachedPayments.verificationCode);
        await m.addColumn(
          cachedPayments,
          cachedPayments.transactionTotalCentavos,
        );
        await m.addColumn(cachedPayments, cachedPayments.cashTenderedCentavos);
        await m.addColumn(cachedPayments, cachedPayments.changeDueCentavos);
        await m.addColumn(cachedNotifications, cachedNotifications.consumerId);
      }
      if (from < 5) {
        // An Inbox alert opens onto its bill or notice and its delivery
        // details, so the cache keeps those too. Nullable: rows cached before
        // v5 gain them on the next successful online read.
        await m.addColumn(cachedNotifications, cachedNotifications.billId);
        await m.addColumn(
          cachedNotifications,
          cachedNotifications.disconnectionId,
        );
        await m.addColumn(
          cachedNotifications,
          cachedNotifications.failedReason,
        );
        await m.addColumn(cachedNotifications, cachedNotifications.sentAt);
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
