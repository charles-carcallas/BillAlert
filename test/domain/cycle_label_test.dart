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

  group('CycleLabel.fromRow takes the most reliable form the row offers', () {
    test('the year and month integers win over everything else', () {
      // The label deliberately disagrees. If the integers are being used, the
      // label is never consulted and cannot drag the answer off.
      final cycle = CycleLabel.fromRow(<String, dynamic>{
        'cycle_year': 2026,
        'cycle_month': 8,
        'period_start': '2020-01-15',
        'cycle_label': 'March 1999',
      });

      expect(cycle, const CycleLabel(2026, 8));
    });

    test('period_start is used when the integers are absent', () {
      // v_consumer_current_bill has no cycle_year/cycle_month but does carry
      // period_start, which is an ISO date and so cannot be misread.
      final cycle = CycleLabel.fromRow(<String, dynamic>{
        'period_start': '2026-07-15',
        'cycle_label': 'March 1999',
      });

      expect(cycle, const CycleLabel(2026, 7));
    });

    test('the rendered label is the last resort', () {
      // v_readings_awaiting_amount offers nothing else.
      final cycle = CycleLabel.fromRow(<String, dynamic>{
        'cycle_label': 'August 2026',
      });

      expect(cycle, const CycleLabel(2026, 8));
    });

    test('a month outside 1-12 is not trusted', () {
      final cycle = CycleLabel.fromRow(<String, dynamic>{
        'cycle_year': 2026,
        'cycle_month': 13,
        'cycle_label': 'August 2026',
      });

      expect(cycle, const CycleLabel(2026, 8), reason: 'falls through to the label');
    });

    test('a row carrying no cycle at all returns null', () {
      expect(CycleLabel.fromRow(<String, dynamic>{'bill_no': 'BA-1'}), isNull);
    });
  });

  group('a bill row with no cycle is refused, not guessed', () {
    test('Bill.fromJson throws rather than inventing a date', () {
      // Before this, a row the parser could not read became January 1970 and
      // was rendered to the consumer as though it were real.
      expect(
        () => Bill.fromJson(<String, dynamic>{
          'bill_id': 'bill-9',
          'bill_no': 'BA-202608-000999',
          'consumer_id': 'consumer-1',
          'consumption': '58.00',
        }),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
