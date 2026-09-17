import 'package:drift/drift.dart';

/// The on-device half of the core data model: the cache the app reads when
/// there is no signal, and the outbox of work that has not reached the server.
///
/// Everything here is a CACHE or a QUEUE. Supabase is the source of truth; on
/// sign-out the cached tables are emptied and the outbox deliberately is not.
///
/// **This file is the schema of record.** It was ported from
/// `Week10_DataModel/local/local_cache_schema.sql`, which has since been
/// retired. The reasoning that used to live in that file's comments — why the
/// outbox is written before the UI confirms, why `capturedAt` is the moment of
/// capture, why `clientUuid` is minted once, why the cycle label is computed in
/// Manila time rather than read from the device clock — is now in
/// `Week10_DataModel/local/local_cache_design_notes.md`. Read that before
/// changing anything here.
///
/// The one rule worth repeating at the point of use: money is an INTEGER
/// number of centavos and kWh an INTEGER number of hundredths, matching the
/// Money and Kwh value objects and the server's `numeric(12,2)`. Never `real` —
/// that is a double, and binary floating point cannot hold 0.10 exactly.
@TableIndex(
  name: 'idx_cached_consumers_name',
  columns: <Symbol>{#lastName, #firstName},
)
@TableIndex(name: 'idx_cached_consumers_area', columns: <Symbol>{#areaId})
@DataClassName('CachedConsumerRow')
class CachedConsumers extends Table {
  @override
  String get tableName => 'cached_consumers';

  TextColumn get id => text()();
  TextColumn get consumerNo => text().named('consumer_no')();
  TextColumn get firstName => text().named('first_name')();
  TextColumn get lastName => text().named('last_name')();
  TextColumn get contactNumber => text().named('contact_number').nullable()();
  TextColumn get meterSerialNo => text().named('meter_serial_no').nullable()();
  TextColumn get areaId => text().named('area_id')();
  TextColumn get purok => text().nullable()();
  TextColumn get accountStatus => text().named('account_status')();

  /// MTR-08, in hundredths of a kWh. See the note above.
  IntColumn get previousReadingHundredths => integer()
      .named('previous_reading_hundredths')
      .withDefault(const Constant(0))();

  TextColumn get previousReadingDate =>
      text().named('previous_reading_date').nullable()();

  /// 'YYYY-MM' in Philippine time. FR-23 checks against this.
  TextColumn get lastReadCycle => text().named('last_read_cycle').nullable()();

  TextColumn get updatedAt => text().named('updated_at').nullable()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

@TableIndex(
  name: 'idx_cached_bills_consumer',
  columns: <Symbol>{#consumerId, #dueDate},
)
@DataClassName('CachedBillRow')
class CachedBills extends Table {
  @override
  String get tableName => 'cached_bills';

  TextColumn get id => text()();
  TextColumn get billNo => text().named('bill_no')();
  TextColumn get consumerId => text().named('consumer_id')();
  TextColumn get cycleLabel => text().named('cycle_label')();

  IntColumn get consumptionHundredths =>
      integer().named('consumption_hundredths')();

  /// The dial figures the consumption came from, and the day of the reading.
  /// Nullable: rows cached before schema v6 have none, and a bill whose
  /// reading row has gone never had them. FR-25 shows them on Bill Details.
  IntColumn get previousReadingHundredths =>
      integer().named('previous_reading_hundredths').nullable()();
  IntColumn get currentReadingHundredths =>
      integer().named('current_reading_hundredths').nullable()();
  TextColumn get readingDate => text().named('reading_date').nullable()();

  IntColumn get amountPaidCentavos =>
      integer().named('amount_paid_centavos').withDefault(const Constant(0))();

  /// NULL until the cooperative amount is posted (FR-21b). CON-07 still has
  /// to show the reading and the consumption during that seven-day window,
  /// which is why an unpriced bill is cached rather than skipped.
  IntColumn get totalAmountCentavos =>
      integer().named('total_amount_centavos').nullable()();

  TextColumn get dueDate => text().named('due_date').nullable()();
  TextColumn get generatedAt => text().named('generated_at').nullable()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

@DataClassName('CachedPaymentRow')
class CachedPayments extends Table {
  @override
  String get tableName => 'cached_payments';

  TextColumn get id => text()();

  /// Nullable only for databases upgraded from the original unused cache
  /// shape. Every row written by the current app carries the household id.
  TextColumn get consumerId => text().named('consumer_id').nullable()();
  TextColumn get billId => text().named('bill_id').nullable()();
  TextColumn get billNo => text().named('bill_no').nullable()();
  TextColumn get cycleLabel => text().named('cycle_label').nullable()();
  TextColumn get receiptNo => text().named('receipt_no')();
  TextColumn get consumerName => text().named('consumer_name').nullable()();
  TextColumn get verificationCode =>
      text().named('verification_code').nullable()();
  IntColumn get amountPaidCentavos => integer().named('amount_paid_centavos')();
  IntColumn get transactionTotalCentavos =>
      integer().named('transaction_total_centavos').nullable()();
  IntColumn get cashTenderedCentavos =>
      integer().named('cash_tendered_centavos').nullable()();
  IntColumn get changeDueCentavos =>
      integer().named('change_due_centavos').nullable()();
  TextColumn get paidAt => text().named('paid_at')();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// CON-05: the alert inbox has to be readable offline too.
@TableIndex(
  name: 'idx_cached_notif_unread',
  columns: <Symbol>{#isRead, #createdAt},
)
@DataClassName('CachedNotificationRow')
class CachedNotifications extends Table {
  @override
  String get tableName => 'cached_notifications';

  TextColumn get id => text()();

  /// Cache ownership is also enforced by cache_owner; this id makes each
  /// repository query say explicitly which household it is serving.
  TextColumn get consumerId => text().named('consumer_id').nullable()();
  TextColumn get notifType => text().named('notif_type')();
  TextColumn get channel => text()();
  TextColumn get message => text()();
  TextColumn get status => text()();
  BoolColumn get isRead =>
      boolean().named('is_read').withDefault(const Constant(false))();
  TextColumn get createdAt => text().named('created_at')();

  /// The bill or disconnection notice an alert is about, and how far its
  /// delivery got, so an alert opened with no signal still shows them.
  /// Nullable: rows cached before schema v5 did not carry them.
  TextColumn get billId => text().named('bill_id').nullable()();
  TextColumn get disconnectionId =>
      text().named('disconnection_id').nullable()();
  TextColumn get failedReason => text().named('failed_reason').nullable()();
  TextColumn get sentAt => text().named('sent_at').nullable()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// Who this cache belongs to.
///
/// SYS-05 scopes the cache to the signed-in user. Storing the owner makes it
/// impossible to open a previous user cached data by accident if the wipe on
/// sign-out ever fails.
@DataClassName('CacheOwnerRow')
class CacheOwner extends Table {
  @override
  String get tableName => 'cache_owner';

  /// Always 1. This table holds at most one row, and the constraint says so
  /// rather than leaving it to every caller to remember.
  //
  // A drift `.check()` names its own column. drift_dev reads the expression
  // statically to build the SQL and never calls the getter, so the analyzer's
  // recursion warning does not apply. Suppressed per line rather than by
  // turning the lint off for the project, where it is worth keeping.
  // ignore: recursive_getters
  IntColumn get id => integer().check(id.equals(1))();

  TextColumn get profileId => text().named('profile_id')();

  /// The remaining profile fields let an already authenticated person open
  /// their encrypted cache when the phone has no signal. They are nullable
  /// only for databases created before schema v3; a successful online
  /// profile load fills all of them together.
  TextColumn get username => text().nullable()();
  TextColumn get firstName => text().named('first_name').nullable()();
  TextColumn get lastName => text().named('last_name').nullable()();
  BoolColumn get mustChangePassword =>
      boolean().named('must_change_password').nullable()();

  TextColumn get role => text().check(
    // ignore: recursive_getters
    role.isIn(<String>['admin', 'meter_reader', 'cashier', 'consumer']),
  )();

  TextColumn get areaId => text().named('area_id').nullable()();
  TextColumn get cachedAt => text().named('cached_at')();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// The last server answer to a staff read that has no table of its own, as
/// the JSON rows PostgREST returned. See `query_cache.dart`.
@DataClassName('CachedQueryRow')
class CachedQueries extends Table {
  @override
  String get tableName => 'cached_queries';

  TextColumn get queryKey => text().named('query_key')();
  TextColumn get rowsJson => text().named('rows_json')();
  TextColumn get savedAt => text().named('saved_at')();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{queryKey};
}

/// GEN-11: what was refreshed, and when. Every screen showing cached data
/// shows this timestamp, so nobody acts on a stale figure believing it live.
@DataClassName('SyncMetaRow')
class SyncMeta extends Table {
  @override
  String get tableName => 'sync_meta';

  TextColumn get tableName_ => text().named('table_name')();
  TextColumn get lastRefreshedAt =>
      text().named('last_refreshed_at').nullable()();
  TextColumn get lastAttemptAt => text().named('last_attempt_at').nullable()();
  TextColumn get lastError => text().named('last_error').nullable()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{tableName_};
}

/// THE OUTBOX (MTR-11, MTR-12).
///
/// Every action taken offline is written here first, synchronously, before
/// the UI confirms it. The app never holds a pending write only in memory.
@TableIndex(
  // Exactly the filter and sort OutboxRepositoryImpl.pending() runs on every
  // sync drain, against the table most likely to grow over a day in the field.
  name: 'idx_outbox_pending',
  columns: <Symbol>{#status, #capturedAt},
)
@DataClassName('OutboxRow')
class OutboxRows extends Table {
  @override
  String get tableName => 'outbox';

  /// The idempotency key, minted on device and sent to the server, so a
  /// retried upload cannot create a second row.
  TextColumn get clientUuid => text().named('client_uuid')();

  /// Which of the queued actions this row is.
  ///
  /// The constraint earns its place: without it a mistyped code is accepted
  /// here and only fails later in OutboxCodec, far from the line that caused
  /// it. All seven codes are listed because the table has to accept anything
  /// the schema allows — whether the app queues each of them yet is a separate
  /// question.
  TextColumn get operation => text().check(
    // ignore: recursive_getters
    operation.isIn(<String>[
      'record_reading',
      'create_consumer',
      'update_consumer',
      'issue_notice',
      'record_payment',
      'post_amount',
      'close_notice',
    ]),
  )();

  TextColumn get payloadJson => text().named('payload_json')();

  /// MTR-12: the moment of capture, not the moment of sync. The 48-hour
  /// disconnection notice period is counted from it, so it carries legal
  /// meaning and must never be replaced by the upload time.
  TextColumn get capturedAt => text().named('captured_at')();

  TextColumn get status => text()
      .withDefault(const Constant('pending'))
      .check(
        // ignore: recursive_getters
        status.isIn(<String>['pending', 'syncing', 'failed', 'synced']),
      )();
  IntColumn get attempts => integer().withDefault(const Constant(0))();

  /// Surfaced to the user; never silently dropped.
  TextColumn get lastError => text().named('last_error').nullable()();

  TextColumn get serverId => text().named('server_id').nullable()();
  TextColumn get createdAt => text().named('created_at')();
  TextColumn get updatedAt => text().named('updated_at').nullable()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{clientUuid};
}

/// FR-23, checked locally.
///
/// A reader working offline must be stopped at ENTRY, not at sync time an
/// hour later. The unique constraint below makes a second queued reading for
/// the same consumer and cycle impossible, so the duplicate surfaces while
/// the reader is still standing at the meter.
@DataClassName('OutboxReadingKeyRow')
class OutboxReadingKeys extends Table {
  @override
  String get tableName => 'outbox_reading_keys';

  TextColumn get clientUuid => text()
      .named('client_uuid')
      .references(OutboxRows, #clientUuid, onDelete: KeyAction.cascade)();
  TextColumn get consumerId => text().named('consumer_id')();

  /// 'YYYY-MM'
  TextColumn get cycleLabel => text().named('cycle_label')();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{clientUuid};

  @override
  List<String> get customConstraints => <String>[
    'UNIQUE (consumer_id, cycle_label)',
  ];
}
