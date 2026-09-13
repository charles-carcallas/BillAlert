import 'package:billalert/domain/repositories/payment_repository.dart';
import 'package:billalert/domain/value_objects/ids.dart';
import 'package:billalert/domain/value_objects/money.dart';
import 'package:billalert/presentation/cashier/receipt_details_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a cashier can open a receipt and see the handover details', (
    WidgetTester tester,
  ) async {
    final PaymentSummary receipt = PaymentSummary(
      receiptNo: 'BIEC-2026-09-004471',
      consumerId: const ConsumerId('consumer-1'),
      consumerName: 'Virgilio Busalanan',
      verificationCode: 'BA-VERIFY-4471',
      paidAt: DateTime.utc(2026, 9, 9, 2, 30),
      totalCollected: Money.of(1271, 15),
      cashTendered: Money.of(1300),
      changeDue: Money.of(28, 85),
      bills: const <SettledBill>[
        SettledBill(
          billId: BillId('bill-1'),
          billNo: BillNumber('BA-202608-000001'),
          cycleLabel: 'August 2026',
          amountPaid: Money.fromCentavos(60000),
        ),
        SettledBill(
          billId: BillId('bill-2'),
          billNo: BillNumber('BA-202609-000001'),
          cycleLabel: 'September 2026',
          amountPaid: Money.fromCentavos(67115),
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (BuildContext context) => TextButton(
              onPressed: () => showCashierReceiptDetails(context, receipt),
              child: const Text('Open receipt'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open receipt'));
    await tester.pumpAndSettle();

    expect(find.text('Receipt details'), findsOneWidget);
    expect(find.text('BIEC-2026-09-004471'), findsOneWidget);
    expect(find.text('Virgilio Busalanan'), findsOneWidget);
    expect(find.text('BA-VERIFY-4471'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('August 2026'),
      180,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('August 2026'), findsOneWidget);
    expect(find.text('September 2026'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Cash received'),
      180,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('₱1,271.15'), findsOneWidget);
    expect(find.text('₱1,300.00'), findsOneWidget);
    expect(find.text('₱28.85'), findsOneWidget);
  });
}
