import 'package:billalert/domain/entities/consumer.dart';
import 'package:billalert/domain/repositories/notice_repository.dart';
import 'package:billalert/domain/repositories/payment_repository.dart';
import 'package:billalert/domain/value_objects/ids.dart';
import 'package:billalert/domain/value_objects/kwh.dart';
import 'package:billalert/domain/value_objects/money.dart';
import 'package:billalert/presentation/common/consumer_search.dart';
import 'package:billalert/presentation/common/notice_search.dart';
import 'package:billalert/presentation/common/payment_search.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const Consumer consumer = Consumer(
    id: ConsumerId('consumer-1'),
    consumerNo: ConsumerNumber('2026-0042-TUB'),
    firstName: 'Virgilio',
    lastName: 'Busalanan',
    areaId: AreaId('area-3'),
    accountStatus: AccountStatus.active,
    previousReading: Kwh.zero,
    purok: 'Purok 4',
    meterSerialNo: 'MTR-9007',
  );

  test('Reader Consumers search checks every useful household identifier', () {
    expect(consumerMatchesSearch(consumer, 'virgilio bus'), isTrue);
    expect(consumerMatchesSearch(consumer, '0042-tub'), isTrue);
    expect(consumerMatchesSearch(consumer, 'purok 4'), isTrue);
    expect(consumerMatchesSearch(consumer, 'mtr-9007'), isTrue);
    expect(consumerMatchesSearch(consumer, 'lumayag'), isFalse);
  });

  test('Reader My Round uses the same offline household search', () {
    expect(consumerMatchesSearch(consumer, ' BUSALANAN '), isTrue);
    expect(consumerMatchesSearch(consumer, ''), isTrue);
  });

  test('Cashier Receipts search checks consumer and receipt number', () {
    final PaymentSummary receipt = PaymentSummary(
      receiptNo: 'BIEC-2026-09-004471',
      consumerId: const ConsumerId('consumer-1'),
      consumerName: 'Virgilio Busalanan',
      verificationCode: 'VERIFY-1',
      paidAt: DateTime.utc(2026, 9, 9),
      totalCollected: Money.of(1271, 15),
      bills: const <SettledBill>[],
    );

    expect(paymentMatchesSearch(receipt, 'virgilio'), isTrue);
    expect(paymentMatchesSearch(receipt, '004471'), isTrue);
    expect(paymentMatchesSearch(receipt, 'lumayag'), isFalse);
  });

  test('Admin Notices search checks consumer, account and notice number', () {
    final ActiveNotice notice = ActiveNotice(
      id: const NoticeId('notice-1'),
      noticeNo: 'DN-2026-0909-0033',
      consumerId: const ConsumerId('consumer-1'),
      consumerLabel: 'Virgilio Busalanan',
      consumerNo: '2026-0042-TUB',
      servedAt: DateTime.utc(2026, 9, 9),
      earliestLawfulAt: DateTime.utc(2026, 9, 11),
      periodElapsed: true,
      amountOverdue: Money.of(1272),
      hoursRemaining: 0,
      reason: 'Unpaid electricity bill',
    );

    expect(noticeMatchesSearch(notice, 'busalanan'), isTrue);
    expect(noticeMatchesSearch(notice, '0042-tub'), isTrue);
    expect(noticeMatchesSearch(notice, '0909-0033'), isTrue);
    expect(noticeMatchesSearch(notice, 'lumayag'), isFalse);
  });
}
