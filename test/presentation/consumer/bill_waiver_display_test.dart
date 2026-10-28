import 'package:billalert/domain/entities/bill.dart';
import 'package:billalert/domain/value_objects/ph_date.dart';
import 'package:billalert/presentation/common/settlement_panel.dart';
import 'package:billalert/presentation/consumer/bill_details_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('covered bill shows noncash coverage separately from cash', (
    tester,
  ) async {
    final bill = Bill.fromJson({
      'bill_id': 'bill',
      'bill_no': 'B-1',
      'consumer_id': 'household',
      'cycle_year': 2026,
      'cycle_month': 10,
      'consumption': 10,
      'total_amount': 530,
      'amount_paid': 0,
      'due_date': '2026-10-28',
      'waiver_amount': 530,
      'waiver_assignment_id': 'assignment',
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          householdSettlementsProvider.overrideWith((ref, id) async => []),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showConsumerBillDetails(
                  context,
                  bill: bill,
                  today: const PhDate(2026, 11, 1),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Covered by BOHECO'), findsWidgets);
    expect(find.text('Paid'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Payment received'),
      100,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('−₱530.00'), findsOneWidget);
    expect(find.text('Paid in full.'), findsNothing);
  });
}
