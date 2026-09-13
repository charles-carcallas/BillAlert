import 'dart:async';

import 'package:flutter_riverpod/misc.dart' show Override;

import '../core/errors/app_failure.dart';
import '../core/result/result.dart';
import '../data/sync/sync_service.dart';
import '../domain/entities/app_user.dart';
import '../domain/entities/bill.dart';
import '../domain/entities/consumer.dart';
import '../domain/entities/staff_account.dart';
import '../domain/outbox/outbox_entry.dart';
import '../domain/outbox/outbox_operation.dart';
import '../domain/repositories/auth_repository.dart';
import '../domain/repositories/bill_repository.dart';
import '../domain/repositories/consumer_repository.dart';
import '../domain/repositories/notice_repository.dart';
import '../domain/repositories/notification_repository.dart';
import '../domain/repositories/outbox_repository.dart';
import '../domain/repositories/payment_repository.dart';
import '../domain/repositories/reading_repository.dart';
import '../domain/time/ph_clock.dart';
import '../domain/value_objects/cycle_label.dart';
import '../domain/value_objects/ids.dart';
import '../domain/value_objects/kwh.dart';
import '../domain/value_objects/money.dart';
import '../domain/value_objects/ph_date.dart';
import '../presentation/providers.dart';

/// Complete, deterministic data wiring for rehearsals and widget tests.
/// The normal build never creates this environment.
List<Override> demoProviderOverrides() {
  final env = _DemoEnvironment();
  return <Override>[
    authRepositoryProvider.overrideWithValue(env.auth),
    consumerRepositoryProvider.overrideWithValue(env.consumers),
    billRepositoryProvider.overrideWithValue(env.bills),
    paymentRepositoryProvider.overrideWithValue(env.payments),
    noticeRepositoryProvider.overrideWithValue(env.notices),
    notificationRepositoryProvider.overrideWithValue(env.notifications),
    readingRepositoryProvider.overrideWithValue(env.readings),
    outboxRepositoryProvider.overrideWithValue(env.outbox),
    syncServiceProvider.overrideWithValue(env.sync),
    phClockProvider.overrideWithValue(const _DemoClock()),
    clientUuidFactoryProvider.overrideWithValue(env.nextUuid),
  ];
}

final class _DemoEnvironment {
  final _DemoStore store = _DemoStore.seeded();
  late final AuthRepository auth = _DemoAuthRepository();
  late final ConsumerRepository consumers = _DemoConsumerRepository(store);
  late final BillRepository bills = _DemoBillRepository(store);
  late final PaymentRepository payments = _DemoPaymentRepository(store);
  late final NoticeRepository notices = _DemoNoticeRepository(store);
  late final NotificationRepository notifications = _DemoNotificationRepository(
    store,
  );
  late final OutboxRepository outbox = _DemoOutboxRepository(store);
  late final ReadingRepository readings = _DemoReadingRepository(store);
  late final SyncService sync = _DemoSyncService(outbox);
  int _counter = 0;

  ClientUuid nextUuid() => ClientUuid('demo-${++_counter}');
}

final class _DemoClock implements PhClock {
  const _DemoClock();
  @override
  DateTime nowUtc() => DateTime.utc(2026, 9, 10, 4);
  @override
  PhDate today() => const PhDate(2026, 9, 10);
}

final class _DemoStore {
  static const area = AreaId('demo-tubod-area');
  static const elena = ConsumerId('demo-elena');
  static const sarigumba = ConsumerId('demo-sarigumba');
  static const virgilio = ConsumerId('demo-virgilio');

  final List<Consumer> consumers;
  final List<Bill> bills;
  final List<AwaitingAmountEntry> awaiting;
  final List<PaymentSummary> payments;
  final List<ActiveNotice> notices;
  final List<AppNotification> notifications;
  final List<OutboxEntry> outbox = <OutboxEntry>[];
  final StreamController<List<OutboxEntry>> outboxChanges =
      StreamController<List<OutboxEntry>>.broadcast();

  _DemoStore({
    required this.consumers,
    required this.bills,
    required this.awaiting,
    required this.payments,
    required this.notices,
    required this.notifications,
  });

  factory _DemoStore.seeded() {
    const august = CycleLabel(2026, 8);
    const households = <Consumer>[
      Consumer(
        id: elena,
        consumerNo: ConsumerNumber('2018-0442-TUB'),
        firstName: 'Elena',
        lastName: 'Bongcaras',
        areaId: area,
        accountStatus: AccountStatus.active,
        previousReading: Kwh.fromHundredths(461000),
        meterSerialNo: 'BIEC-08319',
        purok: 'Purok 1',
        previousReadingDate: PhDate(2026, 8, 7),
        lastReadCycle: august,
      ),
      Consumer(
        id: sarigumba,
        consumerNo: ConsumerNumber('2020-0791-TUB'),
        firstName: 'Bienvenido',
        lastName: 'Sarigumba',
        areaId: area,
        accountStatus: AccountStatus.active,
        previousReading: Kwh.fromHundredths(323840),
        meterSerialNo: 'BIEC-11072',
        purok: 'Purok 2',
        previousReadingDate: PhDate(2026, 8, 8),
        lastReadCycle: august,
      ),
      Consumer(
        id: virgilio,
        consumerNo: ConsumerNumber('2019-0614-TUB'),
        firstName: 'Virgilio',
        lastName: 'Bacus',
        areaId: area,
        accountStatus: AccountStatus.active,
        previousReading: Kwh.fromHundredths(591275),
        meterSerialNo: 'BIEC-09114',
        purok: 'Purok 3',
        previousReadingDate: PhDate(2026, 8, 8),
        lastReadCycle: august,
      ),
      Consumer(
        id: ConsumerId('demo-teresita'),
        consumerNo: ConsumerNumber('2017-0228-TUB'),
        firstName: 'Teresita',
        lastName: 'Daguplo',
        areaId: area,
        accountStatus: AccountStatus.active,
        previousReading: Kwh.fromHundredths(278190),
        meterSerialNo: 'BIEC-07128',
        purok: 'Purok 4',
        previousReadingDate: PhDate(2026, 8, 9),
        lastReadCycle: august,
      ),
      Consumer(
        id: ConsumerId('demo-odelon'),
        consumerNo: ConsumerNumber('2022-1287-TUB'),
        firstName: 'Odelon',
        lastName: 'Paredes',
        areaId: area,
        accountStatus: AccountStatus.active,
        previousReading: Kwh.fromHundredths(184055),
        meterSerialNo: 'BIEC-12542',
        purok: 'Purok 5',
        previousReadingDate: PhDate(2026, 8, 9),
        lastReadCycle: august,
      ),
    ];
    const elenaJuly = Bill(
      id: BillId('demo-elena-july'),
      billNo: BillNumber('BA-202607-000442'),
      consumerId: elena,
      cycle: CycleLabel(2026, 7),
      consumption: Kwh.fromHundredths(11850),
      totalAmount: Money.fromCentavos(54120),
      dueDate: PhDate(2026, 8, 28),
    );
    const elenaJune = Bill(
      id: BillId('demo-elena-june'),
      billNo: BillNumber('BA-202606-000442'),
      consumerId: elena,
      cycle: CycleLabel(2026, 6),
      consumption: Kwh.fromHundredths(11240),
      totalAmount: Money.fromCentavos(52340),
      dueDate: PhDate(2026, 7, 28),
      amountPaid: Money.fromCentavos(52340),
    );
    const elenaMay = Bill(
      id: BillId('demo-elena-may'),
      billNo: BillNumber('BA-202605-000442'),
      consumerId: elena,
      cycle: CycleLabel(2026, 5),
      consumption: Kwh.fromHundredths(10680),
      totalAmount: Money.fromCentavos(49875),
      dueDate: PhDate(2026, 6, 28),
      amountPaid: Money.fromCentavos(49875),
    );
    const sarigumbaAugust = Bill(
      id: BillId('demo-sarigumba-august'),
      billNo: BillNumber('BA-202608-000791'),
      consumerId: sarigumba,
      cycle: CycleLabel(2026, 8),
      consumption: Kwh.fromHundredths(10420),
      totalAmount: Money.fromCentavos(53345),
      dueDate: PhDate(2026, 9, 28),
    );
    const virgilioAugust = Bill(
      id: BillId('demo-virgilio-august'),
      billNo: BillNumber('BA-202608-000614'),
      consumerId: virgilio,
      cycle: CycleLabel(2026, 8),
      consumption: Kwh.fromHundredths(13275),
      totalAmount: Money.fromCentavos(67830),
      dueDate: PhDate(2026, 9, 28),
    );
    const teresitaAugust = Bill(
      id: BillId('demo-teresita-august'),
      billNo: BillNumber('BA-202608-000228'),
      consumerId: ConsumerId('demo-teresita'),
      cycle: CycleLabel(2026, 8),
      consumption: Kwh.fromHundredths(8960),
      totalAmount: null,
      dueDate: null,
    );
    return _DemoStore(
      consumers: <Consumer>[...households],
      bills: <Bill>[
        elenaJuly,
        elenaJune,
        elenaMay,
        sarigumbaAugust,
        virgilioAugust,
        teresitaAugust,
      ],
      awaiting: const <AwaitingAmountEntry>[
        AwaitingAmountEntry(
          bill: teresitaAugust,
          consumerName: 'Teresita Daguplo',
          consumerNo: ConsumerNumber('2017-0228-TUB'),
          purok: 'Purok 4',
          previousReading: Kwh.fromHundredths(269230),
          currentReading: Kwh.fromHundredths(278190),
          readingDate: PhDate(2026, 9, 7),
          daysWaiting: 3,
        ),
      ],
      payments: <PaymentSummary>[
        PaymentSummary(
          receiptNo: 'OR-2026-0802-0018',
          consumerId: elena,
          consumerName: 'Elena Bongcaras',
          verificationCode: 'BILL-ELENA-18QF',
          paidAt: DateTime.utc(2026, 8, 2, 2, 20),
          totalCollected: const Money.fromCentavos(102215),
          cashTendered: const Money.fromCentavos(110000),
          changeDue: const Money.fromCentavos(7785),
          bills: const <SettledBill>[
            SettledBill(
              billId: BillId('demo-elena-june'),
              billNo: BillNumber('BA-202606-000442'),
              cycleLabel: 'June 2026',
              amountPaid: Money.fromCentavos(52340),
            ),
            SettledBill(
              billId: BillId('demo-elena-may'),
              billNo: BillNumber('BA-202605-000442'),
              cycleLabel: 'May 2026',
              amountPaid: Money.fromCentavos(49875),
            ),
          ],
        ),
        PaymentSummary(
          receiptNo: 'OR-2026-0909-0041',
          consumerId: virgilio,
          consumerName: 'Virgilio Bacus',
          verificationCode: 'BILL-7K4P-91QX',
          paidAt: DateTime.utc(2026, 9, 9, 6, 15),
          totalCollected: const Money.fromCentavos(61200),
          cashTendered: const Money.fromCentavos(70000),
          changeDue: const Money.fromCentavos(8800),
          bills: const <SettledBill>[
            SettledBill(
              billId: BillId('demo-virgilio-july'),
              billNo: BillNumber('BA-202607-000614'),
              cycleLabel: 'July 2026',
              amountPaid: Money.fromCentavos(61200),
            ),
          ],
        ),
      ],
      notices: <ActiveNotice>[
        ActiveNotice(
          id: const NoticeId('fe59ec52-60de-4663-b301-01a7861ae213'),
          noticeNo: 'DN-2026-0910-0033',
          consumerId: elena,
          consumerLabel: 'Elena Bongcaras',
          consumerNo: '2018-0442-TUB',
          purok: 'Purok 1',
          meterSerialNo: 'BIEC-08319',
          reason: 'Unpaid July 2026 bill, due 28 August 2026',
          issuedByName: 'Mario Ombajin',
          servedAt: DateTime.utc(2026, 9, 9, 20, 55, 50),
          earliestLawfulAt: DateTime.utc(2026, 9, 14),
          periodElapsed: false,
          amountOverdue: const Money.fromCentavos(54120),
          hoursRemaining: 92,
        ),
      ],
      notifications: <AppNotification>[
        AppNotification(
          id: const NotificationId('demo-alert-overdue'),
          type: 'overdue',
          channel: 'push',
          message: 'Your July 2026 bill is overdue. Amount due: ₱541.20.',
          isRead: false,
          createdAt: DateTime.utc(2026, 8, 29, 0, 5),
        ),
        AppNotification(
          id: const NotificationId('demo-alert-ready'),
          type: 'bill_ready',
          channel: 'push',
          message: 'Your July 2026 bill is ready. Due 28 August 2026.',
          isRead: true,
          createdAt: DateTime.utc(2026, 8, 7, 2, 30),
        ),
      ],
    );
  }

  void emitOutbox() =>
      outboxChanges.add(List<OutboxEntry>.unmodifiable(outbox));
}

final class _DemoAuthRepository implements AuthRepository {
  static const users = <String, AppUser>{
    'admin': AdminUser(
      id: ProfileId('demo-admin'),
      username: 'admin',
      firstName: 'Mario',
      lastName: 'Ombajin',
      areaId: _DemoStore.area,
      mustChangePassword: false,
    ),
    'reader': MeterReaderUser(
      id: ProfileId('demo-reader'),
      username: 'reader',
      firstName: 'Ledesman',
      lastName: 'Dormal',
      areaId: _DemoStore.area,
      mustChangePassword: false,
    ),
    'cashier': CashierUser(
      id: ProfileId('demo-cashier'),
      username: 'cashier',
      firstName: 'Maria',
      lastName: 'Cañete',
      areaId: _DemoStore.area,
      mustChangePassword: false,
    ),
    'consumer': ConsumerUser(
      id: ProfileId('demo-consumer-profile'),
      username: 'consumer',
      firstName: 'Elena',
      lastName: 'Bongcaras',
      mustChangePassword: false,
    ),
  };
  final StreamController<AppUser?> changes =
      StreamController<AppUser?>.broadcast();
  AppUser? current;

  @override
  Stream<AppUser?> authChanges() => changes.stream;
  @override
  Future<Result<AppUser?>> currentUser() async => Ok<AppUser?>(current);
  @override
  Future<Result<void>> changePassword({required String newPassword}) async =>
      const Ok<void>(null);

  @override
  Future<Result<CreatedStaffAccount>> createStaffAccount({
    required String username,
    required String firstName,
    required String lastName,
    required String? contactNumber,
    required StaffRole role,
    required String temporaryPassword,
  }) async => Err<CreatedStaffAccount>(
    ConflictFailure(
      'This service area already has an active ${role.label}. Deactivate or '
      'reassign that account before creating another.',
    ),
  );
  @override
  Future<Result<void>> signOut() async {
    current = null;
    changes.add(null);
    return const Ok<void>(null);
  }

  @override
  Future<Result<AppUser>> signIn({
    required String username,
    required String password,
  }) async {
    final key = username.trim().toLowerCase();
    final alias = const <String, String>{
      'mario.ombajin': 'admin',
      'ledesman.dormal': 'reader',
      'maria.canete': 'cashier',
      'elena.bongcaras': 'consumer',
    }[key];
    final user = users[key] ?? users[alias];
    if (password != 'demo' || user == null) {
      return const Err<AppUser>(
        AuthFailure(
          'Use admin, reader, cashier, or consumer with password demo.',
        ),
      );
    }
    current = user;
    changes.add(user);
    return Ok<AppUser>(user);
  }
}

final class _DemoConsumerRepository implements ConsumerRepository {
  final _DemoStore store;
  _DemoConsumerRepository(this.store);

  @override
  Future<Result<List<Consumer>>> areaRoster(AreaId areaId) async =>
      Ok<List<Consumer>>(List<Consumer>.unmodifiable(store.consumers));
  @override
  Future<Result<Consumer?>> byId(ConsumerId id) async =>
      Ok<Consumer?>(_first(store.consumers, (c) => c.id == id));
  @override
  Future<Result<DateTime?>> lastRefreshedAt() async =>
      Ok<DateTime?>(DateTime.utc(2026, 9, 10, 3, 55));
  @override
  Future<Result<void>> refreshAreaRoster(AreaId areaId) async =>
      const Ok<void>(null);
  @override
  Future<Result<Consumer?>> signedInConsumer() async =>
      Ok<Consumer?>(_first(store.consumers, (c) => c.id == _DemoStore.elena));

  @override
  Future<Result<String>> updateOwnContactNumber(String contactNumber) async {
    // Demo mode has no server trigger. Keep the text rather than duplicating
    // the production normalization rule in Dart.
    final index = store.consumers.indexWhere((c) => c.id == _DemoStore.elena);
    if (index >= 0) {
      final existing = store.consumers[index];
      store.consumers[index] = Consumer(
        id: existing.id,
        consumerNo: existing.consumerNo,
        firstName: existing.firstName,
        lastName: existing.lastName,
        areaId: existing.areaId,
        accountStatus: existing.accountStatus,
        previousReading: existing.previousReading,
        contactNumber: contactNumber,
        meterSerialNo: existing.meterSerialNo,
        purok: existing.purok,
        previousReadingDate: existing.previousReadingDate,
        lastReadCycle: existing.lastReadCycle,
      );
    }
    return Ok<String>(contactNumber);
  }

  @override
  Future<Result<Consumer>> create({
    required ConsumerNumber consumerNo,
    required String firstName,
    required String lastName,
    required AreaId areaId,
    required ProfileId createdBy,
    String? contactNumber,
    String? purok,
  }) async {
    final value = Consumer(
      id: ConsumerId('demo-${store.consumers.length + 1}'),
      consumerNo: consumerNo,
      firstName: firstName,
      lastName: lastName,
      areaId: areaId,
      accountStatus: AccountStatus.active,
      previousReading: Kwh.zero,
      contactNumber: contactNumber,
      purok: purok,
    );
    store.consumers.add(value);
    return Ok<Consumer>(value);
  }
}

final class _DemoBillRepository implements BillRepository {
  final _DemoStore store;
  _DemoBillRepository(this.store);

  @override
  Future<Result<List<AwaitingAmountEntry>>> awaitingAmount(
    AreaId areaId,
  ) async => Ok<List<AwaitingAmountEntry>>(
    List<AwaitingAmountEntry>.unmodifiable(store.awaiting),
  );
  @override
  Future<Result<Bill?>> byId(BillId id) async =>
      Ok<Bill?>(_first(store.bills, (b) => b.id == id));
  @override
  Future<Result<Bill?>> currentBillFor(ConsumerId id) async {
    final values = store.bills.where((b) => b.consumerId == id).toList()
      ..sort((a, b) => b.cycle.compareTo(a.cycle));
    return Ok<Bill?>(values.isEmpty ? null : values.first);
  }

  @override
  Future<Result<List<Bill>>> historyFor(ConsumerId id, {int limit = 12}) async {
    final values = store.bills.where((b) => b.consumerId == id).toList()
      ..sort((a, b) => b.cycle.compareTo(a.cycle));
    return Ok<List<Bill>>(values.take(limit).toList());
  }

  @override
  Future<Result<List<Bill>>> payableFor(ConsumerId id) async => Ok<List<Bill>>(
    store.bills
        .where((b) => b.consumerId == id && b.isPayable && !b.isSettled)
        .toList(),
  );
  @override
  Future<Result<void>> refreshFor(ConsumerId id, CycleLabel cycle) async =>
      const Ok<void>(null);

  @override
  Future<Result<List<ConsumerOutstanding>>> outstandingInArea(
    AreaId areaId,
  ) async {
    final rows = <ConsumerOutstanding>[];
    for (final consumer in store.consumers) {
      final related = store.bills
          .where((b) => b.consumerId == consumer.id)
          .toList();
      final payable = related
          .where((b) => b.isPayable && !b.isSettled)
          .toList();
      final unpriced = related.where((b) => b.isUnpriced).length;
      if (payable.isEmpty && unpriced == 0) continue;
      rows.add(
        ConsumerOutstanding(
          consumerId: consumer.id,
          consumerNo: consumer.consumerNo,
          consumerName: consumer.fullName,
          purok: consumer.purok,
          payableBillCount: payable.length,
          unpricedBillCount: unpriced,
          overdueCount: payable
              .where((b) => b.isOverdueOn(const PhDate(2026, 9, 10)))
              .length,
          totalOutstanding: payable.fold(
            Money.zero,
            (sum, bill) => sum + bill.balance,
          ),
        ),
      );
    }
    return Ok<List<ConsumerOutstanding>>(rows);
  }
}

final class _DemoPaymentRepository implements PaymentRepository {
  final _DemoStore store;
  _DemoPaymentRepository(this.store);
  @override
  Future<Result<CollectionSummary>> dailySummary(AreaId areaId) async =>
      const Ok<CollectionSummary>(
        CollectionSummary(
          receiptCount: 1,
          totalCollected: Money.fromCentavos(61200),
        ),
      );
  @override
  Future<Result<List<PaymentSummary>>> historyFor(ConsumerId id) async =>
      Ok<List<PaymentSummary>>(
        store.payments.where((p) => p.consumerId == id).toList(),
      );
  @override
  Future<Result<List<PaymentSummary>>> recentInArea(
    AreaId areaId, {
    int limit = 50,
  }) async => Ok<List<PaymentSummary>>(store.payments.take(limit).toList());
}

final class _DemoNoticeRepository implements NoticeRepository {
  final _DemoStore store;
  _DemoNoticeRepository(this.store);
  @override
  Future<Result<List<ActiveNotice>>> activeFor(AreaId areaId) async =>
      Ok<List<ActiveNotice>>(List<ActiveNotice>.unmodifiable(store.notices));
  @override
  Future<Result<ActiveNotice?>> byId(NoticeId id) async =>
      Ok<ActiveNotice?>(_first(store.notices, (n) => n.id == id));
  @override
  Future<Result<void>> closeNotice({
    required NoticeId noticeId,
    required NoticeOutcome outcome,
    String? notes,
  }) async {
    store.notices.removeWhere((n) => n.id == noticeId);
    return const Ok<void>(null);
  }
}

final class _DemoNotificationRepository implements NotificationRepository {
  final _DemoStore store;
  _DemoNotificationRepository(this.store);
  @override
  Future<Result<List<AppNotification>>> inboxFor(ConsumerId id) async =>
      Ok<List<AppNotification>>(
        List<AppNotification>.unmodifiable(store.notifications),
      );
  @override
  Future<Result<int>> unreadCount() async =>
      Ok<int>(store.notifications.where((n) => !n.isRead).length);
  @override
  Future<Result<void>> markRead(NotificationId id) async {
    final index = store.notifications.indexWhere((n) => n.id == id);
    if (index >= 0) {
      final old = store.notifications[index];
      store.notifications[index] = AppNotification(
        id: old.id,
        type: old.type,
        channel: old.channel,
        message: old.message,
        isRead: true,
        createdAt: old.createdAt,
      );
    }
    return const Ok<void>(null);
  }
}

final class _DemoReadingRepository implements ReadingRepository {
  final _DemoStore store;
  _DemoReadingRepository(this.store);
  Iterable<RecordReadingOperation> get queued => store.outbox
      .map((entry) => entry.operation)
      .whereType<RecordReadingOperation>();
  @override
  Future<Result<bool>> isReadingQueuedFor({
    required ConsumerId consumerId,
    required CycleLabel cycle,
  }) async => Ok<bool>(
    queued.any(
      (operation) =>
          operation.consumerId == consumerId && operation.cycleLabel == cycle,
    ),
  );
  @override
  Future<Result<Set<ConsumerId>>> queuedConsumerIdsFor(
    CycleLabel cycle,
  ) async => Ok<Set<ConsumerId>>(
    queued
        .where((operation) => operation.cycleLabel == cycle)
        .map((operation) => operation.consumerId)
        .toSet(),
  );
}

final class _DemoOutboxRepository implements OutboxRepository {
  final _DemoStore store;
  _DemoOutboxRepository(this.store);
  @override
  Future<Result<List<OutboxEntry>>> all() async =>
      Ok<List<OutboxEntry>>(List<OutboxEntry>.unmodifiable(store.outbox));
  @override
  Future<Result<List<OutboxEntry>>> pending() async => Ok<List<OutboxEntry>>(
    store.outbox.where((entry) => entry.isPending || entry.hasFailed).toList(),
  );
  @override
  Stream<List<OutboxEntry>> watchAll() async* {
    yield List<OutboxEntry>.unmodifiable(store.outbox);
    yield* store.outboxChanges.stream;
  }

  @override
  Future<Result<void>> enqueue(OutboxOperation operation) async {
    if (operation is RecordReadingOperation &&
        store.outbox.any((entry) {
          final prior = entry.operation;
          return prior is RecordReadingOperation &&
              prior.consumerId == operation.consumerId &&
              prior.cycleLabel == operation.cycleLabel;
        })) {
      return const Err<void>(
        ConflictFailure(
          'A reading for this household and month is already waiting to sync.',
        ),
      );
    }
    store.outbox.add(
      OutboxEntry(
        operation: operation,
        status: OutboxStatus.pending,
        attempts: 0,
        createdAt: operation.capturedAt,
      ),
    );
    store.emitOutbox();
    return const Ok<void>(null);
  }

  @override
  Future<Result<void>> markFailed(ClientUuid id, String reason) async =>
      _replace(id, OutboxStatus.failed, error: reason);
  @override
  Future<Result<void>> markSynced(ClientUuid id, String serverId) async =>
      _replace(id, OutboxStatus.synced, serverId: serverId);
  @override
  Future<Result<void>> markSyncing(ClientUuid id) async =>
      _replace(id, OutboxStatus.syncing);
  Future<Result<void>> _replace(
    ClientUuid id,
    OutboxStatus status, {
    String? error,
    String? serverId,
  }) async {
    final index = store.outbox.indexWhere((e) => e.operation.clientUuid == id);
    if (index < 0) return const Ok<void>(null);
    final old = store.outbox[index];
    store.outbox[index] = OutboxEntry(
      operation: old.operation,
      status: status,
      attempts: status == OutboxStatus.syncing
          ? old.attempts + 1
          : old.attempts,
      lastError: error,
      serverId: serverId,
      createdAt: old.createdAt,
    );
    store.emitOutbox();
    return const Ok<void>(null);
  }
}

/// Keeps demo actions visible in memory. This rehearses the UI flow; it does
/// not substitute for the production SQLite force-stop test.
final class _DemoSyncService extends SyncService {
  _DemoSyncService(OutboxRepository outbox)
    : super(outbox, const _DemoGateway());
  @override
  void start() {}
  @override
  Future<void> stop() async {}
  @override
  Future<Result<SyncReport>> syncNow() async =>
      const Ok<SyncReport>(SyncReport.nothingToDo);
}

final class _DemoGateway implements OutboxGateway {
  const _DemoGateway();
  @override
  Future<Result<String>> submitNotice(IssueNoticeOperation value) async =>
      Ok<String>('demo-${value.clientUuid.value}');
  @override
  Future<Result<String>> submitPayment(RecordPaymentOperation value) async =>
      Ok<String>('demo-${value.clientUuid.value}');
  @override
  Future<Result<String>> submitPostedAmount(PostAmountOperation value) async =>
      Ok<String>('demo-${value.clientUuid.value}');
  @override
  Future<Result<String>> submitReading(RecordReadingOperation value) async =>
      Ok<String>('demo-${value.clientUuid.value}');
}

T? _first<T>(Iterable<T> values, bool Function(T) matches) {
  for (final value in values) {
    if (matches(value)) return value;
  }
  return null;
}
