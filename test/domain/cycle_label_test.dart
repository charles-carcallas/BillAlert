import 'package:billalert/domain/entities/bill.dart';
import 'package:billalert/domain/value_objects/cycle_label.dart';
import 'package:billalert/domain/value_objects/money.dart';
import 'package:billalert/domain/value_objects/ph_date.dart';
import 'package:flutter_test/flutter_test.dart';

/// A cycle label reaches the app in two different spellings, and for a while
/// it only understood one of them. These tests exist because of that bug.
void main() {
  group('parsing the two forms a cycle label arrives in', () {
    test('the device form, "2026-09"', () {
      final cycle = CycleLabel.tryParse('2026-09');

      expect(cycle, const CycleLabel(2026, 9));
    });

    test('the Supabase view form, "September 2026"', () {
      // REGRESSION. Every view spells cycle_label with
      // to_char(period_start, 'FMMonth YYYY'). Before this parsed, every bill
      // read from a view fell through to a fallback and showed January 1970 -
      // silently, on the consumer's own bill screen.
      final cycle = CycleLabel.tryParse('September 2026');

      expect(cycle, const CycleLabel(2026, 9));
    });

    test('month names are matched whatever their case', () {
      expect(CycleLabel.tryParse('august 2026'), const CycleLabel(2026, 8));
      expect(CycleLabel.tryParse('AUGUST 2026'), const CycleLabel(2026, 8));
    });

    test('every month name round trips through its own display form', () {
      for (var month = 1; month <= 12; month++) {
        final original = CycleLabel(2026, month);

        expect(
          CycleLabel.tryParse(original.displayName),
          original,
          reason: 'failed for ${original.displayName}',
        );
      }
    });

    test('refuses text that is not a cycle at all', () {
      expect(CycleLabel.tryParse(''), isNull);
      expect(CycleLabel.tryParse('Smarch 2026'), isNull);
      expect(CycleLabel.tryParse('August'), isNull);
      expect(CycleLabel.tryParse('2026-13'), isNull);
    });
  });

  group('Bill.fromJson against the rows the views really return', () {
    test('a v_readings_awaiting_amount row is an unpriced bill', () {
      // The Admin queue. The view has no total_amount, due_date or
      // amount_paid column at all, because these bills have none yet.
      final bill = Bill.fromJson(<String, dynamic>{
        'bill_id': 'bill-1',
        'bill_no': 'BA-202608-000123',
        'consumer_id': 'consumer-1',
        'cycle_label': 'August 2026',
        'consumption': '58.00',
      });

      expect(bill.cycle, const CycleLabel(2026, 8));
      expect(bill.isUnpriced, isTrue);
      expect(bill.isPayable, isFalse);
      expect(bill.totalAmount, isNull);
      expect(bill.consumption.format(), '58.00 kWh');
      // Nothing is owed on a reading the cooperative has not priced.
      expect(bill.balance, Money.zero);
    });

    test('a priced v_consumer_current_bill row keeps its amount exactly', () {
      final bill = Bill.fromJson(<String, dynamic>{
        'bill_id': 'bill-2',
        'bill_no': 'BA-202608-000124',
        'consumer_id': 'consumer-1',
        'cycle_label': 'August 2026',
        'consumption': '58.00',
        'total_amount': '658.30',
        'due_date': '2026-09-15',
        'amount_paid': '100.00',
      });

      expect(bill.isUnpriced, isFalse);
      expect(bill.totalAmount, Money.of(658, 30));
      expect(bill.amountPaid, Money.of(100));
      expect(bill.balance, Money.of(558, 30));
      expect(bill.dueDate?.toIso(), '2026-09-15');
      expect(bill.isPartiallyPaid, isTrue);
    });

    test('an unpriced bill reads as awaiting an amount, whatever day it is', () {
      final unpriced = Bill.fromJson(<String, dynamic>{
        'bill_id': 'bill-3',
        'bill_no': 'BA-202608-000125',
        'consumer_id': 'consumer-1',
        'cycle_label': 'August 2026',
        'consumption': '58.00',
      });

      // An unpriced bill has no due date, so it can never be overdue - no
      // matter how long ago the reading was taken.
      expect(unpriced.statusLabelOn(const PhDate(2027, 1, 1)), 'Awaiting amount');
      expect(unpriced.isOverdueOn(const PhDate(2027, 1, 1)), isFalse);
    });
  });
}
