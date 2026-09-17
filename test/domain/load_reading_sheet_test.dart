import 'package:billalert/core/errors/app_failure.dart';
import 'package:billalert/core/result/result.dart';
import 'package:billalert/domain/entities/bill.dart';
import 'package:billalert/domain/entities/consumer.dart';
import 'package:billalert/domain/outbox/outbox_operation.dart';
import 'package:billalert/domain/usecases/reader/load_reading_sheet.dart';
import 'package:billalert/domain/value_objects/cycle_label.dart';
import 'package:billalert/domain/value_objects/ids.dart';
import 'package:billalert/domain/value_objects/kwh.dart';
import 'package:billalert/domain/value_objects/ph_date.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

/// Step 2 of the Meter Reader's month: the list that goes onto BOHECO's paper.
void main() {
  const september = CycleLabel(2026, 9);
  const AreaId area = AreaId('area-3');

  Consumer home(String id, {String? purok, String? no, CycleLabel? readFor}) =>
      Consumer(
        id: ConsumerId(id),
        consumerNo: ConsumerNumber(no ?? '2020-$id-TUB'),
        firstName: 'H',
        lastName: id,
        areaId: area,
        accountStatus: AccountStatus.active,
        previousReading: Kwh.of(1000),
        purok: purok,
        lastReadCycle: readFor,
      );

  Bill billFor(String id, int previous, int current) => Bill(
    id: BillId('bill-$id'),
    billNo: BillNumber('BA-$id'),
    consumerId: ConsumerId(id),
    cycle: september,
    consumption: Kwh.of(current - previous),
    totalAmount: null,
    dueDate: null,
    previousReading: Kwh.of(previous),
    currentReading: Kwh.of(current),
    readingDate: const PhDate(2026, 9, 7),
  );

  late FakeConsumerRepository consumers;
  late FakeBillRepository bills;
  late FakeOutboxRepository outbox;

  LoadReadingSheet useCase() =>
      LoadReadingSheet(consumers: consumers, bills: bills, outbox: outbox);

  Future<ReadingSheet> load() async =>
      switch (await useCase()(areaId: area, cycle: september)) {
        Ok(:final value) => value,
        Err(:final failure) => throw failure,
      };

  setUp(() {
    consumers = FakeConsumerRepository(<Consumer>[
      home('a', purok: 'Purok 2'),
      home('b', purok: 'Purok 1'),
      home('c', purok: 'Purok 1'),
    ]);
    bills = FakeBillRepository();
    outbox = FakeOutboxRepository();
  });

  test('every household appears once, read or not', () async {
    bills.history = <Bill>[billFor('b', 1000, 1058)];

    final sheet = await load();

    expect(sheet.rows, hasLength(3));
    expect(sheet.readCount, 1);
    expect(sheet.notReadCount, 2);
  });

  test('a synced reading carries the figures its bill was made from', () async {
    bills.history = <Bill>[billFor('b', 4610, 4668)];

    final row = (await load()).rows.firstWhere(
      (ReadingSheetRow r) => r.household.id == const ConsumerId('b'),
    );

    expect(row.state, SheetRowState.synced);
    expect(row.previousReading, Kwh.of(4610));
    expect(row.currentReading, Kwh.of(4668));
    expect(row.consumption, Kwh.of(58));
  });

  test('a reading still on the phone is listed with its figures', () async {
    outbox.enqueued.add(
      RecordReadingOperation(
        clientUuid: const ClientUuid('u1'),
        capturedAt: DateTime.utc(2026, 9, 7, 1),
        consumerId: const ConsumerId('a'),
        currentReading: Kwh.of(1041),
        cycleLabel: september,
        consumerLabel: 'H a',
      ),
    );

    final row = (await load()).rows.firstWhere(
      (ReadingSheetRow r) => r.household.id == const ConsumerId('a'),
    );

    expect(row.state, SheetRowState.waitingToSync);
    expect(row.previousReading, Kwh.of(1000));
    expect(row.consumption, Kwh.of(41));
    expect(row.readingDate, const PhDate(2026, 9, 7));
  });

  test('rows run purok by purok, then by account number', () async {
    final sheet = await load();

    expect(
      sheet.rows.map((ReadingSheetRow r) => r.household.id.value).toList(),
      <String>['b', 'c', 'a'],
    );
  });

  test('the total adds every known consumption', () async {
    bills.history = <Bill>[billFor('b', 1000, 1058), billFor('c', 2000, 2041)];

    expect((await load()).totalConsumption, Kwh.of(99));
  });

  test(
    'with no signal, the sheet still lists households and says why',
    () async {
      consumers = FakeConsumerRepository(<Consumer>[
        home('a', readFor: september),
        home('b'),
      ]);
      bills.readingsFailure = const NetworkFailure();

      final sheet = await load();

      expect(sheet.serverFailure, isA<NetworkFailure>());
      expect(
        sheet.rows.map((ReadingSheetRow r) => r.state).toList(),
        <SheetRowState>[
          SheetRowState.recordedFiguresUnavailable,
          SheetRowState.notRead,
        ],
      );
    },
  );

  test('an inactive account is not on the sheet', () async {
    consumers = FakeConsumerRepository(<Consumer>[
      home('a'),
      household(id: 'gone', areaId: 'area-3', status: AccountStatus.inactive),
    ]);

    expect((await load()).rows, hasLength(1));
  });
}
