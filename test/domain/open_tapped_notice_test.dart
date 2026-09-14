import 'package:billalert/core/errors/app_failure.dart';
import 'package:billalert/domain/entities/bill.dart';
import 'package:billalert/domain/entities/consumer.dart';
import 'package:billalert/domain/notifications/phone_alerts.dart';
import 'package:billalert/domain/usecases/consumer/open_tapped_notice.dart';
import 'package:billalert/domain/value_objects/cycle_label.dart';
import 'package:billalert/domain/value_objects/ids.dart';
import 'package:billalert/domain/value_objects/kwh.dart';
import 'package:billalert/domain/value_objects/money.dart';
import 'package:billalert/domain/value_objects/ph_date.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

/// Phase 1: open the related bill or notice when a notification is tapped,
/// "after verifying the notification belongs to the authenticated account".
///
/// A notification outlives the session it was shown in. These tests hold the
/// app to showing a bill only to the household it belongs to, whoever is
/// holding the phone when it is tapped.
void main() {
  const Consumer me = Consumer(
    id: ConsumerId('household-1'),
    consumerNo: ConsumerNumber('2019-0917-TUB'),
    firstName: 'Virgilio',
    lastName: 'Busalanan',
    areaId: AreaId('area-3'),
    accountStatus: AccountStatus.active,
    previousReading: Kwh.fromHundredths(347500),
  );

  Bill billOf(String id, {required String household}) => Bill(
    id: BillId(id),
    billNo: BillNumber('BA-202609-$id'),
    consumerId: ConsumerId(household),
    cycle: const CycleLabel(2026, 9),
    consumption: const Kwh.fromHundredths(6300),
    totalAmount: const Money.fromCentavos(70420),
    dueDate: const PhDate(2026, 9, 28),
  );

  late FakeConsumerRepository consumers;
  late FakeBillRepository bills;

  setUp(() {
    consumers = FakeConsumerRepository(<Consumer>[])..me = me;
    bills = FakeBillRepository();
  });

  OpenTappedNotice open() =>
      OpenTappedNotice(consumers: consumers, bills: bills);

  String payloadFor(String billId) => BillNoticeTarget(BillId(billId)).encode();

  test("this household's own bill opens", () async {
    bills.billsById['b-1'] = billOf('b-1', household: 'household-1');

    final destination = await open()(payloadFor('b-1'));

    expect(destination, isA<ShowBill>());
    expect((destination as ShowBill).bill.id.value, 'b-1');
  });

  group('a bill is not shown', () {
    Future<void> expectRefused(String because) async {
      final destination = await open()(payloadFor('b-1'));

      expect(destination, isA<ShowInbox>(), reason: because);
      expect(
        (destination as ShowInbox).explanation,
        OpenTappedNotice.notOnThisAccount,
        reason: because,
      );
    }

    test('when it belongs to another household', () async {
      // Shown to one household, tapped after another signed in on the phone.
      bills.billsById['b-1'] = billOf('b-1', household: 'household-2');

      await expectRefused('the bill is someone else\'s');
    });

    test('when it cannot be found', () async {
      // Row-level security makes another household's bill look exactly like
      // this.
      await expectRefused('no such bill is visible');
    });

    test('when no household is signed in', () async {
      bills.billsById['b-1'] = billOf('b-1', household: 'household-1');
      consumers.me = null;

      await expectRefused('staff, or nobody, is signed in');
    });
  });

  group('when ownership cannot be checked', () {
    test('a failed bill lookup says so, rather than guessing', () async {
      bills.byIdFailure = const NetworkFailure();

      final destination = await open()(payloadFor('b-1'));

      expect(
        (destination as ShowInbox).explanation,
        OpenTappedNotice.couldNotOpen,
      );
    });

    test('a failed household lookup says so too', () async {
      bills.billsById['b-1'] = billOf('b-1', household: 'household-1');
      consumers.signedInFailure = const NetworkFailure();

      final destination = await open()(payloadFor('b-1'));

      expect(destination, isA<ShowInbox>());
      expect(
        (destination as ShowInbox).explanation,
        OpenTappedNotice.couldNotOpen,
      );
    });
  });

  test('a notice opens the Inbox at that notice', () async {
    final destination = await open()(
      const InboxNoticeTarget(notice: NotificationId('n-2')).encode(),
    );

    expect(destination, isA<ShowInbox>());
    expect((destination as ShowInbox).highlight?.value, 'n-2');
    // The Inbox lists only this household's rows, and says so itself when
    // the notice is not among them.
    expect(destination.explanation, isNull);
  });

  test('an unreadable payload opens the plain Inbox', () async {
    final destination = await open()('something-else');

    expect(destination, isA<ShowInbox>());
    expect((destination as ShowInbox).highlight, isNull);
    expect(destination.explanation, isNull);
  });
}
