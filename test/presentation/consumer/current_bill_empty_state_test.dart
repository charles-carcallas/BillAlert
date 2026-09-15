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

void main() {
  const consumer = ConsumerUser(
    id: ProfileId('profile-consumer'),
    username: 'virgilio.busalanan',
    firstName: 'Virgilio',
    lastName: 'Busalanan',
    mustChangePassword: false,
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

  testWidgets('a paid-up account keeps an empty amount card', (tester) async {
    const paid = Bill(
      id: BillId('bill-july'),
      billNo: BillNumber('BA-202607-000001'),
      consumerId: ConsumerId('consumer-1'),
      cycle: CycleLabel(2026, 7),
      consumption: Kwh.fromHundredths(6000),
      totalAmount: Money.fromCentavos(120000),
      dueDate: PhDate(2026, 8, 25),
      amountPaid: Money.fromCentavos(120000),
    );

    await pumpState(tester, const CurrentBillState(history: <Bill>[paid]));

    expect(find.text('Amount due'), findsOneWidget);
    expect(find.text('₱0.00'), findsNothing);
    expect(find.text('No payment needed'), findsOneWidget);
    expect(find.text('You’re all caught up'), findsOneWidget);
    expect(find.text('Latest paid bill · July 2026'), findsOneWidget);
    expect(find.text('View billing history'), findsOneWidget);
  });

  testWidgets('an account with no bills does not pretend it is paid up', (
    tester,
  ) async {
    await pumpState(tester, const CurrentBillState());

    expect(find.text('Amount due'), findsOneWidget);
    expect(find.text('₱0.00'), findsNothing);
    expect(find.text('No current bill'), findsOneWidget);
    expect(find.text('No current bill yet'), findsOneWidget);
    expect(find.text('You’re all caught up'), findsNothing);
  });
}
