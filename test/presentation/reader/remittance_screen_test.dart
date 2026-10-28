import 'package:billalert/core/result/result.dart';
import 'package:billalert/data/repositories/settlement_repository.dart';
import 'package:billalert/domain/entities/app_user.dart';
import 'package:billalert/domain/entities/bill.dart';
import 'package:billalert/domain/repositories/payment_repository.dart';
import 'package:billalert/domain/value_objects/cycle_label.dart';
import 'package:billalert/domain/value_objects/ids.dart';
import 'package:billalert/domain/value_objects/kwh.dart';
import 'package:billalert/domain/value_objects/money.dart';
import 'package:billalert/domain/value_objects/ph_date.dart';
import 'package:billalert/presentation/auth/auth_controller.dart';
import 'package:billalert/presentation/common/settlement_panel.dart';
import 'package:billalert/presentation/providers.dart';
import 'package:billalert/presentation/reader/remittance_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';

/// Answers [collectedInArea] from a fixed list, filtered the way the server
/// filters, and remembers the window it was asked for.
final class _Payments implements PaymentRepository {
  final List<PaymentSummary> all;
  DateTime? askedFrom;
  DateTime? askedUntil;

  _Payments(this.all);

  @override
  Future<Result<List<PaymentSummary>>> collectedInArea(
    AreaId areaId, {
    required DateTime from,
    required DateTime until,
  }) async {
    askedFrom = from;
    askedUntil = until;
    return Ok<List<PaymentSummary>>(
      all
          .where((p) => !p.paidAt.isBefore(from) && p.paidAt.isBefore(until))
          .toList(),
    );
  }

  @override
  Future<Result<DateTime?>> collectedInAreaSavedAt(
    AreaId areaId, {
    required DateTime from,
  }) async => Ok<DateTime?>(askedFrom == null ? null : DateTime.now().toUtc());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

PaymentSummary receipt(
  String no,
  String name,
  DateTime paidAt,
  int centavos, {
  String consumerId = 'c1',
}) => PaymentSummary(
  receiptNo: no,
  consumerId: ConsumerId(consumerId),
  consumerName: name,
  verificationCode: 'V-$no',
  paidAt: paidAt,
  totalCollected: Money.fromCentavos(centavos),
  bills: <SettledBill>[
    SettledBill(
      billId: BillId('b-$no'),
      billNo: BillNumber('BA-$no'),
      cycleLabel: 'August 2026',
      amountPaid: Money.fromCentavos(centavos),
    ),
  ],
);

void main() {
  const reader = MeterReaderUser(
    id: ProfileId('reader-1'),
    username: 'ledesma.dormal',
    firstName: 'Ledesma',
    lastName: 'Dormal',
    areaId: AreaId('area-3'),
    mustChangePassword: false,
  );

  group('monthBounds', () {
    test('September covers 29 Aug through the end of 28 Sep, in Manila', () {
      final bounds = monthBounds(const CycleLabel(2026, 9));

      // 29 Aug 2026 00:00 in Manila is 28 Aug 16:00 UTC.
      expect(bounds.from, DateTime.utc(2026, 8, 28, 16));
      // It stops at 29 Sep 00:00 in Manila, so all of the 28th is in.
      expect(bounds.until, DateTime.utc(2026, 9, 28, 16));
    });

    test('January starts on 29 December of the year before', () {
      final bounds = monthBounds(const CycleLabel(2027, 1));

      expect(bounds.from, DateTime.utc(2026, 12, 28, 16));
    });

    test('March starts on 1 March after a 28-day February', () {
      final bounds = monthBounds(const CycleLabel(2027, 3));

      expect(bounds.from, DateTime.utc(2027, 2, 28, 16));
    });
  });

  group('handoverMonthOf', () {
    test('up to the 28th, it is this month', () {
      expect(
        handoverMonthOf(const PhDate(2026, 9, 28)),
        const CycleLabel(2026, 9),
      );
    });

    test('from the 29th, it is next month', () {
      expect(
        handoverMonthOf(const PhDate(2026, 9, 29)),
        const CycleLabel(2026, 10),
      );
      expect(
        handoverMonthOf(const PhDate(2026, 12, 30)),
        const CycleLabel(2027, 1),
      );
    });
  });

  test('the copied summary leads with the total, then receipts by day', () {
    final String copied = remittanceText(
      const CycleLabel(2026, 9),
      <PaymentSummary>[
        // Newest first, as the server returns them.
        receipt('R2', 'Rosalinda Amistad', DateTime.utc(2026, 9, 9, 2), 50000),
        receipt('R1', 'Elena Ravelo', DateTime.utc(2026, 9, 8, 2), 67100),
      ],
      reader: 'Ledesma Dormal',
    );

    expect(copied, contains('BillAlert remittance — September 2026'));
    expect(copied, contains('Meter reader: Ledesma Dormal'));
    expect(copied, contains('Receipts: 2'));
    expect(copied, contains('₱1,171.00'));
    // Oldest first on paper.
    expect(
      copied.indexOf('Elena Ravelo'),
      lessThan(copied.indexOf('Rosalinda Amistad')),
    );
  });

  Future<_Payments> open(WidgetTester tester, List<PaymentSummary> all) async {
    tester.view.physicalSize = const Size(412, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final payments = _Payments(all);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settlementSnapshotProvider.overrideWith(
            (ref) async => SettlementSnapshot({}),
          ),
          authControllerProvider.overrideWith(
            () => FakeAuthController(signedInUser: reader),
          ),
          paymentRepositoryProvider.overrideWithValue(payments),
          // 20 September 2026, eight days before the handover.
          phClockProvider.overrideWithValue(
            FixedPhClock.onPhDate(const PhDate(2026, 9, 20)),
          ),
        ],
        child: const MaterialApp(home: RemittanceScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Elena Ravelo'), findsNothing);
    await tester.tap(find.text('Collections'));
    await tester.pumpAndSettle();
    return payments;
  }

  testWidgets('shows the month total, the receipts and the handover day', (
    WidgetTester tester,
  ) async {
    await open(tester, <PaymentSummary>[
      receipt(
        'R2',
        'Rosalinda Amistad',
        DateTime.utc(2026, 9, 9, 2),
        50000,
        consumerId: 'c2',
      ),
      receipt('R1', 'Elena Ravelo', DateTime.utc(2026, 9, 8, 2), 67100),
      // 20 Aug was in August's envelope.
      receipt('R0', 'Old Payment', DateTime.utc(2026, 8, 20, 2), 99900),
      // 29 Aug, after August's handover, goes in September's.
      receipt(
        'R3',
        'Late August',
        DateTime.utc(2026, 8, 29, 2),
        10000,
        consumerId: 'c3',
      ),
      // 29 Sep, after September's handover, waits for October.
      receipt(
        'R4',
        'Next Envelope',
        DateTime.utc(2026, 9, 29, 2),
        10000,
        consumerId: 'c4',
      ),
    ]);

    expect(find.text('September 2026'), findsOneWidget);
    // Bills posted before the split was kept: all of it goes to BOHECO.
    expect(find.text('₱1,271.00'), findsOneWidget);
    // The Meter Reader is never shown the rounding.
    expect(find.textContaining('share'), findsNothing);
    expect(find.text('Late August'), findsOneWidget);
    expect(find.text('Next Envelope'), findsNothing);
    expect(find.text('Collected 29 Aug – 28 Sep 2026'), findsOneWidget);
    expect(find.text('Elena Ravelo'), findsOneWidget);
    expect(find.text('Rosalinda Amistad'), findsOneWidget);
    expect(find.text('Old Payment'), findsNothing);
    expect(
      find.text('Receipt reporting period ends in 8 days'),
      findsOneWidget,
    );
  });

  testWidgets('the previous month can be checked, not a future one', (
    WidgetTester tester,
  ) async {
    await open(tester, <PaymentSummary>[
      receipt('R0', 'Old Payment', DateTime.utc(2026, 8, 20, 2), 99900),
    ]);

    final IconButton next = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.chevron_right).first,
    );
    expect(next.onPressed, isNull);

    await tester.tap(find.byTooltip('Previous month'));
    await tester.pumpAndSettle();

    expect(find.text('August 2026'), findsOneWidget);
    expect(find.text('Old Payment'), findsOneWidget);
  });

  testWidgets('a month with nothing collected says so', (
    WidgetTester tester,
  ) async {
    await open(tester, const <PaymentSummary>[]);

    expect(
      find.text('No payments collected in September 2026.'),
      findsOneWidget,
    );
  });

  group('the rounding share', () {
    SettledBill line(int paid, int? boheco) => SettledBill(
      billId: const BillId('b'),
      billNo: const BillNumber('BA-1'),
      cycleLabel: 'September 2026',
      amountPaid: Money.fromCentavos(paid),
      bohecoShare: boheco == null ? null : Money.fromCentavos(boheco),
    );

    PaymentSummary paid(List<SettledBill> bills) => PaymentSummary(
      receiptNo: 'R',
      consumerId: const ConsumerId('c1'),
      consumerName: 'Test',
      verificationCode: 'V',
      paidAt: DateTime.utc(2026, 9, 10),
      totalCollected: bills.fold(
        Money.zero,
        (Money sum, SettledBill b) => sum + b.amountPaid,
      ),
      bills: bills,
    );

    test('BOHECO gets its figure, the reader keeps the rounding', () {
      // BOHECO said 529.40; the household paid 530.00.
      final split = RemitSplit.of(<PaymentSummary>[
        paid(<SettledBill>[line(53000, 52940)]),
      ]);

      expect(split.toBoheco, const Money.fromCentavos(52940));
      expect(split.readerShare, const Money.fromCentavos(60));
      expect(split.handOver, const Money.fromCentavos(52940));
    });

    test('a bill posted before the split was kept is handed over whole', () {
      final split = RemitSplit.of(<PaymentSummary>[
        paid(<SettledBill>[line(53000, 52940), line(70400, null)]),
      ]);

      expect(split.readerShare, const Money.fromCentavos(60));
      expect(split.unsplit, const Money.fromCentavos(70400));
      expect(split.handOver, const Money.fromCentavos(52940 + 70400));
    });

    test('the copied summary says what goes to BOHECO and what is lacking', () {
      final copied = remittanceText(
        const CycleLabel(2026, 9),
        <PaymentSummary>[
          paid(<SettledBill>[line(53000, 52940)]),
        ],
        unpaid: const MonthUnpaid(
          amount: Money.fromCentavos(104000),
          households: 2,
          notPriced: 1,
        ),
      );

      expect(copied, contains('Hand over to BOHECO: ₱529.40'));
      expect(copied, isNot(contains('share')));
      expect(copied, contains('Still unpaid for September 2026: ₱1,040.00'));
      expect(copied, contains('Bills with no amount yet: 1'));
    });
  });

  test('still unpaid: balances of priced bills, and unpriced ones counted', () {
    Bill bill(String consumer, int? total, {int paid = 0}) => Bill(
      id: BillId('b-$consumer'),
      billNo: BillNumber('BA-$consumer'),
      consumerId: ConsumerId(consumer),
      cycle: const CycleLabel(2026, 9),
      consumption: Kwh.parse('100'),
      totalAmount: total == null ? null : Money.fromCentavos(total),
      dueDate: total == null ? null : const PhDate(2026, 9, 28),
      amountPaid: Money.fromCentavos(paid),
    );

    final unpaid = MonthUnpaid.of(<Bill>[
      bill('paid', 53000, paid: 53000),
      bill('partly', 53000, paid: 20000),
      bill('none', 70400),
      bill('unpriced', null),
    ]);

    expect(unpaid.amount, const Money.fromCentavos(33000 + 70400));
    expect(unpaid.households, 2);
    expect(unpaid.notPriced, 1);
  });
}
