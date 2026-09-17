import 'package:billalert/domain/entities/app_user.dart';
import 'package:billalert/domain/entities/bill.dart';
import 'package:billalert/domain/entities/consumer.dart';
import 'package:billalert/domain/usecases/reader/load_reading_sheet.dart';
import 'package:billalert/domain/value_objects/cycle_label.dart';
import 'package:billalert/domain/value_objects/ids.dart';
import 'package:billalert/domain/value_objects/kwh.dart';
import 'package:billalert/domain/value_objects/ph_date.dart';
import 'package:billalert/presentation/auth/auth_controller.dart';
import 'package:billalert/presentation/providers.dart';
import 'package:billalert/presentation/reader/reading_sheet_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Consumer;
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';

void main() {
  const reader = MeterReaderUser(
    id: ProfileId('reader-1'),
    username: 'ledesma.dormal',
    firstName: 'Ledesma',
    lastName: 'Dormal',
    areaId: AreaId('area-3'),
    mustChangePassword: false,
  );
  const september = CycleLabel(2026, 9);

  Consumer home(String id, String first, String last, String purok) => Consumer(
    id: ConsumerId(id),
    consumerNo: ConsumerNumber('2020-$id-TUB'),
    firstName: first,
    lastName: last,
    areaId: const AreaId('area-3'),
    accountStatus: AccountStatus.active,
    previousReading: Kwh.of(4610),
    purok: purok,
    meterSerialNo: 'MTR-$id',
  );

  late FakeBillRepository bills;

  setUp(() {
    bills = FakeBillRepository()
      ..history = <Bill>[
        Bill(
          id: const BillId('bill-0791'),
          billNo: const BillNumber('BA-202609-000001'),
          consumerId: const ConsumerId('0791'),
          cycle: september,
          consumption: Kwh.of(58),
          totalAmount: null,
          dueDate: null,
          previousReading: Kwh.of(4610),
          currentReading: Kwh.of(4668),
          readingDate: const PhDate(2026, 9, 7),
        ),
      ];
  });

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(412, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(
            () => FakeAuthController(signedInUser: reader),
          ),
          consumerRepositoryProvider.overrideWithValue(
            FakeConsumerRepository(<Consumer>[
              home('0791', 'Bienvenido', 'Sarigumba', 'Purok 3'),
              home('0812', 'Rosalinda', 'Amistad', 'Purok 5'),
            ]),
          ),
          billRepositoryProvider.overrideWithValue(bills),
          outboxRepositoryProvider.overrideWithValue(FakeOutboxRepository()),
          phClockProvider.overrideWithValue(
            FixedPhClock.onPhDate(const PhDate(2026, 9, 9)),
          ),
        ],
        child: const MaterialApp(home: ReadingSheetScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('lists every household with its readings or "Not read"', (
    WidgetTester tester,
  ) async {
    await open(tester);

    expect(find.text('September 2026'), findsOneWidget);
    expect(find.text('Bienvenido Sarigumba'), findsOneWidget);
    expect(find.text('Previous'), findsOneWidget);
    expect(find.text('4,610.00'), findsOneWidget);
    expect(find.text('Present'), findsOneWidget);
    expect(find.text('4,668.00'), findsOneWidget);
    expect(find.text('58.00'), findsOneWidget);
    expect(find.text('Rosalinda Amistad'), findsOneWidget);
    expect(find.text('Not read'), findsWidgets);
  });

  testWidgets('"Not read" narrows the list to the meters still to visit', (
    WidgetTester tester,
  ) async {
    await open(tester);

    await tester.tap(find.text('Not read 1'));
    await tester.pumpAndSettle();

    expect(find.text('Rosalinda Amistad'), findsOneWidget);
    expect(find.text('Bienvenido Sarigumba'), findsNothing);
  });

  test('the copied table has a header and one tab-separated line each', () {
    final sheet = ReadingSheet(
      cycle: september,
      rows: <ReadingSheetRow>[
        ReadingSheetRow(
          household: home('0791', 'Bienvenido', 'Sarigumba', 'Purok 3'),
          state: SheetRowState.synced,
          previousReading: Kwh.of(4610),
          currentReading: Kwh.of(4668),
          readingDate: const PhDate(2026, 9, 7),
        ),
        ReadingSheetRow(
          household: home('0812', 'Rosalinda', 'Amistad', 'Purok 5'),
          state: SheetRowState.notRead,
        ),
      ],
    );

    final String copied = readingSheetText(sheet, reader: 'Ledesma Dormal');

    expect(copied, contains('Reading sheet — September 2026'));
    expect(copied, contains('Read: 1 of 2'));
    expect(
      copied,
      contains(
        '1\t2020-0791-TUB\tBienvenido Sarigumba\tPurok 3\tMTR-0791\t'
        '4,610.00\t4,668.00\t58.00\t7 Sep 2026',
      ),
    );
    expect(copied, contains('2\t2020-0812-TUB\tRosalinda Amistad'));
    expect(copied, contains('NOT READ'));
  });
}
