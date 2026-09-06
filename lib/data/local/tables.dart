import 'package:drift/drift.dart';

/// The on-device half of the data model, ported from
/// `Week10_DataModel/local/local_cache_schema.sql`.
///
/// Everything here is a CACHE or a QUEUE. Supabase is the source of truth;
/// on sign-out the cached tables are emptied.
///
/// ONE DELIBERATE CHANGE FROM THAT SQL FILE, and it needs to be agreed with
/// the team rather than discovered later. The SQL declares money and meter
/// readings as `real`:
///
///     previous_reading  real not null default 0
///     total_amount      real
///
/// `real` is a double, and the project rule is that money is never a double —
/// binary floating point cannot hold 0.10 exactly, and these columns are
/// summed. So every money column here is an INTEGER number of centavos and
/// every kWh column an INTEGER number of hundredths, matching the Money and
/// Kwh value objects exactly. `local_cache_schema.sql` should be updated to
/// match before anyone else builds on it.
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
  IntColumn get previousReadingHundredths =>
      integer().named('previous_reading_hundredths').withDefault(const Constant(0))();

  TextColumn get previousReadingDate =>
      text().named('previous_reading_date').nullable()();

  /// 'YYYY-MM' in Philippine time. FR-23 checks against this.
  TextColumn get lastReadCycle => text().named('last_read_cycle').nullable()();

  TextColumn get updatedAt => text().named('updated_at').nullable()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

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
  TextColumn get billId => text().named('bill_id').nullable()();
  TextColumn get receiptNo => text().named('receipt_no')();
  IntColumn get amountPaidCentavos => integer().named('amount_paid_centavos')();
  TextColumn get paidAt => text().named('paid_at')();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// CON-05: the alert inbox has to be readable offline too.
@DataClassName('CachedNotificationRow')
class CachedNotifications extends Table {
  @override
  String get tableName => 'cached_notifications';

  TextColumn get id => text()();
  TextColumn get notifType => text().named('notif_type')();
  TextColumn get channel => text()();
  TextColumn get message => text()();
  TextColumn get status => text()();
  BoolColumn get isRead =>
      boolean().named('is_read').withDefault(const Constant(false))();
  TextColumn get createdAt => text().named('created_at')();

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

  IntColumn get id => integer()();
  TextColumn get profileId => text().named('profile_id')();
  TextColumn get role => text()();
  TextColumn get areaId => text().named('area_id').nullable()();
  TextColumn get cachedAt => text().named('cached_at')();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
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
@DataClassName('OutboxRow')
class OutboxRows extends Table {
  @override
  String get tableName => 'outbox';

  /// The idempotency key, minted on device and sent to the server, so a
  /// retried upload cannot create a second row.
  TextColumn get clientUuid => text().named('client_uuid')();

  TextColumn get operation => text()();
  TextColumn get payloadJson => text().named('payload_json')();

  /// MTR-12: the moment of capture, not the moment of sync.
  TextColumn get capturedAt => text().named('captured_at')();

  TextColumn get status => text().withDefault(const Constant('pending'))();
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

  TextColumn get clientUuid => text().named('client_uuid').references(
        OutboxRows,
        #clientUuid,
        onDelete: KeyAction.cascade,
      )();
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
