import 'package:billalert/core/errors/app_failure.dart';
import 'package:billalert/core/result/result.dart';
import 'package:billalert/domain/entities/bill.dart';
import 'package:billalert/domain/repositories/notice_repository.dart';
import 'package:billalert/domain/repositories/notification_repository.dart';
import 'package:billalert/domain/usecases/consumer/load_notification_details.dart';
import 'package:billalert/domain/value_objects/cycle_label.dart';
import 'package:billalert/domain/value_objects/ids.dart';
import 'package:billalert/domain/value_objects/kwh.dart';
import 'package:billalert/domain/value_objects/money.dart';
import 'package:billalert/domain/value_objects/ph_date.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

/// Active notices by id, or a failure for every read.
final class _Notices implements NoticeRepository {
  final Map<String, ActiveNotice> active = <String, ActiveNotice>{};
  AppFailure? failure;

  @override
  Future<Result<List<ActiveNotice>>> activeFor(AreaId areaId) async =>
      Ok<List<ActiveNotice>>(active.values.toList());

  @override
  Future<Result<ActiveNotice?>> byId(NoticeId id) async {
    final AppFailure? failure = this.failure;
    return failure == null
        ? Ok<ActiveNotice?>(active[id.value])
        : Err<ActiveNotice?>(failure);
  }

  @override
  Future<Result<void>> closeNotice({
    required NoticeId noticeId,
    required NoticeOutcome outcome,
    String? notes,
  }) async => const Ok<void>(null);
}

/// CON-05: opening an Inbox notification onto what it is about.
void main() {
  const Bill august = Bill(
    id: BillId('bill-aug'),
    billNo: BillNumber('BA-202608-000001'),
    consumerId: ConsumerId('consumer-1'),
    cycle: CycleLabel(2026, 8),
    consumption: Kwh.fromHundredths(6200),
    totalAmount: Money.fromCentavos(70500),
    dueDate: PhDate(2026, 9, 30),
  );

  final ActiveNotice served = ActiveNotice(
    id: const NoticeId('notice-1'),
    noticeNo: 'DN-2026-0910-0033',
    consumerId: const ConsumerId('consumer-1'),
    consumerLabel: 'Virgilio Busalanan',
    servedAt: DateTime.utc(2026, 9, 9, 20, 55),
    earliestLawfulAt: DateTime.utc(2026, 9, 14),
    periodElapsed: false,
    amountOverdue: const Money.fromCentavos(54120),
    hoursRemaining: 92,
    reason: 'Unpaid July 2026 bill',
  );

  AppNotification alert({BillId? billId, NoticeId? noticeId}) =>
      AppNotification(
        id: const NotificationId('n-1'),
        type: noticeId != null ? 'disconnection' : 'bill_ready',
        channel: 'push',
        message: 'A notice.',
        isRead: false,
        createdAt: DateTime.utc(2026, 9, 9),
        billId: billId,
        noticeId: noticeId,
      );

  late FakeBillRepository bills;
  late _Notices notices;
  late LoadNotificationDetails load;

  setUp(() {
    bills = FakeBillRepository();
    notices = _Notices();
    load = LoadNotificationDetails(bills: bills, notices: notices);
  });

  test('a bill notification comes with its bill', () async {
    bills.billsById['bill-aug'] = august;

    final details = await load(alert(billId: const BillId('bill-aug')));

    expect(details.bill?.billNo.value, 'BA-202608-000001');
    expect(details.notice, isNull);
    expect(details.relatedFailure, isNull);
  });

  test('a disconnection notification comes with its notice', () async {
    notices.active['notice-1'] = served;

    final details = await load(alert(noticeId: const NoticeId('notice-1')));

    expect(details.notice?.noticeNo, 'DN-2026-0910-0033');
    expect(details.noticeNoLongerActive, isFalse);
  });

  test('a notice closed since is said to be no longer active', () async {
    final details = await load(alert(noticeId: const NoticeId('notice-1')));

    expect(details.notice, isNull);
    expect(details.noticeNoLongerActive, isTrue);
  });

  test('a notification about nothing reads nothing', () async {
    // Any read would fail, so a failure here would mean one was attempted.
    bills.byIdFailure = const ServerFailure();
    notices.failure = const ServerFailure();

    final details = await load(alert());

    expect(details.bill, isNull);
    expect(details.notice, isNull);
    expect(details.relatedFailure, isNull);
  });

  test('a bill that cannot be read leaves the notification whole', () async {
    bills.byIdFailure = const NetworkFailure();
    final AppNotification opened = alert(billId: const BillId('bill-aug'));

    final details = await load(opened);

    expect(details.notification, same(opened));
    expect(details.relatedFailure, isA<NetworkFailure>());
    // Not "no longer available": it may be there once there is signal.
    expect(details.billUnavailable, isFalse);
  });
}
