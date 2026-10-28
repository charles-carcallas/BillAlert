import 'package:billalert/domain/entities/bill.dart';
import 'package:billalert/domain/repositories/payment_repository.dart';
import 'package:billalert/domain/value_objects/cycle_label.dart';
import 'package:billalert/domain/value_objects/ids.dart';
import 'package:billalert/domain/value_objects/kwh.dart';
import 'package:billalert/domain/value_objects/money.dart';
import 'package:billalert/domain/value_objects/ph_date.dart';
import 'package:billalert/presentation/auth/auth_controller.dart';
import 'package:billalert/presentation/consumer/history_controller.dart';
import 'package:billalert/presentation/consumer/history_screen.dart';
import 'package:billalert/presentation/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/fakes.dart';
import 'payment_history_filter_test.dart' show payment;

class _History extends HistoryController {
  @override
  HistoryState build() => HistoryState(
    receipts: <PaymentSummary>[
      payment('early', DateTime.utc(2026, 9, 30, 15, 59)),
      payment('selected', DateTime.utc(2026, 9, 30, 16)),
      payment('later', DateTime.utc(2026, 10, 2, 16)),
    ],
    bills: const <Bill>[
      Bill(
        id: BillId('bill'),
        billNo: BillNumber('B-1'),
        consumerId: ConsumerId('home'),
        cycle: CycleLabel(2026, 8),
        consumption: Kwh.fromHundredths(100),
        totalAmount: Money.fromCentavos(50000),
        dueDate: PhDate(2026, 9, 28),
      ),
    ],
  );
}

void main() {
  Future<void> open(WidgetTester tester) async {
    final router = GoRouter(
      routes: <RouteBase>[
        GoRoute(path: '/', builder: (_, _) => const HistoryScreen()),
        GoRoute(
          path: '/consumer/receipt/:receiptNo',
          builder: (_, state) => Scaffold(
            body: Text('Opened ${state.pathParameters['receiptNo']}'),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(FakeAuthController.new),
          historyControllerProvider.overrideWith(_History.new),
          phClockProvider.overrideWithValue(
            FixedPhClock.onPhDate(const PhDate(2026, 10, 24)),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> choose(WidgetTester tester, String start, String end) async {
    await tester.tap(find.byKey(const ValueKey('payment-date-range')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'calendar layout');
    await tester.tap(find.byTooltip('Switch to input'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'input layout');
    final fields = find.descendant(
      of: find.byType(DateRangePickerDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(fields.at(0), start);
    await tester.enterText(fields.at(1), end);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'date picker applies, cancels and clears; Bills remain independent',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await open(tester);
      expect(tester.takeException(), isNull, reason: 'initial history');
      await choose(tester, '10/01/2026', '10/01/2026');
      expect(tester.takeException(), isNull, reason: 'after date picker');
      expect(find.text('OR selected'), findsOneWidget);
      expect(find.text('OR early'), findsNothing);
      expect(find.text('OR later'), findsNothing);
      expect(find.text('Paid 2026-10-01'), findsOneWidget);
      await tester.tap(find.text('Bills'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'billing tab');
      expect(find.text('August 2026'), findsOneWidget);
      expect(find.byKey(const ValueKey('payment-date-range')), findsNothing);
      await tester.tap(find.text('Payments'));
      await tester.pumpAndSettle();
      expect(find.text('OR early'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('payment-date-range')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.text('OR early'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('clear-payment-dates')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('payment-early')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'empty filtered results explain recovery and matching receipt opens',
    (tester) async {
      await open(tester);
      await choose(tester, '10/10/2026', '10/11/2026');
      expect(find.text('No matching records.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('clear-payment-dates')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'selected');
      await tester.pumpAndSettle();
      await tester.tap(find.text('OR selected'));
      await tester.pumpAndSettle();
      expect(find.text('Opened selected'), findsOneWidget);
    },
  );
}
