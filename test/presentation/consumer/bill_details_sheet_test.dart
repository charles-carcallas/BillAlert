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
    expect(find.text('September 2026'), findsWidgets);

    // The statement leads with what is still owed.
    expect(find.text('Partially paid'), findsOneWidget);
    expect(find.text('Remaining balance'), findsOneWidget);
    expect(find.text('₱605.00'), findsOneWidget);

    // ...broken down directly beneath, so the figure is never on trust.
    await tester.scrollUntilVisible(
      find.text('Payment received'),
      160,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Payment received'), findsOneWidget);
    expect(find.text('₱1,005.00'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Due in 10 days'),
      160,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Due in 10 days'), findsOneWidget);

    // The reference facts close the sheet.
    await tester.scrollUntilVisible(
      find.text('67.00 kWh'),
      160,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('67.00 kWh'), findsOneWidget);
    expect(find.text('BA-202609-000001'), findsOneWidget);
    expect(find.text('OFFICIAL DIGITAL RECEIPT'), findsNothing);
  });

  testWidgets('an overdue bill counts the days past its due date', (
    WidgetTester tester,
  ) async {
    // July, due 28 August, still unpaid on 10 September: 3 days left in
    // August plus 10 in September. An off-by-one here tells a household it
    // has one day more or less than it does.
    const Bill bill = Bill(
      id: BillId('bill-3'),
      billNo: BillNumber('BA-202607-000902'),
      consumerId: ConsumerId('consumer-1'),
      cycle: CycleLabel(2026, 7),
      consumption: Kwh.fromHundredths(5900),
      totalAmount: Money.fromCentavos(54120),
      dueDate: PhDate(2026, 8, 28),
    );

    await tester.pumpWidget(
      _testApp(
        onOpen: (BuildContext context) => showConsumerBillDetails(
          context,
          bill: bill,
          today: const PhDate(2026, 9, 10),
        ),
      ),
    );
    await tester.tap(find.text('Open bill'));
    await tester.pumpAndSettle();

    expect(find.text('Overdue'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Overdue by 13 days'),
      160,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Overdue by 13 days'), findsOneWidget);
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

  testWidgets('the dial figures behind the consumption are shown', (
    WidgetTester tester,
  ) async {
    // 1,289.40 less 1,222.40 is the 67.00 kWh charged for. The point of
    // printing all three is that the household can do that subtraction.
    const Bill bill = Bill(
      id: BillId('bill-4'),
      billNo: BillNumber('BA-202609-000001'),
      consumerId: ConsumerId('consumer-1'),
      cycle: CycleLabel(2026, 9),
      consumption: Kwh.fromHundredths(6700),
      totalAmount: Money.fromCentavos(100500),
      dueDate: PhDate(2026, 9, 30),
      previousReading: Kwh.fromHundredths(122240),
      currentReading: Kwh.fromHundredths(128940),
      readingDate: PhDate(2026, 9, 8),
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

    await tester.scrollUntilVisible(
      find.text('Present reading'),
      160,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('1,222.40 kWh'), findsOneWidget);
    expect(find.text('1,289.40 kWh'), findsOneWidget);
    expect(find.text('67.00 kWh'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Date read'),
      160,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('8 September 2026'), findsOneWidget);
  });

  testWidgets('a bill with no reading says so rather than showing zero', (
    WidgetTester tester,
  ) async {
    // What a row cached before the readings were carried looks like, and
    // what the Admin's pricing queue returns. A zero here would read as a
    // meter that never turned.
    const Bill bill = Bill(
      id: BillId('bill-5'),
      billNo: BillNumber('BA-202609-000002'),
      consumerId: ConsumerId('consumer-1'),
      cycle: CycleLabel(2026, 9),
      consumption: Kwh.fromHundredths(6700),
      totalAmount: Money.fromCentavos(100500),
      dueDate: PhDate(2026, 9, 30),
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

    await tester.scrollUntilVisible(
      find.text('Present reading'),
      160,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Not recorded'), findsNWidgets(2));
    expect(find.text('0.00 kWh'), findsNothing);
    expect(find.text('Date read'), findsNothing);
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
