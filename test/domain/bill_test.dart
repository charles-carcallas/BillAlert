import 'package:billalert/domain/entities/bill.dart';
import 'package:billalert/domain/value_objects/cycle_label.dart';
import 'package:billalert/domain/value_objects/ids.dart';
import 'package:billalert/domain/value_objects/kwh.dart';
import 'package:billalert/domain/value_objects/money.dart';
import 'package:billalert/domain/value_objects/ph_date.dart';
import 'package:flutter_test/flutter_test.dart';

/// A bill as the meter reader's reading created it: consumption recorded,
/// no amount, no due date. This is what every bill looks like for about a
/// week.
Bill unpricedBill() => Bill(
      id: const BillId('bill-1'),
      billNo: const BillNumber('BA-202609-000123'),
      consumerId: const ConsumerId('consumer-1'),
      cycle: const CycleLabel(2026, 9),
      consumption: Kwh.of(142),
      totalAmount: null,
      dueDate: null,
    );

/// The same bill after the Area President posted the cooperative's figure.
Bill pricedBill({Money? paid}) => Bill(
      id: const BillId('bill-1'),
      billNo: const BillNumber('BA-202609-000123'),
      consumerId: const ConsumerId('consumer-1'),
      cycle: const CycleLabel(2026, 9),
      consumption: Kwh.of(142),
      totalAmount: Money.parse('658.30'),
      dueDate: const PhDate(2026, 9, 30),
      amountPaid: paid ?? Money.zero,
    );

void main() {
  group('unpriced - the seven day window', () {
    test('a new bill has no amount and is not payable', () {
      final bill = unpricedBill();
      expect(bill.isUnpriced, isTrue);
      expect(bill.isPayable, isFalse);
      expect(bill.isSettled, isFalse);
    });

    test('nothing is owed on a reading the cooperative has not priced', () {
      expect(unpricedBill().balance, Money.zero);
    });

    test('an unpriced bill is never overdue, whatever the date', () {
      // It has no due date to be past.
      expect(unpricedBill().isOverdueOn(const PhDate(2027, 1, 1)), isFalse);
      expect(unpricedBill().daysOverdueOn(const PhDate(2027, 1, 1)), 0);
    });

    test('the consumer still sees the consumption', () {
      expect(unpricedBill().consumption, Kwh.of(142));
    });

    test('the status reads as waiting, not as unpaid', () {
      expect(
        unpricedBill().statusLabelOn(const PhDate(2026, 9, 15)),
        'Awaiting amount',
      );
    });
  });

  group('payable', () {
    test('posting an amount makes it payable', () {
      final bill = pricedBill();
      expect(bill.isUnpriced, isFalse);
      expect(bill.isPayable, isTrue);
      expect(bill.balance, Money.parse('658.30'));
    });

    test('a part payment leaves the rest owing', () {
      final bill = pricedBill(paid: Money.parse('200.00'));
      expect(bill.isPartiallyPaid, isTrue);
      expect(bill.isSettled, isFalse);
      expect(bill.balance, Money.parse('458.30'));
      expect(
        bill.statusLabelOn(const PhDate(2026, 9, 15)),
        'Partially paid',
      );
    });

    test('paying it in full settles it', () {
      final bill = pricedBill(paid: Money.parse('658.30'));
      expect(bill.isSettled, isTrue);
      expect(bill.isPartiallyPaid, isFalse);
      expect(bill.balance, Money.zero);
    });

    test('overpaying still counts as settled', () {
      expect(pricedBill(paid: Money.parse('700.00')).isSettled, isTrue);
    });
  });

  group('overdue', () {
    test('not overdue on the due date itself', () {
      // Due 30 September means the consumer has all of 30 September to pay.
      expect(pricedBill().isOverdueOn(const PhDate(2026, 9, 30)), isFalse);
    });

    test('overdue the day after', () {
      final bill = pricedBill();
      expect(bill.isOverdueOn(const PhDate(2026, 10, 1)), isTrue);
      expect(bill.daysOverdueOn(const PhDate(2026, 10, 8)), 8);
      expect(bill.statusLabelOn(const PhDate(2026, 10, 1)), 'Overdue');
    });

    test('a settled bill is never overdue', () {
      final bill = pricedBill(paid: Money.parse('658.30'));
      expect(bill.isOverdueOn(const PhDate(2026, 12, 25)), isFalse);
      expect(bill.statusLabelOn(const PhDate(2026, 12, 25)), 'Paid');
    });
  });
}
