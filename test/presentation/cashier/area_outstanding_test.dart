import 'package:billalert/domain/repositories/bill_repository.dart';
import 'package:billalert/domain/value_objects/ids.dart';
import 'package:billalert/domain/value_objects/money.dart';
import 'package:billalert/presentation/cashier/receipts_controller.dart';
import 'package:flutter_test/flutter_test.dart';

ConsumerOutstanding _household({
  required String name,
  required int centavos,
  int payable = 1,
  int overdue = 0,
  int unpriced = 0,
}) => ConsumerOutstanding(
  consumerId: ConsumerId('consumer-$name'),
  consumerNo: const ConsumerNumber('2020-0001-TUB'),
  consumerName: name,
  payableBillCount: payable,
  unpricedBillCount: unpriced,
  overdueCount: overdue,
  totalOutstanding: Money.fromCentavos(centavos),
);

/// The Receipts screen tells a cashier closing up what came in and what is
/// still out there. The second figure is a roll-up of the same per-household
/// rows their own list screen shows, so the two can never disagree.
void main() {
  test('the area total is the sum of what each household still owes', () {
    final AreaOutstanding owed = AreaOutstanding.from(<ConsumerOutstanding>[
      _household(name: 'Elena', centavos: 54120, overdue: 1),
      _household(name: 'Rodel', centavos: 61235),
      _household(name: 'Bienvenido', centavos: 65830, overdue: 1),
    ]);

    expect(owed.total, const Money.fromCentavos(181185));
    expect(owed.households, 3);
    expect(owed.overdueHouseholds, 2);
  });

  test('a household that owes nothing is not counted', () {
    // v_consumer_outstanding can return a row with a zero balance — a
    // household whose only open bill is unpriced. Counting it would tell the
    // cashier there are more people to collect from than there are.
    final AreaOutstanding owed = AreaOutstanding.from(<ConsumerOutstanding>[
      _household(name: 'Elena', centavos: 54120),
      _household(name: 'Teresita', centavos: 0, payable: 0, unpriced: 1),
    ]);

    expect(owed.total, const Money.fromCentavos(54120));
    expect(owed.households, 1);
    expect(owed.overdueHouseholds, 0);
  });

  test('an area with nothing owed totals zero', () {
    final AreaOutstanding owed = AreaOutstanding.from(
      const <ConsumerOutstanding>[],
    );

    expect(owed.total, Money.zero);
    expect(owed.households, 0);
    expect(owed.overdueHouseholds, 0);
  });
}
