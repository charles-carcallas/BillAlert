import 'package:billalert/data/local/pending_fund_request.dart';
import 'package:billalert/data/network/network_status.dart';
import 'package:billalert/data/repositories/settlement_repository.dart';
import 'package:billalert/domain/entities/app_user.dart';
import 'package:billalert/domain/entities/bill.dart';
import 'package:billalert/domain/value_objects/cycle_label.dart';
import 'package:billalert/domain/value_objects/ids.dart';
import 'package:billalert/domain/value_objects/money.dart';
import 'package:billalert/domain/value_objects/ph_date.dart';
import 'package:billalert/presentation/auth/auth_controller.dart';
import 'package:billalert/presentation/common/settlement_panel.dart';
import 'package:billalert/presentation/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../support/fakes.dart';

class Trips implements SettlementRepository {
  PendingFundRequest? pending;
  String? lastEntryUuid;
  @override
  Future<PendingFundRequest?> pendingEntry(String owner) async => pending;
  final calls = <String>[];
  List<Map<String, dynamic>> selected = [];
  @override
  Future<void> correct(
    String bill,
    String reason, {
    required String action,
    required String updatedAt,
    required String uuid,
  }) async {
    calls.add('correct:$bill:$action:$updatedAt:$reason');
  }

  @override
  Future<void> completeTrip(String trip, List<String> bills) async {
    calls.add('complete:$trip:${bills.join(',')}');
  }

  @override
  Future<void> payCompensation(String month, String reader) async {
    calls.add('compensation:$month:$reader');
  }

  @override
  Future<void> entry(
    Money value,
    String kind,
    String reason,
    String uuid, {
    required String owner,
  }) async {
    lastEntryUuid = uuid;
    pending = null;
    calls.add('$kind:${value.centavos}:$reason');
  }

  @override
  Future<void> allocate(
    String trip,
    List<Map<String, dynamic>> bills,
    String reader,
  ) async {
    calls.add('$trip:$reader');
    selected = bills;
  }

  @override
  Future<void> close(String month) async {
    calls.add(month);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const admin = AdminUser(
    id: ProfileId('admin'),
    username: 'admin',
    firstName: 'Test',
    lastName: 'Admin',
    areaId: AreaId('area'),
    mustChangePassword: false,
  );
  const cashier = CashierUser(
    id: ProfileId('cashier'),
    username: 'cashier',
    firstName: 'Test',
    lastName: 'Cashier',
    areaId: AreaId('area'),
    mustChangePassword: false,
  );
  const reader = MeterReaderUser(
    id: ProfileId('reader'),
    username: 'reader',
    firstName: 'Test',
    lastName: 'Reader',
    areaId: AreaId('area'),
    mustChangePassword: false,
  );
  late NetworkStatus network;
  late Trips repository;
  setUp(() {
    network = NetworkStatus(
      linkChanges: const Stream.empty(),
      checkLink: () async => true,
    );
    repository = Trips();
  });
  tearDown(() => network.dispose());
  Future<void> open(
    WidgetTester tester,
    AppUser user, {
    int available = 1000,
    String state = 'review',
    String tripMonth = '2026-09-01',
    bool secondTrip = false,
    bool compensation = false,
    bool paid = false,
  }) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(
            () => FakeAuthController(signedInUser: user),
          ),
          phClockProvider.overrideWithValue(
            FixedPhClock.onPhDate(const PhDate(2026, 10, 4)),
          ),
          networkStatusProvider.overrideWithValue(network),
          settlementRepositoryProvider.overrideWithValue(repository),
          settlementSnapshotProvider.overrideWith(
            (ref) async => SettlementSnapshot({
              'available': available,
              if (compensation) ...{
                'coverage_available': available - (paid ? 0 : 500),
                'compensation_reserved': paid ? 0 : 500,
                'compensation_months': [
                  {
                    'month': '2026-10-01',
                    'id': paid ? 'payout' : null,
                    'reader_name': 'Test Reader',
                  },
                ],
              },
              'trips': [
                {'id': 'trip', 'trip_month': tripMonth},
                if (secondTrip) {'id': 'older', 'trip_month': '2026-08-01'},
              ],
              'readers': [
                {'id': 'reader', 'name': 'Test Reader'},
              ],
              'bills': [
                for (final id in ['small', 'large'])
                  {
                    'trip_id': 'trip',
                    'bill_id': id,
                    'consumer_name': id,
                    'consumer_no': id,
                    'boheco_amount': id == 'small' ? 249.40 : 349.40,
                    'consumer_amount': id == 'small' ? 250 : 350,
                    'state': state,
                    'updated_at': '2026-10-04T04:00:00Z',
                    'route': state == 'awaiting_referral' ? 'boheco' : 'pondo',
                  },
              ],
            }),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: SettlementPanel(month: CycleLabel(2026, 10)),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Cashier payout takes one confirmation and blocks insufficient cash',
    (tester) async {
      await open(tester, cashier, compensation: true, available: 499);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Record ₱500 payout'),
            )
            .onPressed,
        isNull,
      );
      expect(repository.calls, isEmpty);
    },
  );
  testWidgets('Cashier confirms monthly payout without amount entry', (
    tester,
  ) async {
    await open(tester, cashier, compensation: true);
    await tester.ensureVisible(find.text('Record ₱500 payout'));
    await tester.tap(find.text('Record ₱500 payout'));
    await tester.pumpAndSettle();
    expect(repository.calls, isEmpty);
    expect(find.textContaining('₱500 handed to Test Reader'), findsOneWidget);
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(repository.calls, ['compensation:2026-10-01:reader']);
    expect(tester.takeException(), isNull);
  });
  testWidgets('paid month has no second payout action', (tester) async {
    await open(tester, cashier, compensation: true, paid: true);
    expect(find.text('Record ₱500 payout'), findsNothing);
    expect(find.text('Paid · Test Reader'), findsOneWidget);
  });
  testWidgets(
    'pending fund entry offers original request instead of a new money form',
    (tester) async {
      repository.pending = const PendingFundRequest(
        '100.00',
        'contribution',
        'Cash added',
        'original-id',
      );
      await open(tester, cashier);
      await tester.tap(find.text('Record reserve fund money'));
      await tester.pumpAndSettle();
      expect(find.text('Check previous fund entry?'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(repository.lastEntryUuid, 'original-id');
      expect(repository.calls, ['contribution:10000:Cash added']);
    },
  );
  testWidgets('Admin sees compact balances and collapsed allocation review', (
    tester,
  ) async {
    await open(tester, admin);
    expect(find.text('small'), findsNothing);
    expect(find.text('With Meter Reader'), findsNothing);
    await tester.tap(find.text('Balance details'));
    await tester.pumpAndSettle();
    expect(find.text('With Meter Reader'), findsOneWidget);
    await tester.tap(find.text('Awaiting Cashier allocation · 2'));
    await tester.pumpAndSettle();
    expect(find.text('small'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'one recorded trip still allows month selection and collapses households',
    (tester) async {
      await open(tester, reader);
      expect(find.text('September 2026'), findsOneWidget);
      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
      expect(find.text('Awaiting Cashier allocation · 2'), findsOneWidget);
      expect(find.text('small'), findsNothing);
      await tester.tap(find.text('Awaiting Cashier allocation · 2'));
      await tester.pumpAndSettle();
      expect(find.text('small'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('already closed current month cannot be closed again', (
    tester,
  ) async {
    await open(tester, reader, tripMonth: '2026-10-01');
    expect(find.text('Closed'), findsOneWidget);
    expect(find.text('Close collection · October 2026'), findsNothing);
    expect(repository.calls, isEmpty);
  });
  testWidgets(
    'empty month stays selected without showing another month bills',
    (tester) async {
      await open(tester, reader);
      final picker = find.byType(DropdownButtonFormField<String>);
      await tester.tap(picker);
      await tester.pumpAndSettle();
      await tester.tap(find.text('October 2026').last);
      await tester.pumpAndSettle();
      expect(find.text('Awaiting Cashier allocation · 2'), findsNothing);
      expect(
        find.text('No BOHECO trip bills recorded for this month.'),
        findsOneWidget,
      );
      await tester.pump();
      expect(find.text('October 2026'), findsOneWidget);
      expect(repository.calls, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'covered verification correction explicitly leaves cash with Reader',
    (tester) async {
      await open(tester, admin, state: 'awaiting_repayment');
      final button = find.text('Correct verification').first;
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('money stays with the Meter Reader'),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextField), 'Wrong receipt');
      await tester.tap(find.text('Confirm correction'));
      await tester.pumpAndSettle();
      expect(repository.calls, [
        'correct:small:reverse_verification:2026-10-04T04:00:00Z:Wrong receipt',
      ]);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('multiple recorded trips remain selectable by month name', (
    tester,
  ) async {
    await open(tester, reader, secondTrip: true);
    final picker = find.byType(DropdownButtonFormField<String>);
    expect(picker, findsOneWidget);
    await tester.tap(picker);
    await tester.pumpAndSettle();
    await tester.tap(find.text('August 2026').last);
    await tester.pumpAndSettle();
    expect(find.text('Awaiting Cashier allocation · 2'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Admin fund entry choices and buttons fit a narrow phone', (
    tester,
  ) async {
    await open(tester, admin);
    expect(find.text('Record reserve fund money'), findsNothing);
    await tester.tap(find.text('Balance details'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Correct balance'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(OutlinedButton),
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Correction'));
    await tester.pumpAndSettle();
    expect(find.text('Use + or − to adjust the balance.'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Cancel')).dy,
      closeTo(tester.getTopLeft(find.text('Save')).dy, 2),
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(repository.calls, isEmpty);
  });

  testWidgets('reserve form cancels safely while its closing animation runs', (
    tester,
  ) async {
    await open(tester, cashier);
    await tester.tap(find.text('Record reserve fund money'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(DropdownButtonFormField<String>),
      ),
      findsNothing,
    );
    await tester.tap(find.text('Opening balance').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '100');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(repository.calls, isEmpty);
  });
  testWidgets('reserve form saves safely and can reopen after cancellation', (
    tester,
  ) async {
    await open(tester, cashier);
    await tester.tap(find.text('Record reserve fund money'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Record reserve fund money'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '100');
    await tester.enterText(find.byType(TextField).last, 'Test contribution');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(repository.calls, ['contribution:10000:Test contribution']);
  });
  testWidgets(
    'BOHECO verification form cancels without disposing an active field',
    (tester) async {
      await open(tester, reader, state: 'handed_over');
      final button = find.text('Confirm reserve fund payment to BOHECO').first;
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'TEST-RECEIPT');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(repository.calls, isEmpty);
    },
  );
  testWidgets('returned-funds correction cancels safely', (tester) async {
    await open(tester, admin, state: 'handed_over');
    final button = find.text('Record returned funds').first;
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Test correction');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(repository.calls, isEmpty);
  });
  testWidgets('supply-status form cancels safely on a narrow phone', (
    tester,
  ) async {
    await open(tester, reader, state: 'settled');
    final settled = find.text('Settled bills');
    await tester.ensureVisible(settled);
    await tester.tap(settled);
    await tester.pumpAndSettle();
    final button = find.text('Supply status: unknown').first;
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Test evidence');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(repository.calls, isEmpty);
  });
  testWidgets('Cashier selects exact bills and confirms physical handover', (
    tester,
  ) async {
    await open(tester, cashier);
    expect(find.byType(CheckboxListTile), findsNothing);
    await tester.tap(find.text('Choose bills to cover · 2'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.pump();
    final button = find.widgetWithText(
      FilledButton,
      'Confirm allocation & handover',
    );
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(repository.calls, isEmpty);
    expect(
      find.textContaining('Confirm only after handing over the actual cash.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(repository.calls, ['trip:reader']);
    expect(repository.selected.single['bill_id'], 'small');
    expect(repository.selected.single['consumer_amount'], 250);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'insufficient reserve fund disables allocation on a narrow phone',
    (tester) async {
      await open(tester, cashier, available: 100);
      expect(find.byType(CheckboxListTile), findsNothing);
      await tester.tap(find.text('Choose bills to cover · 2'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(CheckboxListTile).first);
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(
                FilledButton,
                'Confirm allocation & handover',
              ),
            )
            .onPressed,
        isNull,
      );
      expect(repository.calls, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Reader closes trip once and cannot allocate or alter reserve fund',
    (tester) async {
      await open(tester, reader);
      expect(find.text('Record reserve fund money'), findsNothing);
      expect(find.byType(CheckboxListTile), findsNothing);
      await tester.tap(find.text('Close collection · October 2026'));
      await tester.pumpAndSettle();
      expect(repository.calls, isEmpty);
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(repository.calls, ['2026-10-01']);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('offline closure sends no financial request', (tester) async {
    await open(tester, reader);
    network.reportUnreachable();
    await tester.tap(find.text('Close collection · October 2026'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(repository.calls, isEmpty);
    expect(
      find.text('Connect to update reserve fund or BOHECO records.'),
      findsOneWidget,
    );
  });
  testWidgets('Reader reports the trip once with reviewed accounts', (
    tester,
  ) async {
    await open(tester, reader, state: 'awaiting_referral');
    expect(find.text('Confirm referral to BOHECO'), findsNothing);
    expect(find.text('Verify direct payment'), findsNWidgets(2));
    await tester.ensureVisible(find.text('Complete BOHECO trip'));
    await tester.tap(find.text('Complete BOHECO trip'));
    await tester.pumpAndSettle();
    expect(repository.calls, isEmpty);
    expect(find.textContaining('small (small)'), findsOneWidget);
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(repository.calls, ['complete:trip:small,large']);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Unrecorded handed-over money blocks trip completion', (
    tester,
  ) async {
    await open(tester, reader, state: 'handed_over');
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Complete BOHECO trip'),
    );
    expect(button.onPressed, isNull);
    expect(repository.calls, isEmpty);
  });
  testWidgets('Cashier cannot complete the Reader trip', (tester) async {
    await open(tester, cashier, state: 'awaiting_referral');
    expect(find.text('Complete BOHECO trip'), findsNothing);
    expect(find.text('Verify direct payment'), findsNothing);
  });
  test(
    'direct BOHECO settlement clears debt without creating cashier cash',
    () {
      final bill = Bill.fromJson({
        'bill_id': 'bill',
        'bill_no': 'bill',
        'consumer_id': 'home',
        'cycle_year': 2026,
        'cycle_month': 10,
        'total_amount': 350,
        'amount_paid': 0,
        'external_paid': 350,
        'settlement_state': 'settled',
        'due_date': '2026-10-28',
      });
      expect(bill.balance.isZero, isTrue);
      expect(bill.amountPaid.isZero, isTrue);
      expect(bill.isPartiallyPaid, isFalse);
    },
  );
}
