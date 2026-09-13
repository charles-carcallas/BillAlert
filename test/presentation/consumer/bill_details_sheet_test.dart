import 'package:billalert/domain/entities/bill.dart';
import 'package:billalert/domain/value_objects/cycle_label.dart';
import 'package:billalert/domain/value_objects/ids.dart';
import 'package:billalert/domain/value_objects/kwh.dart';
import 'package:billalert/domain/value_objects/money.dart';
import 'package:billalert/domain/value_objects/ph_date.dart';
import 'package:billalert/presentation/consumer/bill_details_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Bills opens bill facts rather than payment receipt details', (
    WidgetTester tester,
  ) async {
    const Bill bill = Bill(
      id: BillId('bill-1'),
      billNo: BillNumber('BA-202609-000001'),
      consumerId: ConsumerId('consumer-1'),
      cycle: CycleLabel(2026, 9),
      consumption: Kwh.fromHundredths(6700),
      totalAmount: Money.fromCentavos(100500),
      dueDate: PhDate(2026, 9, 30),
      amountPaid: Money.fromCentavos(40000),
    );

    await tester.pumpWidget(
      _testApp(
        onOpen: (BuildContext context) => showConsumerBillDetails(
          context,
          bill: bill,
          today: const PhDate(2026, 9, 20),
        ),
      ),
    );
    await tester.tap(find.text('Open bill'));
    await tester.pumpAndSettle();

    expect(find.text('Bill details'), findsOneWidget);
    expect(find.text('BA-202609-000001'), findsOneWidget);
    expect(find.text('September 2026'), findsWidgets);

    await tester.scrollUntilVisible(
      find.text('67.00 kWh'),
      160,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('67.00 kWh'), findsOneWidget);
    expect(find.text('₱1,005.00'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Remaining balance'),
      160,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Payment received'), findsOneWidget);
    expect(find.text('₱605.00'), findsOneWidget);
    expect(find.text('OFFICIAL DIGITAL RECEIPT'), findsNothing);
  });

  testWidgets('an unpriced bill states that its amount is not posted', (
    WidgetTester tester,
  ) async {
    const Bill bill = Bill(
      id: BillId('bill-2'),
      billNo: BillNumber('BA-202610-000001'),
      consumerId: ConsumerId('consumer-1'),
      cycle: CycleLabel(2026, 10),
      consumption: Kwh.fromHundredths(5900),
      totalAmount: null,
      dueDate: null,
    );

    await tester.pumpWidget(
      _testApp(
        onOpen: (BuildContext context) => showConsumerBillDetails(
          context,
          bill: bill,
          today: const PhDate(2026, 10, 5),
        ),
      ),
    );
    await tester.tap(find.text('Open bill'));
    await tester.pumpAndSettle();

    expect(find.text('Awaiting amount'), findsOneWidget);
    expect(find.text('Not posted yet'), findsOneWidget);
    expect(find.text('Not assigned yet'), findsOneWidget);
    expect(find.text('Payment received'), findsNothing);
  });
}

Widget _testApp({required ValueChanged<BuildContext> onOpen}) => MaterialApp(
  home: Scaffold(
    body: Builder(
      builder: (BuildContext context) => TextButton(
        onPressed: () => onOpen(context),
        child: const Text('Open bill'),
      ),
    ),
  ),
);
