import 'package:billalert/core/errors/app_failure.dart';
import 'package:billalert/core/result/result.dart';
import 'package:billalert/data/local/app_database.dart';
import 'package:billalert/data/network/network_status.dart';
import 'package:billalert/data/repositories/overdue_repository.dart';
import 'package:billalert/data/repositories/settlement_repository.dart';
import 'package:billalert/domain/entities/app_user.dart';
import 'package:billalert/domain/entities/bill.dart';
import 'package:billalert/domain/entities/consumer.dart' as domain;
import 'package:billalert/domain/outbox/outbox_operation.dart';
import 'package:billalert/domain/repositories/bill_repository.dart';
import 'package:billalert/domain/repositories/notice_repository.dart';
import 'package:billalert/domain/value_objects/ids.dart';
import 'package:billalert/domain/value_objects/kwh.dart';
import 'package:billalert/domain/value_objects/money.dart';
import 'package:billalert/presentation/admin/disconnections_screen.dart';
import 'package:billalert/presentation/admin/overdue_workspace_screen.dart';
import 'package:billalert/presentation/admin/serve_notice_controller.dart';
import 'package:billalert/presentation/admin/serve_notice_screen.dart';
import 'package:billalert/presentation/auth/auth_controller.dart';
import 'package:billalert/presentation/auth/linked_household_provider.dart';
import 'package:billalert/presentation/common/overdue_screen.dart';
import 'package:billalert/presentation/common/profile_screen.dart';
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

OverdueBill bill(
  String id, {
  String approval = 'requested',
  String home = 'house',
}) => OverdueBill(
  Bill.fromJson({
    'bill_id': id,
    'bill_no': id,
    'consumer_id': home,
    'cycle_year': 2026,
    'cycle_month': 9,
    'total_amount': 350,
    'amount_paid': 0,
    'due_date': '2026-09-28',
  }),
  home == 'house' ? 'Test household · TEST-1' : 'Household $home',
  approval,
  '350',
);
final notice = ActiveNotice(
  id: const NoticeId('notice'),
  noticeNo: 'DN-TEST',
  consumerId: const ConsumerId('house'),
  consumerLabel: 'Test household',
  servedAt: DateTime.utc(2026, 10, 3),
  earliestLawfulAt: DateTime.utc(2026, 10, 5),
  periodElapsed: false,
  amountOverdue: Money.parse('350'),
  hoursRemaining: 39,
  reason: 'Unpaid bill',
);

class TestNotices implements NoticeRepository {
  @override
  Future<Result<List<ActiveNotice>>> activeFor(AreaId area) async =>
      activeFailure == null ? Ok(active) : Err(activeFailure!);
  List<ActiveNotice> active = [];
  AppFailure? activeFailure;

  bool ready = true;
  int closes = 0;
  ActiveNotice get value => ActiveNotice(
    id: notice.id,
    noticeNo: notice.noticeNo,
    consumerId: notice.consumerId,
    consumerLabel: notice.consumerLabel,
    servedAt: notice.servedAt,
    earliestLawfulAt: notice.earliestLawfulAt,
    periodElapsed: false,
    amountOverdue: Money.zero,
    hoursRemaining: 0,
    reason: notice.reason,
    readyToClose: true,
  );
  @override
  Future<Result<NoticeReview?>> review(NoticeId id) async => Ok(
    NoticeReview(
      notice: value,
      status: ready ? 'active' : 'settled',
      checkedAt: DateTime.now(),
      coveredBills: [],
      overdueBills: [],
      sms: [],
      receipts: [
        NoticeReceipt(
          receiptNo: 'RECEIPT-TEST',
          billNo: 'bill',
          amount: Money.parse('350'),
          paidAt: DateTime.now(),
        ),
      ],
    ),
  );
  @override
  Future<Result<void>> closeNotice({
    required NoticeId noticeId,
    required NoticeOutcome outcome,
    String? notes,
  }) async {
    expect(outcome, NoticeOutcome.settled);
    closes++;
    return const Ok(null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('household-specific notice opens its confirmation directly', (
    tester,
  ) async {
    const person = domain.Consumer(
      id: ConsumerId('house'),
      consumerNo: ConsumerNumber('TEST-1'),
      firstName: 'Test',
      lastName: 'Household',
      areaId: AreaId('area'),
      accountStatus: domain.AccountStatus.active,
      previousReading: Kwh.zero,
    );
    final bills = FakeBillRepository()
      ..outstanding = [
        ConsumerOutstanding(
          consumerId: person.id,
          consumerNo: person.consumerNo,
          consumerName: person.fullName,
          payableBillCount: 1,
          unpricedBillCount: 0,
          overdueCount: 1,
          totalOutstanding: Money.parse('350'),
        ),
      ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(
            () => FakeAuthController(
              signedInUser: const AdminUser(
                id: ProfileId('admin'),
                username: 'admin',
                firstName: 'Test',
                lastName: 'President',
                areaId: AreaId('area'),
                mustChangePassword: false,
              ),
            ),
          ),
          consumerRepositoryProvider.overrideWithValue(
            FakeConsumerRepository([person]),
          ),
          billRepositoryProvider.overrideWithValue(bills),
          settlementSnapshotProvider.overrideWith(
            (ref) async => SettlementSnapshot({
              'bills': [
                {
                  'bill_id': 'overdue',
                  'route': 'boheco',
                  'state': 'referred',
                  'referred_at': '2026-09-29T00:00:00Z',
                },
              ],
            }),
          ),
          overdueBillsProvider.overrideWith((ref) async => [bill('overdue')]),
          noticeRepositoryProvider.overrideWithValue(TestNotices()),
          outboxRepositoryProvider.overrideWithValue(FakeOutboxRepository()),
        ],
        child: const MaterialApp(home: ServeNoticeScreen(consumerId: 'house')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Confirm notice'), findsOneWidget);
    expect(find.text('Test Household'), findsOneWidget);
  });
  for (final scenario in [
    'eligible',
    'active',
    'pending',
    'failure',
    'covered',
    'unconfirmed',
    'paid',
  ]) {
    testWidgets('notice picker eligibility: $scenario', (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      domain.Consumer home(String id, {bool active = true}) => domain.Consumer(
        id: ConsumerId(id),
        consumerNo: ConsumerNumber(id),
        firstName: id,
        lastName: 'Household',
        areaId: const AreaId('area'),
        accountStatus: active
            ? domain.AccountStatus.active
            : domain.AccountStatus.inactive,
        previousReading: Kwh.zero,
      );
      final notices = TestNotices();
      if (scenario == 'active') notices.active = [notice];
      if (scenario == 'failure') {
        notices.activeFailure = const NetworkFailure('Cannot check notices.');
      }
      final outbox = FakeOutboxRepository();
      if (scenario == 'pending') {
        outbox.enqueued.add(
          IssueNoticeOperation(
            clientUuid: const ClientUuid('pending-notice'),
            capturedAt: DateTime.utc(2026, 10, 4),
            consumerId: const ConsumerId('house'),
            consumerLabel: 'house Household',
          ),
        );
      }
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authControllerProvider.overrideWith(
              () => FakeAuthController(
                signedInUser: const AdminUser(
                  id: ProfileId('admin'),
                  username: 'admin',
                  firstName: 'Test',
                  lastName: 'President',
                  areaId: AreaId('area'),
                  mustChangePassword: false,
                ),
              ),
            ),
            consumerRepositoryProvider.overrideWithValue(
              FakeConsumerRepository([
                home('house'),
                home('current'),
                home('inactive', active: false),
              ]),
            ),
            settlementSnapshotProvider.overrideWith(
              (ref) async => SettlementSnapshot({
                'bills': [
                  for (final id in ['first', 'second', 'inactive-bill'])
                    {
                      'bill_id': id,
                      'route': scenario == 'covered' ? 'pondo' : 'boheco',
                      'state': scenario == 'covered'
                          ? 'awaiting_repayment'
                          : scenario == 'unconfirmed'
                          ? 'awaiting_referral'
                          : scenario == 'paid'
                          ? 'settled'
                          : 'referred',
                      'referred_at': '2026-09-29T00:00:00Z',
                    },
                ],
              }),
            ),
            overdueBillsProvider.overrideWith(
              (ref) async => [
                bill('first'),
                bill('second'),
                bill('inactive-bill', home: 'inactive'),
              ],
            ),
            noticeRepositoryProvider.overrideWithValue(notices),
            outboxRepositoryProvider.overrideWithValue(outbox),
          ],
          child: const MaterialApp(home: ServeNoticeScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('current Household'), findsNothing);
      expect(find.text('inactive Household'), findsNothing);
      expect(find.text('Eligible'), findsNothing);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ServeNoticeScreen)),
      );
      final controller = container.read(serveNoticeControllerProvider.notifier);
      controller.select(home('current'));
      expect(container.read(serveNoticeControllerProvider).selected, isNull);
      if (scenario == 'eligible') {
        expect(find.text('house Household'), findsOneWidget);
        expect(find.text('house · ₱700.00 overdue'), findsOneWidget);
        await tester.enterText(find.byType(TextField), 'missing');
        await tester.pumpAndSettle();
        expect(
          find.text('No eligible household matches that search.'),
          findsOneWidget,
        );
      } else {
        expect(find.text('house Household'), findsNothing);
        controller.select(home('house'));
        expect(container.read(serveNoticeControllerProvider).selected, isNull);
        if (scenario == 'failure') {
          expect(find.text('Cannot check notices.'), findsOneWidget);
        }
      }
      expect(tester.takeException(), isNull);
    });
  }
  const admin = AdminUser(
    id: ProfileId('admin'),
    username: 'admin',
    firstName: 'Test',
    lastName: 'President',
    areaId: AreaId('area'),
    mustChangePassword: false,
  );
  late AppDatabase db;
  late SupabaseClient client;
  late NetworkStatus network;
  late List<http.Request> requests;
  setUp(() {
    requests = [];
    db = AppDatabase.forTesting(NativeDatabase.memory());
    client = SupabaseClient(
      'https://example.invalid',
      'test-key',
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response('', 204, request: request);
      }),
    );
    network = NetworkStatus(
      linkChanges: const Stream.empty(),
      checkLink: () async => true,
    );
  });
  tearDown(() async {
    network.dispose();
    await client.dispose();
    await db.close();
  });

  Future<void> pump(
    WidgetTester tester, {
    double width = 390,
    bool active = true,
    List<OverdueBill>? rows,
    TestNotices? noticesRepo,
    bool cashier = false,
    List<ActiveNotice>? noticeRows,
    Map<String, dynamic>? settlement,
  }) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(
            () => FakeAuthController(
              signedInUser: cashier
                  ? const CashierUser(
                      id: ProfileId('cashier'),
                      username: 'cashier',
                      firstName: 'Test',
                      lastName: 'Cashier',
                      areaId: AreaId('area'),
                      mustChangePassword: false,
                    )
                  : admin,
            ),
          ),
          settlementSnapshotProvider.overrideWith(
            (ref) async => SettlementSnapshot(settlement ?? {}),
          ),
          linkedHouseholdProvider.overrideWith((ref) async => null),
          overdueBillsProvider.overrideWith(
            (ref) async => rows ?? [bill('bill')],
          ),
          activeNoticesProvider.overrideWith(
            (ref) async =>
                noticeRows ?? (active ? [noticesRepo?.value ?? notice] : []),
          ),
          closedNoticesProvider.overrideWith((ref) async => []),
          overdueHistoryProvider.overrideWith(
            (ref) async => [
              {
                'action': 'consumed',
                'amount': '350',
                'occurred_at': '2026-10-03T12:00:00Z',
                'bills': {
                  'bill_no': 'SEPT',
                  'consumers': {
                    'first_name': 'Test',
                    'last_name': 'Household',
                    'consumer_no': 'TEST-1',
                  },
                },
              },
            ],
          ),
          pendingOutboxProvider.overrideWith((ref) => Stream.value([])),
          savedListTimeProvider.overrideWith((ref, key) => Stream.value(null)),
          networkStatusProvider.overrideWithValue(network),
          if (noticesRepo != null)
            noticeRepositoryProvider.overrideWithValue(noticesRepo),
          overdueRepositoryProvider.overrideWithValue(
            OverdueRepository(client, db),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: cashier
                ? const OverdueScreen()
                : const AdminOverdueWorkspaceScreen(),
            bottomNavigationBar: const SizedBox(height: 80),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  test('multiple bills and a notice produce one household case', () {
    final cases = groupOverdueHouseholds(
      [bill('one'), bill('two')],
      [notice],
      [],
    );
    expect(cases, hasLength(1));
    expect(cases.single.balance, Money.parse('700'));
    expect(cases.single.requested, isTrue);
    expect(cases.single.notices, hasLength(1));
  });

  test('changed balance invalidates waiting and authorized states', () {
    final old = bill('bill');
    expect(
      OverdueBill(old.bill, old.household, 'requested', '300').isRequested,
      isFalse,
    );
    expect(
      OverdueBill(old.bill, old.household, 'approved', '300').isApproved,
      isFalse,
    );
  });

  testWidgets('Pay at BOHECO excludes covered bills and allocation cases', (
    tester,
  ) async {
    await pump(
      tester,
      width: 320,
      settlement: {
        'trips': [
          {'id': 'trip', 'trip_month': '2026-09-01'},
        ],
        'bills': [
          for (final route in ['boheco', 'pondo', 'review'])
            {
              'trip_id': 'trip',
              'bill_id': route,
              'consumer_name': 'Household $route',
              'consumer_no': route,
              'consumer_amount': 350,
              'route': route,
              'state': route == 'boheco'
                  ? 'awaiting_referral'
                  : route == 'pondo'
                  ? 'awaiting_repayment'
                  : 'review',
            },
        ],
      },
    );
    expect(find.text('Pay at BOHECO'), findsOneWidget);
    expect(find.text('Household boheco'), findsOneWidget);
    expect(find.text('Household pondo'), findsNothing);
    expect(find.text('Household review'), findsNothing);
    expect(find.textContaining('Awaiting Cashier allocation'), findsNothing);
    expect(find.text('Balance details'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'notice flow starts with serving then unpaid before paid at phone width',
    (tester) async {
      await pump(tester, width: 320, noticeRows: [TestNotices().value, notice]);
      await tester.tap(find.text('Disconnection notices'));
      await tester.pumpAndSettle();
      expect(find.text('Serve a notice').hitTestable(), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Serve a notice')).dy,
        lessThan(
          tester.getTopLeft(find.byKey(const ValueKey('overdue-search'))).dy,
        ),
      );
      expect(
        tester.getTopLeft(find.text('Awaiting payment · 1')).dy,
        lessThan(tester.getTopLeft(find.text('Payment verified · 1')).dy),
      );
      expect(find.text('Close as settled'), findsNothing);
      expect(find.text('Notice period: 39h remaining'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Reserve fund and Notices separate money routing from notice closure',
    (tester) async {
      final repo = TestNotices();
      await pump(tester, noticesRepo: repo, width: 320);
      expect(find.text('Close notice — Paid'), findsNothing);
      expect(find.text('Balance details'), findsNothing);
      expect(find.byKey(const ValueKey('overdue-search')), findsNothing);
      expect(find.text('Authorize collection'), findsNothing);
      await tester.tap(find.text('Disconnection notices'));
      await tester.pumpAndSettle();
      expect(find.text('Authorize collection'), findsNothing);
      expect(
        tester
            .getSize(find.widgetWithText(FilledButton, 'Close notice — Paid'))
            .height,
        greaterThanOrEqualTo(52),
      );
      expect(find.text('Serve a notice'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'settlement reviews receipts and writes only after confirmation',
    (tester) async {
      final repo = TestNotices();
      await pump(tester, rows: [], noticesRepo: repo);
      await tester.tap(find.text('Disconnection notices'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Close notice — Paid'));
      await tester.tap(find.text('Close notice — Paid'));
      // The progress indicator remains active behind the confirmation dialog.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.textContaining('RECEIPT-TEST'), findsOneWidget);
      expect(repo.closes, 0);
      await tester.tap(
        find.widgetWithText(FilledButton, 'Close notice — Paid').last,
      );
      await tester.pumpAndSettle();
      expect(repo.closes, 1);
    },
  );

  testWidgets('stale readiness prevents shortcut closure', (tester) async {
    final repo = TestNotices()..ready = false;
    await pump(tester, rows: [], noticesRepo: repo);
    await tester.tap(find.text('Disconnection notices'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Close notice — Paid'));
    await tester.tap(find.text('Close notice — Paid'));
    await tester.pumpAndSettle();
    expect(repo.closes, 0);
    expect(find.text('Close this paid notice?'), findsNothing);
  });

  testWidgets('offline notice closure creates no writes', (tester) async {
    final repo = TestNotices();
    await pump(tester, rows: [bill('one'), bill('two')], noticesRepo: repo);
    network.reportUnreachable();
    await tester.tap(find.text('Disconnection notices'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Close notice — Paid'));
    await tester.tap(find.text('Close notice — Paid'));
    await tester.pumpAndSettle();
    expect(repo.closes, 0);
    expect(requests, isEmpty);
  });

  testWidgets('cancelling settlement leaves the notice open', (tester) async {
    final repo = TestNotices();
    await pump(tester, rows: [], noticesRepo: repo);
    await tester.tap(find.text('Disconnection notices'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Close notice — Paid'));
    await tester.tap(find.text('Close notice — Paid'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(repo.closes, 0);
  });

  for (final width in [320.0, 1200.0]) {
    testWidgets('household grouping and history fit $width', (tester) async {
      await pump(tester, width: width);
      expect(find.text('Balance details'), findsNothing);
      expect(find.byKey(const ValueKey('overdue-search')), findsNothing);
      expect(find.text('Authorize collection'), findsNothing);
      await tester.tap(find.text('Disconnection notices'));
      await tester.pumpAndSettle();
      expect(find.textContaining('DN-TEST'), findsOneWidget);
      expect(find.text('Authorize collection'), findsNothing);
      await tester.tap(find.text('History'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Overdue payment recorded'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
