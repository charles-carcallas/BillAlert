import 'package:billalert/domain/entities/app_user.dart';
import 'package:billalert/domain/entities/bill.dart';
import 'package:billalert/domain/value_objects/cycle_label.dart';
import 'package:billalert/domain/value_objects/ids.dart';
import 'package:billalert/domain/value_objects/kwh.dart';
import 'package:billalert/domain/value_objects/money.dart';
import 'package:billalert/domain/value_objects/ph_date.dart';
import 'package:billalert/presentation/auth/auth_controller.dart';
import 'package:billalert/presentation/consumer/current_bill_controller.dart';
import 'package:billalert/presentation/consumer/current_bill_screen.dart';
import 'package:billalert/presentation/consumer/inbox_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';

class _FixedCurrentBillController extends CurrentBillController {
  final CurrentBillState fixed;

  _FixedCurrentBillController(this.fixed);

  @override
  CurrentBillState build() => fixed;
}

class _FixedInboxController extends InboxController {
  @override
  InboxState build() => const InboxState();
}

/// The Bills tab used to lead with one month's balance. A household with an
/// unpaid July and a priced August was told it owed only August, and the July
/// debt was visible only by scrolling History.
void main() {
  const consumer = ConsumerUser(
    id: ProfileId('profile-elena'),
    username: 'elena.montano',
    firstName: 'Elena',
    lastName: 'Montano',
    mustChangePassword: false,
  );

  const Bill july = Bill(
    id: BillId('bill-july'),
    billNo: BillNumber('BA-202607-000902'),
    consumerId: ConsumerId('consumer-elena'),
    cycle: CycleLabel(2026, 7),
    consumption: Kwh.fromHundredths(5900),
    totalAmount: Money.fromCentavos(54120),
    dueDate: PhDate(2026, 8, 28),
  );

  const Bill august = Bill(
    id: BillId('bill-august'),
    billNo: BillNumber('BA-202608-000902'),
    consumerId: ConsumerId('consumer-elena'),
    cycle: CycleLabel(2026, 8),
    consumption: Kwh.fromHundredths(6700),
    totalAmount: Money.fromCentavos(100500),
    dueDate: PhDate(2026, 9, 28),
  );

  Future<void> pumpState(WidgetTester tester, CurrentBillState state) async {
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(
          () => FakeAuthController(signedInUser: consumer),
        ),
        currentBillControllerProvider.overrideWith(
          () => _FixedCurrentBillController(state),
        ),
        inboxControllerProvider.overrideWith(_FixedInboxController.new),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: CurrentBillScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('an older unpaid bill is added into the headline total', (
    tester,
  ) async {
    await pumpState(
      tester,
      const CurrentBillState(
        currentBill: august,
        history: <Bill>[august, july],
      ),
    );

    // ₱1,005.00 + ₱541.20. The household is told what it owes, not what one
    // month of it costs.
    expect(find.text('Total amount unpaid'), findsOneWidget);
    expect(find.text('₱1,546.20'), findsOneWidget);
    expect(find.text('Amount due'), findsNothing);

    // And where the total came from, so it is never unaccountable.
    expect(find.text('August 2026 (this bill)'), findsOneWidget);
    expect(find.text('₱1,005.00'), findsOneWidget);
    expect(find.text('July 2026 (unpaid)'), findsOneWidget);
    expect(find.text('₱541.20'), findsOneWidget);
  });

  testWidgets('a single unpaid bill keeps the simpler wording', (tester) async {
    await pumpState(
      tester,
      const CurrentBillState(currentBill: august, history: <Bill>[august]),
    );

    // Nothing older is owed, so "Amount due" is the whole truth and a
    // breakdown would only repeat the figure above it.
    expect(find.text('Amount due'), findsOneWidget);
    expect(find.text('Total amount unpaid'), findsNothing);
    expect(find.text('₱1,005.00'), findsOneWidget);
    expect(find.text('August 2026 (this bill)'), findsNothing);
  });

  testWidgets('an unpriced month still shows what is owed from before', (
    tester,
  ) async {
    const Bill september = Bill(
      id: BillId('bill-september'),
      billNo: BillNumber('BA-202609-000902'),
      consumerId: ConsumerId('consumer-elena'),
      cycle: CycleLabel(2026, 9),
      consumption: Kwh.fromHundredths(7100),
      totalAmount: null,
      dueDate: null,
    );

    await pumpState(
      tester,
      const CurrentBillState(
        currentBill: september,
        history: <Bill>[september, july],
      ),
    );

    // The current month has no amount, but July is still owed — so the
    // screen must not answer "Amount pending" and leave it at that.
    expect(find.text('Total amount unpaid'), findsOneWidget);
    expect(find.text('₱541.20'), findsWidgets);
    expect(find.text('Amount pending'), findsNothing);
    expect(find.text('September 2026 (awaiting amount)'), findsOneWidget);
    expect(find.text('Not posted yet'), findsOneWidget);
  });

  testWidgets('a settled older bill is not counted', (tester) async {
    const Bill paidJuly = Bill(
      id: BillId('bill-july'),
      billNo: BillNumber('BA-202607-000902'),
      consumerId: ConsumerId('consumer-elena'),
      cycle: CycleLabel(2026, 7),
      consumption: Kwh.fromHundredths(5900),
      totalAmount: Money.fromCentavos(54120),
      dueDate: PhDate(2026, 8, 28),
      amountPaid: Money.fromCentavos(54120),
    );

    await pumpState(
      tester,
      const CurrentBillState(
        currentBill: august,
        history: <Bill>[august, paidJuly],
      ),
    );

    expect(find.text('Amount due'), findsOneWidget);
    expect(find.text('₱1,005.00'), findsOneWidget);
    expect(find.text('July 2026 (unpaid)'), findsNothing);
  });
}
