import 'package:billalert/domain/entities/app_user.dart';
import 'package:billalert/domain/entities/bill.dart';
import 'package:billalert/domain/entities/consumer.dart' as domain;
import 'package:billalert/domain/value_objects/cycle_label.dart';
import 'package:billalert/domain/value_objects/ids.dart';
import 'package:billalert/domain/value_objects/kwh.dart';
import 'package:billalert/domain/value_objects/money.dart';
import 'package:billalert/domain/value_objects/ph_date.dart';
import 'package:billalert/presentation/auth/auth_controller.dart';
import 'package:billalert/presentation/consumer/current_bill_controller.dart';
import 'package:billalert/presentation/consumer/current_bill_screen.dart';
import 'package:billalert/presentation/consumer/inbox_controller.dart';
import 'package:billalert/presentation/providers.dart';
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
        phClockProvider.overrideWithValue(
          FixedPhClock.onPhDate(const PhDate(2026, 10, 2)),
        ),
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

  testWidgets(
    'a paid-up account shows a single summary without an amount placeholder',
    (tester) async {
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

      expect(find.text('Amount due'), findsNothing);
      expect(find.text('₱0.00'), findsNothing);
      expect(
        find.byKey(const ValueKey('household-empty-bill')),
        findsOneWidget,
      );
      expect(find.text('You’re all caught up'), findsOneWidget);
      expect(find.text('Latest paid bill · July 2026'), findsOneWidget);
      expect(find.text('View billing history'), findsOneWidget);
    },
  );

  testWidgets('an account with no bills does not pretend it is paid up', (
    tester,
  ) async {
    await pumpState(tester, const CurrentBillState());

    expect(find.text('Amount due'), findsNothing);
    expect(find.text('₱0.00'), findsNothing);
    expect(find.text('No bill for October yet'), findsOneWidget);
    expect(find.byKey(const ValueKey('household-empty-bill')), findsOneWidget);
    expect(find.text('Covered by BOHECO'), findsNothing);
    expect(find.text('My household'), findsOneWidget);
    expect(find.text('You’re all caught up'), findsNothing);
  });

  testWidgets('loaded household details appear without another lookup', (
    tester,
  ) async {
    const home = domain.Consumer(
      id: ConsumerId('home'),
      consumerNo: ConsumerNumber('BETA-001'),
      firstName: 'Test',
      lastName: 'Household',
      areaId: AreaId('area'),
      accountStatus: domain.AccountStatus.active,
      previousReading: Kwh.zero,
      meterSerialNo: 'METER-001',
    );
    final consumers = FakeConsumerRepository([])..me = home;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(
            () => FakeAuthController(signedInUser: consumer),
          ),
          consumerRepositoryProvider.overrideWithValue(consumers),
          billRepositoryProvider.overrideWithValue(FakeBillRepository()),
          inboxControllerProvider.overrideWith(_FixedInboxController.new),
          phClockProvider.overrideWithValue(
            FixedPhClock.onPhDate(const PhDate(2026, 10, 2)),
          ),
        ],
        child: const MaterialApp(home: CurrentBillScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Consumer no. BETA-001'), findsOneWidget);
    expect(find.text('Meter METER-001'), findsOneWidget);
    expect(find.text('No bill for October yet'), findsOneWidget);
  });

  const covered = Bill(
    id: BillId('bill-october'),
    billNo: BillNumber('BA-202610-000001'),
    consumerId: ConsumerId('consumer-1'),
    cycle: CycleLabel(2026, 10),
    consumption: Kwh.fromHundredths(6000),
    totalAmount: Money.fromCentavos(53000),
    dueDate: PhDate(2026, 10, 28),
    waiverAmount: Money.fromCentavos(53000),
    waiverAssignmentId: 'recorded-coverage',
  );

  testWidgets('current-month recorded coverage shows a zero balance', (
    tester,
  ) async {
    await pumpState(tester, const CurrentBillState(history: [covered]));
    expect(find.text('Covered by BOHECO'), findsOneWidget);
    expect(find.text('₱0.00'), findsOneWidget);
    expect(find.text('BOHECO coverage'), findsOneWidget);
    expect(find.text('₱530.00'), findsOneWidget);
    expect(find.text('October 2026'), findsOneWidget);
    expect(find.byKey(const ValueKey('household-empty-bill')), findsNothing);
  });

  testWidgets('coverage of this month preserves an older unpaid balance', (
    tester,
  ) async {
    const older = Bill(
      id: BillId('bill-september'),
      billNo: BillNumber('BA-202609-000001'),
      consumerId: ConsumerId('consumer-1'),
      cycle: CycleLabel(2026, 9),
      consumption: Kwh.fromHundredths(4000),
      totalAmount: Money.fromCentavos(20000),
      dueDate: PhDate(2026, 9, 28),
    );
    await pumpState(
      tester,
      const CurrentBillState(currentBill: older, history: [covered, older]),
    );
    expect(find.text('Covered by BOHECO'), findsOneWidget);
    expect(find.text('Total amount unpaid'), findsOneWidget);
    expect(find.text('₱200.00'), findsWidgets);
    expect(find.text('September 2026 (unpaid)'), findsOneWidget);
    expect(find.text('October 2026 (this bill)'), findsOneWidget);
  });
}
