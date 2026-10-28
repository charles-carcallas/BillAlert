import 'package:billalert/domain/repositories/payment_repository.dart';
import 'package:billalert/domain/value_objects/ids.dart';
import 'package:billalert/domain/value_objects/money.dart';
import 'package:billalert/presentation/cashier/receipt_details_sheet.dart';
import 'package:billalert/presentation/cashier/record_payment_controller.dart';
import 'package:billalert/presentation/cashier/record_payment_screen.dart';
import 'package:billalert/presentation/common/receipt_qr_code.dart';
import 'package:billalert/presentation/consumer/receipt_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

final receipt = PaymentSummary(
  receiptNo: 'OR-TEST-123',
  consumerId: const ConsumerId('household'),
  consumerName: 'Test household',
  verificationCode: 'BA-VERIFY-123',
  paidAt: DateTime.utc(2026, 10, 1),
  totalCollected: Money.of(500),
  bills: const <SettledBill>[
    SettledBill(
      billId: BillId('a'),
      billNo: BillNumber('B-1'),
      cycleLabel: 'August 2026',
      amountPaid: Money.fromCentavos(20000),
    ),
    SettledBill(
      billId: BillId('b'),
      billNo: BillNumber('B-2'),
      cycleLabel: 'September 2026',
      amountPaid: Money.fromCentavos(30000),
    ),
  ],
);

class _Issued extends RecordPaymentController {
  @override
  RecordPaymentState build() => RecordPaymentState(receipt: receipt);
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      'all receipt views share one scannable reference in $brightness',
      (tester) async {
        tester.view.physicalSize = const Size(320, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        for (final screen in <Widget>[
          ConsumerReceiptScreen(receiptNo: receipt.receiptNo),
          Scaffold(body: CashierReceiptDetails(receipt: receipt)),
          const RecordPaymentScreen(),
        ]) {
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                consumerReceiptProvider(
                  receipt.receiptNo,
                ).overrideWith((ref) async => receipt),
                recordPaymentControllerProvider.overrideWith(_Issued.new),
              ],
              child: MaterialApp(
                theme: ThemeData(brightness: brightness),
                home: screen,
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
            find.byType(ReceiptQrCode),
            180,
            scrollable: find.byType(Scrollable).first,
          );
          expect(find.byType(QrImageView), findsOneWidget);
          final qr = tester.widget<QrImageView>(find.byType(QrImageView));
          expect(
            tester
                .widget<ReceiptQrCode>(find.byType(ReceiptQrCode))
                .verificationCode,
            receipt.verificationCode,
          );
          expect(qr.backgroundColor, Colors.white);
          expect(qr.dataModuleStyle.color, Colors.black);
          expect(qr.padding, const EdgeInsets.all(32));
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        }
      },
    );
  }

  testWidgets('missing reference does not generate a made-up QR code', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ReceiptQrCode(verificationCode: '  ')),
      ),
    );
    expect(find.byType(QrImageView), findsNothing);
    expect(find.text('Scannable reference unavailable.'), findsOneWidget);
  });
}
