import 'package:billalert/domain/repositories/payment_repository.dart';
import 'package:billalert/domain/value_objects/ids.dart';
import 'package:billalert/domain/value_objects/money.dart';
import 'package:billalert/domain/value_objects/ph_date.dart';
import 'package:billalert/presentation/consumer/payment_history_filter.dart';
import 'package:flutter_test/flutter_test.dart';

PaymentSummary payment(String number, DateTime instant) => PaymentSummary(
  receiptNo: number,
  consumerId: const ConsumerId('home'),
  consumerName: 'Test household',
  verificationCode: 'VERIFY-$number',
  paidAt: instant,
  totalCollected: Money.of(500),
  bills: const <SettledBill>[
    SettledBill(
      billId: BillId('bill'),
      billNo: BillNumber('B-1'),
      cycleLabel: 'August 2026',
      amountPaid: Money.fromCentavos(50000),
    ),
  ],
);

void main() {
  final receipts = <PaymentSummary>[
    payment('before', DateTime.utc(2026, 9, 30, 15, 59, 59)),
    payment('start', DateTime.utc(2026, 9, 30, 16)),
    payment('end', DateTime.utc(2026, 10, 1, 15, 59, 59, 999)),
    payment('after', DateTime.utc(2026, 10, 1, 16)),
  ];

  test('single-day range includes both PH boundaries, not billing month', () {
    final result = filterPaymentHistory(
      receipts,
      from: const PhDate(2026, 10, 1),
      through: const PhDate(2026, 10, 1),
    );
    expect(result.map((r) => r.receiptNo), ['end', 'start']);
  });

  test(
    'range and month or receipt search intersect, without mutating input',
    () {
      final result = filterPaymentHistory(
        receipts,
        from: const PhDate(2026, 10, 1),
        through: const PhDate(2026, 10, 1),
        query: ' AUGUST ',
        newestFirst: false,
      );
      expect(result.map((r) => r.receiptNo), ['start', 'end']);
      expect(receipts.first.receiptNo, 'before');
      expect(
        filterPaymentHistory(receipts, query: 'START').single.receiptNo,
        'start',
      );
      expect(filterPaymentHistory(receipts, query: 'missing'), isEmpty);
    },
  );

  test(
    'no date filter returns all transactions including repeated bill payments',
    () {
      expect(filterPaymentHistory(receipts), hasLength(4));
      expect(filterPaymentHistory(receipts).first.receiptNo, 'after');
      expect(
        filterPaymentHistory(receipts, newestFirst: false).first.receiptNo,
        'before',
      );
    },
  );
}
