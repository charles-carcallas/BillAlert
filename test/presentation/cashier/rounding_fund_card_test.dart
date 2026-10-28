import 'package:billalert/core/result/result.dart';
import 'package:billalert/domain/entities/app_user.dart';
import 'package:billalert/domain/repositories/payment_repository.dart';
import 'package:billalert/domain/value_objects/ids.dart';
import 'package:billalert/domain/value_objects/money.dart';
import 'package:billalert/presentation/auth/auth_controller.dart';
import 'package:billalert/presentation/cashier/rounding_fund_card.dart';
import 'package:billalert/presentation/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';

final class _Payments implements PaymentRepository {
  final List<RoundingFundMonth> months;

  _Payments(this.months);

  @override
  Future<Result<List<RoundingFundMonth>>> roundingFund(AreaId areaId) async =>
      Ok<List<RoundingFundMonth>>(months);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Money peso(int centavos) => Money.fromCentavos(centavos);

void main() {
  const cashier = CashierUser(
    id: ProfileId('cashier-1'),
    username: 'cashier',
    firstName: 'Cora',
    lastName: 'Cashier',
    areaId: AreaId('area-3'),
    mustChangePassword: false,
  );

  testWidgets('the Cashier sees the rounding, the pay and the fund saved', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(
            () => FakeAuthController(signedInUser: cashier),
          ),
          paymentRepositoryProvider.overrideWithValue(
            _Payments(<RoundingFundMonth>[
              RoundingFundMonth(
                year: 2026,
                month: 9,
                collected: peso(1250000),
                toBoheco: peso(1204000),
                rounding: peso(46000),
                gap: peso(10000),
                fundBefore: peso(5000),
                keptForGap: peso(10000),
                readerPay: peso(30000),
                fundAfter: peso(21000),
              ),
            ]),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: RoundingFundCard())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Rounding fund · September 2026'), findsOneWidget);
    expect(find.text('₱460.00'), findsOneWidget);
    expect(find.text('₱300.00'), findsOneWidget);
    expect(find.text('BOHECO still owed ₱100.00'), findsOneWidget);
    expect(find.text('₱210.00'), findsOneWidget);
  });
}
