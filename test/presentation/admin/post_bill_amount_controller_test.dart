import 'package:billalert/core/errors/app_failure.dart';
import 'package:billalert/domain/entities/app_user.dart';
import 'package:billalert/domain/entities/bill.dart';
import 'package:billalert/domain/outbox/outbox_operation.dart';
import 'package:billalert/domain/repositories/bill_repository.dart';
import 'package:billalert/domain/value_objects/cycle_label.dart';
import 'package:billalert/domain/value_objects/ids.dart';
import 'package:billalert/domain/value_objects/kwh.dart';
import 'package:billalert/domain/value_objects/money.dart';
import 'package:billalert/domain/value_objects/ph_date.dart';
import 'package:billalert/presentation/admin/post_bill_amount_controller.dart';
import 'package:billalert/presentation/auth/auth_controller.dart';
import 'package:billalert/presentation/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';

/// FR-21b. The Admin transcribes a figure; the app must carry it to the
/// outbox exactly, or refuse it in words they can act on.
///
/// These run the REAL PostBillAmount use case over fake infrastructure, so
/// the domain rules — no zero, no date in the past, no re-pricing — are
/// under test here too, not just the controller's plumbing.
void main() {
  const AreaId area3 = AreaId('11111111-0000-0000-0000-00000000000a');

  const admin = AdminUser(
    id: ProfileId('admin-1'),
    username: 'mario.ombajin',
    firstName: 'Mario',
    lastName: 'Ombajin',
    areaId: area3,
    mustChangePassword: false,
  );

  // 9 September 2026, so "the past" and "the future" are fixed facts rather
  // than whatever day the suite happens to run on.
  final clock = FixedPhClock.onPhDate(const PhDate(2026, 9, 9));

  AwaitingAmountEntry sarigumba() => const AwaitingAmountEntry(
        bill: Bill(
          id: BillId('117cdc15-a13a-4c25-ba20-f46d89667272'),
          billNo: BillNumber('BA-202608-000005'),
          consumerId: ConsumerId('e9d5aba2'),
          cycle: CycleLabel(2026, 8),
          consumption: Kwh.fromHundredths(5800),
          totalAmount: null,
          dueDate: null,
        ),
        consumerName: 'Bienvenido Sarigumba',
        consumerNo: ConsumerNumber('2020-0791-TUB'),
        previousReading: Kwh.fromHundredths(461000),
        currentReading: Kwh.fromHundredths(466800),
        readingDate: PhDate(2026, 8, 10),
        daysWaiting: 6,
      );

  late FakeBillRepository bills;
  late FakeOutboxRepository outbox;
  late FakeSyncService sync;

  ProviderContainer harness() {
    bills = FakeBillRepository()..queue = <AwaitingAmountEntry>[sarigumba()];
    outbox = FakeOutboxRepository();
    sync = FakeSyncService();

    final container = ProviderContainer(
      overrides: [
        authControllerProvider
            .overrideWith(() => FakeAuthController(signedInUser: admin)),
        billRepositoryProvider.overrideWithValue(bills),
        outboxRepositoryProvider.overrideWithValue(outbox),
        syncServiceProvider.overrideWithValue(sync),
        phClockProvider.overrideWithValue(clock),
        clientUuidFactoryProvider
            .overrideWithValue(CountingUuidFactory().call),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<PostBillAmountController> loaded(ProviderContainer container) async {
    final controller =
        container.read(postBillAmountControllerProvider.notifier);
    await controller.refresh();
    return controller;
  }

  PostBillAmountState stateOf(ProviderContainer c) =>
      c.read(postBillAmountControllerProvider);

  test('loads the queue for the area the Admin presides over', () async {
    final container = harness();
    await loaded(container);

    expect(bills.awaitingCalls, greaterThanOrEqualTo(1));
    expect(stateOf(container).queue.single.consumerName, 'Bienvenido Sarigumba');
    expect(stateOf(container).failure, isNull);
  });

  test('a typed amount reaches the outbox as exact centavos', () async {
    final container = harness();
    final controller = await loaded(container);

    await controller.post(
      entry: sarigumba(),
      amountText: '658.30',
      dueDate: const PhDate(2026, 9, 25),
    );

    expect(outbox.enqueued, hasLength(1));
    final operation = outbox.enqueued.single as PostAmountOperation;

    // The whole point of Money: 658.30 is 65,830 centavos and never a double.
    expect(operation.amount, const Money.fromCentavos(65830));
    expect(operation.amount.toDatabaseString(), '658.30');
    expect(operation.billId, const BillId('117cdc15-a13a-4c25-ba20-f46d89667272'));
    expect(operation.dueDate.toIso(), '2026-09-25');
    expect(stateOf(container).failure, isNull);
  });

  test('a comma and a peso sign are accepted, because people type them',
      () async {
    final container = harness();
    final controller = await loaded(container);

    await controller.post(
      entry: sarigumba(),
      amountText: '₱1,975.35',
      dueDate: const PhDate(2026, 9, 25),
    );

    expect(
      (outbox.enqueued.single as PostAmountOperation).amount,
      const Money.fromCentavos(197535),
    );
  });

  test('text that is not an amount is refused, and nothing is queued',
      () async {
    final container = harness();
    final controller = await loaded(container);

    await controller.post(
      entry: sarigumba(),
      amountText: 'six hundred',
      dueDate: const PhDate(2026, 9, 25),
    );

    expect(outbox.enqueued, isEmpty);
    expect(stateOf(container).failure, isA<ValidationFailure>());
    // The queue is still on screen: a typo must not empty the list.
    expect(stateOf(container).queue, hasLength(1));
  });

  test('a missing due date is refused before anything is queued', () async {
    final container = harness();
    final controller = await loaded(container);

    await controller.post(
      entry: sarigumba(),
      amountText: '658.30',
      dueDate: null,
    );

    expect(outbox.enqueued, isEmpty);
    expect(stateOf(container).failure, isA<ValidationFailure>());
  });

  test('zero is refused here, not hours later at sync', () async {
    // fn_post_bill_amount refuses it too, but an Admin may be offline: a
    // zero would otherwise sit in the outbox looking accepted.
    final container = harness();
    final controller = await loaded(container);

    await controller.post(
      entry: sarigumba(),
      amountText: '0',
      dueDate: const PhDate(2026, 9, 25),
    );

    expect(outbox.enqueued, isEmpty);
    expect(stateOf(container).failure, isA<ValidationFailure>());
  });

  test('a due date already past is refused', () async {
    final container = harness();
    final controller = await loaded(container);

    await controller.post(
      entry: sarigumba(),
      amountText: '658.30',
      dueDate: const PhDate(2026, 9, 1),
    );

    expect(outbox.enqueued, isEmpty);
    expect(stateOf(container).failure, isA<ValidationFailure>());
  });

  test('a bill that already has an amount cannot be re-priced', () async {
    final container = harness();
    final controller = await loaded(container);

    const priced = AwaitingAmountEntry(
      bill: Bill(
        id: BillId('already-priced'),
        billNo: BillNumber('BA-202607-000001'),
        consumerId: ConsumerId('c-1'),
        cycle: CycleLabel(2026, 7),
        consumption: Kwh.fromHundredths(5800),
        totalAmount: Money.fromCentavos(65830),
        dueDate: PhDate(2026, 8, 25),
      ),
      consumerName: 'Bienvenido Sarigumba',
      consumerNo: ConsumerNumber('2020-0791-TUB'),
      previousReading: Kwh.fromHundredths(461000),
      currentReading: Kwh.fromHundredths(466800),
      readingDate: PhDate(2026, 7, 10),
      daysWaiting: 30,
    );

    await controller.post(
      entry: priced,
      amountText: '700.00',
      dueDate: const PhDate(2026, 9, 25),
    );

    expect(outbox.enqueued, isEmpty);
    expect(stateOf(container).failure, isA<ConflictFailure>());
  });

  test('a successful post drains the outbox and reloads the queue', () async {
    // Posting is what makes the bill leave v_readings_awaiting_amount and
    // sends the consumer's alert, so the sync is not fire-and-forget here.
    final container = harness();
    final controller = await loaded(container);
    final int callsBefore = bills.awaitingCalls;

    // The server would drop it from the queue; the fake has to be told.
    bills.queue = <AwaitingAmountEntry>[];

    await controller.post(
      entry: sarigumba(),
      amountText: '658.30',
      dueDate: const PhDate(2026, 9, 25),
    );

    expect(sync.syncCalls, 1);
    expect(bills.awaitingCalls, greaterThan(callsBefore));
    expect(stateOf(container).queue, isEmpty);
    expect(stateOf(container).postedMessage, contains('Bienvenido Sarigumba'));
  });
}
