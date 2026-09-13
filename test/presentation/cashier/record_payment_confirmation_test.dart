import 'package:billalert/domain/entities/app_user.dart';
import 'package:billalert/domain/entities/bill.dart';
import 'package:billalert/domain/repositories/bill_repository.dart';
import 'package:billalert/domain/value_objects/cycle_label.dart';
import 'package:billalert/domain/value_objects/ids.dart';
import 'package:billalert/domain/value_objects/kwh.dart';
import 'package:billalert/domain/value_objects/money.dart';
import 'package:billalert/domain/value_objects/ph_date.dart';
import 'package:billalert/presentation/auth/auth_controller.dart';
import 'package:billalert/presentation/cashier/record_payment_screen.dart';
import 'package:billalert/presentation/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';

void main() {
  testWidgets('payment waits for confirmation of the handover summary', (
    WidgetTester tester,
  ) async {
    const consumerId = ConsumerId('consumer-1');
    const household = ConsumerOutstanding(
      consumerId: consumerId,
      consumerNo: ConsumerNumber('2019-0917-TUB'),
      consumerName: 'Elena Ravelo',
      payableBillCount: 1,
      unpricedBillCount: 0,
      overdueCount: 0,
      totalOutstanding: Money.fromCentavos(50000),
    );
    const bill = Bill(
      id: BillId('bill-1'),
      billNo: BillNumber('BA-202609-000001'),
      consumerId: consumerId,
      cycle: CycleLabel(2026, 9),
      consumption: Kwh.fromHundredths(5000),
      totalAmount: Money.fromCentavos(50000),
      dueDate: PhDate(2026, 9, 30),
    );
    const cashier = CashierUser(
      id: ProfileId('cashier-1'),
      username: 'mercedita.gales',
      firstName: 'Mercedita',
      lastName: 'Gales',
      areaId: AreaId('area-3'),
      mustChangePassword: false,
    );
    final bills = FakeBillRepository()
      ..outstanding = <ConsumerOutstanding>[household]
      ..payableBills = <Bill>[bill];
    final outbox = FakeOutboxRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(
            () => FakeAuthController(signedInUser: cashier),
          ),
          billRepositoryProvider.overrideWithValue(bills),
          outboxRepositoryProvider.overrideWithValue(outbox),
          phClockProvider.overrideWithValue(
            FixedPhClock.onPhDate(const PhDate(2026, 9, 13)),
          ),
        ],
        child: const MaterialApp(home: RecordPaymentScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Elena Ravelo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('September 2026'));
    await tester.enterText(find.byType(TextField), '600.00');
    await tester.pump();
    await tester.tap(find.text('Confirm cash payment · ₱500.00'));
    await tester.pumpAndSettle();

    final Finder dialog = find.byType(AlertDialog);
    expect(find.text('Confirm cash payment'), findsOneWidget);
    expect(
      find.descendant(of: dialog, matching: find.text('Elena Ravelo')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dialog, matching: find.text('₱500.00')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dialog, matching: find.text('₱600.00')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dialog, matching: find.text('₱100.00')),
      findsOneWidget,
    );
    expect(outbox.enqueued, isEmpty);

    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();
    expect(outbox.enqueued, isEmpty);
  });
}
