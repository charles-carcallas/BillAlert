import 'package:billalert/core/errors/app_failure.dart';
import 'package:billalert/domain/entities/app_user.dart';
import 'package:billalert/domain/repositories/bill_repository.dart';
import 'package:billalert/domain/repositories/payment_repository.dart';
import 'package:billalert/domain/value_objects/ids.dart';
import 'package:billalert/domain/value_objects/money.dart';
import 'package:billalert/presentation/auth/auth_controller.dart';
import 'package:billalert/presentation/auth/linked_household_provider.dart';
import 'package:billalert/presentation/cashier/receipts_controller.dart';
import 'package:billalert/presentation/cashier/receipts_screen.dart';
import 'package:billalert/presentation/cashier/record_payment_screen.dart';
import 'package:billalert/presentation/common/failure_banner.dart';
import 'package:billalert/presentation/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';

class _FixedReceipts extends ReceiptsController {
  final ReceiptsState fixed;
  _FixedReceipts(this.fixed);

  @override
  ReceiptsState build() => fixed;
}

void main() {
  const cashier = CashierUser(
    id: ProfileId('cashier'),
    username: 'test.cashier',
    firstName: 'Test',
    lastName: 'Cashier',
    areaId: AreaId('area'),
    mustChangePassword: false,
  );

  Future<void> pumpConsumers(
    WidgetTester tester,
    FakeBillRepository bills,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(
            () => FakeAuthController(signedInUser: cashier),
          ),
          linkedHouseholdProvider.overrideWith((ref) async => null),
          billRepositoryProvider.overrideWithValue(bills),
        ],
        child: const MaterialApp(home: RecordPaymentScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pumpReceipts(WidgetTester tester, ReceiptsState state) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(
            () => FakeAuthController(signedInUser: cashier),
          ),
          linkedHouseholdProvider.overrideWith((ref) async => null),
          receiptsControllerProvider.overrideWith(() => _FixedReceipts(state)),
        ],
        child: const MaterialApp(home: ReceiptsScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('empty collection refresh discovers a newly posted bill', (
    tester,
  ) async {
    final bills = FakeBillRepository();
    await pumpConsumers(tester, bills);
    expect(find.text('No bills to collect'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Covered bills'), findsOneWidget);

    bills.outstanding = const <ConsumerOutstanding>[
      ConsumerOutstanding(
        consumerId: ConsumerId('home'),
        consumerNo: ConsumerNumber('BETA-001'),
        consumerName: 'Test Household',
        payableBillCount: 1,
        unpricedBillCount: 0,
        overdueCount: 0,
        totalOutstanding: Money.fromCentavos(17500),
      ),
    ];
    await tester.tap(find.text('Refresh'));
    await tester.pumpAndSettle();
    expect(find.text('No bills to collect'), findsNothing);
    expect(find.text('Test Household'), findsOneWidget);
    expect(find.text('₱175.00'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'unknown');
    await tester.pump();
    expect(find.text('No household matches that search.'), findsOneWidget);
    expect(find.text('No bills to collect'), findsNothing);
  });

  testWidgets('current balance and overdue blocker fit a narrow phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final bills = FakeBillRepository()
      ..outstanding = const [
        ConsumerOutstanding(
          consumerId: ConsumerId('mixed'),
          consumerNo: ConsumerNumber('TEST-MIXED'),
          consumerName: 'Mixed Household',
          payableBillCount: 1,
          unpricedBillCount: 0,
          overdueCount: 1,
          totalOutstanding: Money.fromCentavos(25000),
        ),
      ];
    await pumpConsumers(tester, bills);
    expect(find.text('Settle overdue first'), findsOneWidget);
    expect(find.text('₱250.00'), findsOneWidget);
    expect(find.textContaining('₱250.00 this month'), findsOneWidget);
    expect(find.text('1 overdue'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an unavailable collection list does not claim no bills', (
    tester,
  ) async {
    final bills = FakeBillRepository()
      ..outstandingFailure = const NetworkFailure('No saved list available.');
    await pumpConsumers(tester, bills);
    expect(find.byType(FailureBanner), findsOneWidget);
    expect(find.text('No saved list available.'), findsOneWidget);
    expect(find.text('No bills to collect'), findsNothing);
  });

  testWidgets('unknown outstanding is not displayed as a zero balance', (
    tester,
  ) async {
    await pumpReceipts(tester, const ReceiptsState());
    expect(find.text("Today's collections"), findsOneWidget);
    expect(find.text('Still to collect'), findsNothing);
    expect(find.text('0 households'), findsNothing);
  });

  testWidgets('receipt summary keeps collected and outstanding separate', (
    tester,
  ) async {
    await pumpReceipts(
      tester,
      const ReceiptsState(
        today: CollectionSummary(
          receiptCount: 3,
          totalCollected: Money.fromCentavos(369715),
        ),
        outstanding: AreaOutstanding(
          total: Money.fromCentavos(120050),
          households: 2,
          overdueHouseholds: 1,
        ),
      ),
    );
    expect(find.text('₱3,697.15'), findsOneWidget);
    expect(find.text('₱1,200.50'), findsOneWidget);
    expect(find.text('3 receipts'), findsOneWidget);
    expect(find.text('2 households'), findsOneWidget);
    expect(find.text('1 overdue'), findsOneWidget);
    expect(find.text('₱4,897.65'), findsNothing);
  });
}
