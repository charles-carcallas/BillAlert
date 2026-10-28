import 'dart:async';
import 'package:billalert/core/errors/app_failure.dart';
import 'package:billalert/core/result/result.dart';
import 'package:billalert/data/local/app_database.dart';
import 'package:billalert/data/repositories/outbox_repository_impl.dart';
import 'package:billalert/data/sync/outbox_session.dart';
import 'package:billalert/data/sync/sync_service.dart';
import 'package:billalert/domain/entities/bill.dart';
import 'package:billalert/domain/outbox/outbox_entry.dart';
import 'package:billalert/domain/outbox/outbox_operation.dart';
import 'package:billalert/domain/usecases/cashier/record_cash_payment.dart';
import 'package:billalert/domain/value_objects/cycle_label.dart';
import 'package:billalert/domain/value_objects/ids.dart';
import 'package:billalert/domain/value_objects/kwh.dart';
import 'package:billalert/domain/value_objects/money.dart';
import 'package:billalert/domain/value_objects/ph_date.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/fakes.dart';

class Link implements Connectivity {
  final Completer<List<ConnectivityResult>>? check;
  Link([this.check]);
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async =>
      check == null ? [ConnectivityResult.wifi] : await check!.future;
  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      const Stream.empty();
}

class Gateway implements OutboxGateway {
  final sent = <String>[];
  Future<void> Function()? duringSend;
  @override
  Future<Result<String>> submitReading(RecordReadingOperation op) async {
    sent.add(op.clientUuid.value);
    await duringSend?.call();
    return Ok('bill-${op.clientUuid.value}');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late AppDatabase db;
  late OutboxSession session;
  late OutboxRepositoryImpl outbox;
  RecordReadingOperation reading(String id) => RecordReadingOperation(
    clientUuid: ClientUuid(id),
    capturedAt: DateTime.utc(2026, 10, 2),
    consumerId: ConsumerId('house-$id'),
    currentReading: Kwh.parse('10'),
    cycleLabel: const CycleLabel(2026, 10),
    consumerLabel: 'Test household',
  );
  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    session = OutboxSession()
      ..scope = const OutboxScope('reader-a', 'meter_reader', 'area-a');
    outbox = OutboxRepositoryImpl(db, session: session);
  });
  tearDown(() => db.close());
  test(
    'another account, role or area cannot read or mark the original work',
    () async {
      await outbox.enqueue(reading('one'));
      for (final scope in [
        const OutboxScope('reader-b', 'meter_reader', 'area-a'),
        const OutboxScope('reader-a', 'cashier', 'area-a'),
        const OutboxScope('reader-a', 'meter_reader', 'area-b'),
      ]) {
        session.scope = scope;
        expect(
          (await outbox.pending() as Ok<List<OutboxEntry>>).value,
          isEmpty,
        );
        expect(
          await outbox.markSynced(const ClientUuid('one'), 'wrong'),
          isA<Err<void>>(),
        );
      }
      session.scope = const OutboxScope('reader-a', 'meter_reader', 'area-a');
      expect(
        (await outbox.pending() as Ok<List<OutboxEntry>>)
            .value
            .single
            .operation
            .clientUuid
            .value,
        'one',
      );
    },
  );
  test('legacy rows survive but are quarantined', () async {
    await outbox.enqueue(reading('old'));
    await db
        .update(db.outboxRows)
        .write(const OutboxRowsCompanion(ownerId: Value(null)));
    expect((await outbox.pending() as Ok<List<OutboxEntry>>).value, isEmpty);
    expect((await outbox.quarantinedCount() as Ok<int>).value, 1);
    await db.clearCachedData();
    expect((await outbox.quarantinedCount() as Ok<int>).value, 1);
  });
  test(
    'overlapping requests share the drain before connectivity resolves',
    () async {
      await outbox.enqueue(reading('one'));
      final link = Completer<List<ConnectivityResult>>();
      final gateway = Gateway();
      final sync = SyncService(
        outbox,
        gateway,
        connectivity: Link(link),
        session: session,
      );
      final first = sync.syncNow();
      final second = sync.syncNow();
      expect(identical(first, second), isTrue);
      link.complete([ConnectivityResult.wifi]);
      expect((await second as Ok<SyncReport>).value.succeeded, 1);
      expect(gateway.sent, ['one']);
      await sync.dispose();
    },
  );
  test('captures arriving during upload join the same drain', () async {
    await outbox.enqueue(reading('one'));
    final gateway = Gateway();
    gateway.duringSend = () async {
      if (gateway.sent.length == 1) await outbox.enqueue(reading('two'));
    };
    final sync = SyncService(
      outbox,
      gateway,
      connectivity: Link(),
      session: session,
    );
    expect((await sync.syncNow() as Ok<SyncReport>).value.succeeded, 2);
    expect(gateway.sent, ['one', 'two']);
    await sync.dispose();
  });
  test(
    'stop waits for dispatched work and never sends the next queued item',
    () async {
      await outbox.enqueue(reading('one'));
      await outbox.enqueue(reading('two'));
      final arrived = Completer<void>();
      final release = Completer<void>();
      final gateway = Gateway()
        ..duringSend = () async {
          arrived.complete();
          await release.future;
        };
      final sync = SyncService(
        outbox,
        gateway,
        connectivity: Link(),
        session: session,
      );
      final running = sync.syncNow();
      await arrived.future;
      var stopped = false;
      final stopping = sync.stop().then((_) => stopped = true);
      await Future<void>.delayed(Duration.zero);
      expect(stopped, isFalse);
      release.complete();
      await stopping;
      await running;
      expect(gateway.sent, ['one']);
      expect(
        (await outbox.pending() as Ok<List<OutboxEntry>>)
            .value
            .single
            .operation
            .clientUuid
            .value,
        'two',
      );
      await sync.dispose();
    },
  );
  test(
    'reserved payment survives repository restart and interrupted upload',
    () async {
      RecordPaymentOperation payment(String uuid) => RecordPaymentOperation(
        clientUuid: ClientUuid(uuid),
        capturedAt: DateTime.utc(2026, 10, 2),
        billIds: [const BillId('bill')],
        amounts: [Money.parse('100')],
        consumerLabel: 'Test',
      );
      expect(await outbox.enqueue(payment('original')), isA<Ok<void>>());
      await outbox.markSyncing(const ClientUuid('original'));
      final reopened = OutboxRepositoryImpl(db, session: session);
      expect(await reopened.enqueue(payment('duplicate')), isA<Err<void>>());
      final waiting = (await reopened.pending() as Ok<List<OutboxEntry>>).value;
      expect(waiting.single.operation.clientUuid.value, 'original');
      expect(waiting.single.status, OutboxStatus.syncing);
    },
  );
  test(
    'only an explicit rejected due date is editable, keeping the operation and amounts',
    () async {
      final op = PostAmountOperation(
        clientUuid: const ClientUuid('post'),
        capturedAt: DateTime.utc(2026, 10, 1),
        billId: const BillId('bill'),
        amount: Money.parse('530'),
        cooperativeAmount: Money.parse('529.40'),
        dueDate: const PhDate(2026, 10, 1),
        billLabel: 'TEST',
      );
      await outbox.enqueue(op);
      await outbox.markFailed(op.clientUuid, 'Connection lost');
      expect(
        await outbox.reviseRejectedDueDate(
          op.clientUuid,
          const PhDate(2026, 10, 28),
        ),
        isA<Err<void>>(),
      );
      await outbox.markFailed(op.clientUuid, 'The due date has passed');
      expect(
        await outbox.reviseRejectedDueDate(
          op.clientUuid,
          const PhDate(2026, 10, 28),
        ),
        isA<Ok<void>>(),
      );
      final entry =
          (await outbox.pending() as Ok<List<OutboxEntry>>).value.single;
      final changed = entry.operation as PostAmountOperation;
      expect(changed.clientUuid, op.clientUuid);
      expect(changed.cooperativeAmount, op.cooperativeAmount);
      expect(changed.amount, op.amount);
      expect(changed.capturedAt, op.capturedAt);
      expect(changed.dueDate, const PhDate(2026, 10, 28));
      expect(entry.status, OutboxStatus.pending);
    },
  );
  test(
    'account switch while checking collection cannot enqueue under a new account',
    () async {
      final fake = FakeOutboxRepository();
      final entered = Completer<void>();
      final release = Completer<Result<void>>();
      final useCase = RecordCashPayment(
        outbox: fake,
        clock: FixedPhClock.onPhDate(const PhDate(2026, 10, 2)),
        newClientUuid: () => const ClientUuid('payment'),
        verifyCollection: (_, _) {
          entered.complete();
          return release.future;
        },
      );
      const bill = Bill(
        id: BillId('bill'),
        billNo: BillNumber('TEST'),
        consumerId: ConsumerId('house'),
        cycle: CycleLabel(2026, 10),
        consumption: Kwh.fromHundredths(100),
        totalAmount: Money.fromCentavos(10000),
        dueDate: PhDate(2026, 10, 28),
      );
      final result = useCase(
        consumerLabel: 'Test',
        bills: [bill],
        amounts: [bill.balance],
      );
      await entered.future;
      fake.sessionGeneration++;
      release.complete(const Ok<void>(null));
      expect(
        await result,
        isA<Err<void>>().having(
          (e) => e.failure,
          'failure',
          isA<AuthFailure>(),
        ),
      );
      expect(fake.enqueued, isEmpty);
    },
  );
  test(
    'local status write failure stops upload and retains pending work',
    () async {
      await outbox.enqueue(reading('one'));
      await db.customStatement(
        "create trigger reject_status before update of status on outbox begin select raise(FAIL, 'simulated storage failure'); end",
      );
      final gateway = Gateway();
      final sync = SyncService(
        outbox,
        gateway,
        connectivity: Link(),
        session: session,
      );
      expect(await sync.syncNow(), isA<Err<SyncReport>>());
      expect(gateway.sent, isEmpty);
      expect(
        (await outbox.pending() as Ok<List<OutboxEntry>>).value.single.status,
        OutboxStatus.pending,
      );
      await sync.dispose();
    },
  );
}
