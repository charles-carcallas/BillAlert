import 'package:billalert/data/local/app_database.dart';
import 'package:billalert/data/network/network_status.dart';
import 'package:billalert/data/repositories/overdue_repository.dart';
import 'package:billalert/data/repositories/settlement_repository.dart';
import 'package:billalert/domain/entities/app_user.dart';
import 'package:billalert/domain/entities/bill.dart';
import 'package:billalert/domain/repositories/bill_repository.dart';
import 'package:billalert/domain/value_objects/ids.dart';
import 'package:billalert/domain/value_objects/money.dart';
import 'package:billalert/domain/value_objects/ph_date.dart';
import 'package:billalert/presentation/auth/auth_controller.dart';
import 'package:billalert/presentation/auth/linked_household_provider.dart';
import 'package:billalert/presentation/cashier/record_payment_screen.dart';
import 'package:billalert/presentation/common/overdue_screen.dart';
import 'package:billalert/presentation/common/saved_list_time.dart';
import 'package:billalert/presentation/common/settlement_panel.dart';
import 'package:billalert/presentation/providers.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../support/fakes.dart';

Bill bill(String id, int month, {String home = 'home'}) => Bill.fromJson({
  'bill_id': id,
  'bill_no': id,
  'consumer_id': home,
  'cycle_year': 2026,
  'cycle_month': month,
  'total_amount': 350,
  'amount_paid': 0,
  'due_date': month == 10 ? '2026-10-28' : '2026-09-28',
});

void main() {
  late AppDatabase db;
  late SupabaseClient client;
  late NetworkStatus network;
  late FakeBillRepository bills;
  late List<http.Request> requests;
  late List<OverdueBill> overdue;
  String route = 'boheco', status = 'referred';
  const home = ConsumerOutstanding(
    consumerId: ConsumerId('home'),
    consumerNo: ConsumerNumber('QA-HOME'),
    consumerName: 'Test Household',
    payableBillCount: 1,
    unpricedBillCount: 0,
    overdueCount: 2,
    totalOutstanding: Money.fromCentavos(35000),
  );
  setUp(() {
    route = 'boheco';
    status = 'referred';
    db = AppDatabase.forTesting(NativeDatabase.memory());
    network = NetworkStatus(
      linkChanges: const Stream.empty(),
      checkLink: () async => true,
    );
    requests = [];
    overdue = [
      for (final b in [bill('old-one', 8), bill('old-two', 9)])
        OverdueBill(
          b,
          'Test Household · QA-HOME',
          null,
          null,
          consumerNo: 'QA-HOME',
          consumerName: 'Test Household',
        ),
      OverdueBill(
        bill('other', 9, home: 'other-home'),
        'Other household',
        null,
        null,
      ),
    ];
    bills = FakeBillRepository()
      ..outstanding = [home]
      ..payableBills = [
        bill('old-one', 8),
        bill('old-two', 9),
        bill('current', 10),
      ];
    client = SupabaseClient(
      'https://example.invalid',
      'test',
      httpClient: MockClient((request) async {
        requests.add(request);
        overdue = overdue
            .map(
              (r) => r.bill.consumerId.value == 'home'
                  ? OverdueBill(
                      r.bill,
                      r.household,
                      'requested',
                      '350',
                      consumerNo: r.consumerNo,
                      consumerName: r.consumerName,
                    )
                  : r,
            )
            .toList();
        return http.Response('', 204, request: request);
      }),
    );
  });
  tearDown(() async {
    network.dispose();
    await client.dispose();
    await db.close();
  });
  Future<void> pump(WidgetTester tester, {double width = 390}) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(
            () => FakeAuthController(
              signedInUser: const CashierUser(
                id: ProfileId('cashier'),
                username: 'cashier',
                firstName: 'Test',
                lastName: 'Cashier',
                areaId: AreaId('area'),
                mustChangePassword: false,
              ),
            ),
          ),
          settlementSnapshotProvider.overrideWith(
            (ref) async => SettlementSnapshot({
              'bills': [
                for (final r in overdue)
                  {'bill_id': r.bill.id.value, 'state': status, 'route': route},
              ],
            }),
          ),
          linkedHouseholdProvider.overrideWith((ref) async => null),
          billRepositoryProvider.overrideWithValue(bills),
          overdueBillsProvider.overrideWith((ref) async => overdue),
          overdueRepositoryProvider.overrideWithValue(
            OverdueRepository(client, db),
          ),
          networkStatusProvider.overrideWithValue(network),
          phClockProvider.overrideWithValue(
            FixedPhClock.onPhDate(const PhDate(2026, 10, 4)),
          ),
          savedListTimeProvider.overrideWith((ref, key) => Stream.value(null)),
        ],
        child: const MaterialApp(home: RecordPaymentScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'unpaid overdue debt opens payment routing instead of current collection',
    (tester) async {
      await pump(tester);
      await tester.tap(find.text('Test Household'));
      await tester.pumpAndSettle();
      expect(find.text('CASH RECEIVED'), findsNothing);
      expect(find.text('Request authorization'), findsNothing);
      expect(find.text('Pay directly at BOHECO'), findsNWidgets(2));
      expect(find.text('Other household'), findsNothing);
      expect(requests, isEmpty);
    },
  );
  testWidgets(
    'direct BOHECO route is readable on a narrow phone without a cashier payment',
    (tester) async {
      bills.outstanding = [];
      await pump(tester, width: 320);
      await tester.tap(find.text('Pay at BOHECO'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Test Household'));
      await tester.pumpAndSettle();
      expect(find.text('Pay directly at BOHECO'), findsNWidgets(2));
      expect(find.text('Collect full payment'), findsNothing);
      expect(tester.takeException(), isNull);
      expect(requests, isEmpty);
    },
  );
  testWidgets(
    'covered tab excludes direct bills and gates repayment until verified',
    (tester) async {
      route = 'pondo';
      status = 'handed_over';
      await pump(tester, width: 320);
      await tester.tap(find.text('Pay at BOHECO'));
      await tester.pumpAndSettle();
      expect(find.text('Test Household'), findsNothing);
      await tester.tap(find.text('Covered bills'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Test Household'));
      await tester.pumpAndSettle();
      expect(find.text('Collect repayment'), findsNothing);
      expect(find.text('Reserve fund with Meter Reader'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('verified covered bills offer full repayment', (tester) async {
    route = 'pondo';
    status = 'awaiting_repayment';
    await pump(tester);
    await tester.tap(find.text('Covered bills'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Test Household'));
    await tester.pumpAndSettle();
    expect(find.text('Collect repayment'), findsNWidgets(2));
    expect(requests, isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final dismiss in ['Cancel', 'back']) {
    testWidgets('focused repayment dialog safely closes using $dismiss', (
      tester,
    ) async {
      route = 'pondo';
      status = 'awaiting_repayment';
      await pump(tester);
      await tester.tap(find.text('Covered bills'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Test Household'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Collect repayment').first);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        '350',
      );
      if (dismiss == 'Cancel') {
        await tester.tap(find.text('Cancel'));
      } else {
        Navigator.of(tester.element(find.byType(AlertDialog))).pop();
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(AlertDialog), findsNothing);
      expect(requests, isEmpty);
    });
  }
}
