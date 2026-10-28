import 'package:billalert/core/result/result.dart';
import 'package:billalert/domain/entities/app_user.dart';
import 'package:billalert/domain/repositories/payment_repository.dart';
import 'package:billalert/domain/value_objects/cycle_label.dart';
import 'package:billalert/domain/value_objects/ids.dart';
import 'package:billalert/domain/value_objects/money.dart';
import 'package:billalert/presentation/auth/auth_controller.dart';
import 'package:billalert/presentation/cashier/cashier_remit_panel.dart';
import 'package:billalert/presentation/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';

final class _Payments implements PaymentRepository {
  final List<RemitHandover> handovers;
  int recorded = 0;

  _Payments(this.handovers);

  static const RoundingFundMonth september = RoundingFundMonth(
    year: 2026,
    month: 9,
    collected: Money.fromCentavos(53000),
    toBoheco: Money.fromCentavos(52940),
    rounding: Money.fromCentavos(60),
    gap: Money.zero,
    fundBefore: Money.zero,
    keptForGap: Money.zero,
    readerPay: Money.fromCentavos(60),
    fundAfter: Money.zero,
  );

  @override
  Future<Result<List<RoundingFundMonth>>> roundingFund(AreaId areaId) async =>
      const Ok<List<RoundingFundMonth>>(<RoundingFundMonth>[september]);

  @override
  Future<Result<List<RemitHandover>>> remitHandovers(AreaId areaId) async =>
      Ok<List<RemitHandover>>(handovers);

  @override
  Future<Result<RemitHandover>> recordRemitHandover({
    required int year,
    required int month,
  }) async {
    recorded++;
    final RemitHandover done = RemitHandover(
      year: year,
      month: month,
      toBoheco: september.toBoheco,
      readerPay: september.readerPay,
      gap: Money.zero,
      handedAt: DateTime.utc(2026, 9, 28, 2),
      handedToName: 'Ledesma Dormal',
    );
    handovers.add(done);
    return Ok<RemitHandover>(done);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const cashier = CashierUser(
    id: ProfileId('cashier-1'),
    username: 'cashier',
    firstName: 'Cora',
    lastName: 'Cashier',
    areaId: AreaId('area-3'),
    mustChangePassword: false,
  );

  Future<_Payments> open(WidgetTester tester) async {
    final payments = _Payments(<RemitHandover>[]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(
            () => FakeAuthController(signedInUser: cashier),
          ),
          paymentRepositoryProvider.overrideWithValue(payments),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CashierRemitPanel(month: CycleLabel(2026, 9)),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return payments;
  }

  testWidgets('the Cashier sees where the money goes and records the '
      'handover', (WidgetTester tester) async {
    final payments = await open(tester);

    expect(find.text('₱529.40'), findsOneWidget);
    expect(find.text('Regular collections to remit'), findsOneWidget);
    expect(find.text('Meter Reader pay (max ₱300)'), findsNothing);

    await tester.tap(find.text('Mark as handed over'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Record handover'));
    await tester.pumpAndSettle();

    expect(payments.recorded, 1);
    expect(find.textContaining('Handed over 28 Sep 2026'), findsOneWidget);
    expect(find.text('Mark as handed over'), findsNothing);
  });
}
