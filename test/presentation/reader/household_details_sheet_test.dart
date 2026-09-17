import 'package:billalert/core/errors/app_failure.dart';
import 'package:billalert/core/result/result.dart';
import 'package:billalert/domain/entities/app_user.dart';
import 'package:billalert/domain/entities/bill.dart';
import 'package:billalert/domain/entities/consumer.dart';
import 'package:billalert/domain/repositories/payment_repository.dart';
import 'package:billalert/domain/value_objects/cycle_label.dart';
import 'package:billalert/domain/value_objects/ids.dart';
import 'package:billalert/domain/value_objects/kwh.dart';
import 'package:billalert/domain/value_objects/money.dart';
import 'package:billalert/domain/value_objects/ph_date.dart';
import 'package:billalert/presentation/auth/auth_controller.dart';
import 'package:billalert/presentation/providers.dart';
import 'package:billalert/presentation/reader/consumers_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Consumer;
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';

/// Only [historyFor] is used by the household sheet.
final class _Payments implements PaymentRepository {
  Result<List<PaymentSummary>> result = const Ok<List<PaymentSummary>>(
    <PaymentSummary>[],
  );

  @override
  Future<Result<List<PaymentSummary>>> historyFor(ConsumerId id) async =>
      result;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Meter Reader › Consumers: a household in the list opens its details,
/// bills and payments.
void main() {
  const reader = MeterReaderUser(
    id: ProfileId('reader-1'),
    username: 'ledesma.dormal',
    firstName: 'Ledesma',
    lastName: 'Dormal',
    areaId: AreaId('area-3'),
    mustChangePassword: false,
  );

  late FakeBillRepository bills;
  late _Payments payments;

  setUp(() {
    bills = FakeBillRepository()
      ..history = const <Bill>[
        Bill(
          id: BillId('bill-aug'),
          billNo: BillNumber('BA-202608-000001'),
          consumerId: ConsumerId('consumer-1'),
          cycle: CycleLabel(2026, 8),
          consumption: Kwh.fromHundredths(5800),
          totalAmount: Money.fromCentavos(67100),
          dueDate: PhDate(2026, 9, 20),
          amountPaid: Money.fromCentavos(67100),
        ),
      ];
    payments = _Payments()
      ..result = Ok<List<PaymentSummary>>(<PaymentSummary>[
        PaymentSummary(
          receiptNo: 'BIEC-2026-09-004471',
          consumerId: const ConsumerId('consumer-1'),
          consumerName: 'Elena Ravelo',
          verificationCode: 'BA-VERIFY-4471',
          paidAt: DateTime.utc(2026, 9, 9, 2, 30),
          totalCollected: const Money.fromCentavos(67100),
          bills: const <SettledBill>[
            SettledBill(
              billId: BillId('bill-aug'),
              billNo: BillNumber('BA-202608-000001'),
              cycleLabel: 'August 2026',
              amountPaid: Money.fromCentavos(67100),
            ),
          ],
        ),
      ]);
  });

  Future<void> openConsumers(WidgetTester tester) async {
    tester.view.physicalSize = const Size(412, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final consumers = FakeConsumerRepository(<Consumer>[household()])
      ..refreshedAt = DateTime.utc(2026, 9, 9);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(
            () => FakeAuthController(signedInUser: reader),
          ),
          consumerRepositoryProvider.overrideWithValue(consumers),
          billRepositoryProvider.overrideWithValue(bills),
          paymentRepositoryProvider.overrideWithValue(payments),
          phClockProvider.overrideWithValue(
            FixedPhClock.onPhDate(const PhDate(2026, 9, 9)),
          ),
        ],
        child: const MaterialApp(home: ReaderConsumersScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('tapping a household shows its details, bills and payments', (
    WidgetTester tester,
  ) async {
    await openConsumers(tester);

    await tester.tap(find.text('Elena Ravelo'));
    await tester.pumpAndSettle();

    expect(find.text('Household'), findsOneWidget);
    expect(find.text('Meter serial'), findsOneWidget);
    expect(find.text('August 2026'), findsOneWidget);
    expect(find.textContaining('BIEC-2026-09-004471'), findsOneWidget);
  });

  testWidgets('a payment opens its receipt', (WidgetTester tester) async {
    await openConsumers(tester);
    await tester.tap(find.text('Elena Ravelo'));
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('BIEC-2026-09-004471'));
    await tester.pumpAndSettle();

    expect(find.text('Receipt details'), findsOneWidget);
  });

  testWidgets('payments that cannot load still leave the bills showing', (
    WidgetTester tester,
  ) async {
    payments.result = const Err<List<PaymentSummary>>(NetworkFailure());
    await openConsumers(tester);
    await tester.tap(find.text('Elena Ravelo'));
    await tester.pumpAndSettle();

    expect(find.text('August 2026'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });
}
