import 'package:billalert/domain/entities/bill.dart';
import 'package:billalert/domain/value_objects/ph_date.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, dynamic> row() => {
    'bill_id': 'bill',
    'bill_no': 'B-1',
    'consumer_id': 'household',
    'cycle_year': 2026,
    'cycle_month': 10,
    'consumption': 40,
    'total_amount': 530,
    'amount_paid': 0,
    'due_date': '2026-10-28',
    'waiver_amount': 530,
    'waiver_assignment_id': 'assignment',
    'waived_at': '2026-10-02T04:00:00Z',
  };
  test('full BOHECO coverage is settled without inventing cash', () {
    final bill = Bill.fromJson(row());
    expect(bill.isWaived, isTrue);
    expect(bill.isSettled, isTrue);
    expect(bill.isPayable, isFalse);
    expect(bill.amountPaid.isZero, isTrue);
    expect(bill.balance.isZero, isTrue);
    expect(bill.isOverdueOn(const PhDate(2026, 11, 1)), isFalse);
    expect(bill.statusLabelOn(const PhDate(2026, 11, 1)), 'Covered by BOHECO');
    expect(bill.waiverAssignmentId, 'assignment');
  });
  test('ordinary existing bill retains debt and overdue state', () {
    final json = row()
      ..remove('waiver_amount')
      ..remove('waiver_assignment_id')
      ..remove('waived_at');
    final bill = Bill.fromJson(json);
    expect(bill.isWaived, isFalse);
    expect(bill.isSettled, isFalse);
    expect(bill.balance.centavos, 53000);
    expect(bill.statusLabelOn(const PhDate(2026, 11, 1)), 'Overdue');
  });
}
