import 'package:billalert/core/errors/app_failure.dart';
import 'package:billalert/core/result/result.dart';
import 'package:billalert/domain/entities/bill.dart';
import 'package:billalert/domain/notifications/phone_alerts.dart';
import 'package:billalert/domain/usecases/consumer/refresh_phone_alerts.dart';
import 'package:billalert/domain/value_objects/cycle_label.dart';
import 'package:billalert/domain/value_objects/ids.dart';
import 'package:billalert/domain/value_objects/kwh.dart';
import 'package:billalert/domain/value_objects/money.dart';
import 'package:billalert/domain/value_objects/ph_date.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/phone_alert_fakes.dart';

/// What a household's phone is told, and when.
///
/// Every rule here runs while the app is closed, where nobody can watch it go
/// wrong, so each is pinned by a test rather than trusted.
void main() {
  // 20 September 2026, 08:00 in Manila.
  final DateTime now = DateTime.utc(2026, 9, 20);

  late FakeAlertFeed feed;
  late FakePhoneNotifier phone;

  setUp(() {
    feed = FakeAlertFeed();
    phone = FakePhoneNotifier();
  });

  RefreshPhoneAlerts refresh() =>
      RefreshPhoneAlerts(feed: feed, phone: phone, clock: StoppedClock(now));

  Bill bill(
    String id, {
    PhDate? due = const PhDate(2026, 9, 28),
    int totalCentavos = 65830,
    int paidCentavos = 0,
  }) => Bill(
    id: BillId(id),
    billNo: BillNumber('BA-202608-$id'),
    consumerId: const ConsumerId('consumer-1'),
    cycle: const CycleLabel(2026, 8),
    consumption: const Kwh.fromHundredths(5800),
    totalAmount: due == null ? null : Money.fromCentavos(totalCentavos),
    dueDate: due,
    amountPaid: Money.fromCentavos(paidCentavos),
  );

  group('notices the server queued', () {
    test('each is shown once and marked shown', () async {
      feed.pending = const <PendingPhoneAlert>[
        PendingPhoneAlert(id: NotificationId('n-1'), type: 'bill_ready'),
      ];

      await refresh()();

      expect(phone.shown, hasLength(1));
      expect(phone.shown.single.title, 'Your bill is ready');
      // No bill on this notice, so tapping it opens the Inbox at it.
      expect(phone.shown.single.payload, 'notice:n-1');
      expect(feed.markedShown.single.value, 'n-1');
    });

    test('a notice about a bill opens that bill when tapped', () async {
      feed.pending = const <PendingPhoneAlert>[
        PendingPhoneAlert(
          id: NotificationId('n-1'),
          type: 'bill_ready',
          bill: BillId('b-7'),
        ),
      ];

      await refresh()();

      expect(phone.shown.single.payload, 'bill:b-7');
    });

    test(
      'never carry an amount, which anyone holding the phone could read',
      () async {
        feed.pending = const <PendingPhoneAlert>[
          PendingPhoneAlert(id: NotificationId('n-1'), type: 'bill_ready'),
          PendingPhoneAlert(id: NotificationId('n-2'), type: 'overdue'),
          PendingPhoneAlert(id: NotificationId('n-3'), type: 'disconnection'),
        ];

        await refresh()();

        for (final PhoneNotice notice in phone.shown) {
          expect(notice.title + notice.body, isNot(contains('₱')));
        }
      },
    );

    test('are neither shown nor marked while notifications are off', () async {
      // A notice marked sent that nobody saw would be a false delivery record.
      phone.allowed = false;
      feed.pending = const <PendingPhoneAlert>[
        PendingPhoneAlert(id: NotificationId('n-1'), type: 'bill_ready'),
      ];

      final result = await refresh()();

      expect(phone.shown, isEmpty);
      expect(feed.markedShown, isEmpty);
      expect((result as Ok<PhoneAlertReport>).value.notificationsOff, isTrue);
    });
  });

  group('due-date reminders', () {
    test('go off at 08:00 in Manila, the set number of days before', () async {
      feed.unpaid = <Bill>[bill('b-1', due: const PhDate(2026, 9, 28))];
      feed.reminderDays = 3;

      await refresh()();

      final ScheduledNotice reminder = phone.scheduled.values.single;
      // 25 September, 08:00 in Manila, is 00:00 UTC.
      expect(reminder.atUtc, DateTime.utc(2026, 9, 25));
      expect(reminder.notice.title, 'Bill due in 3 days');
      expect(reminder.notice.body, contains('28 September'));
      expect(reminder.notice.payload, 'bill:b-1');
    });

    test("use the server's setting, not a number fixed in the app", () async {
      feed.unpaid = <Bill>[bill('b-1', due: const PhDate(2026, 9, 28))];
      feed.reminderDays = 1;

      await refresh()();

      expect(phone.scheduled.values.single.atUtc, DateTime.utc(2026, 9, 27));
      expect(phone.scheduled.values.single.notice.title, 'Bill due tomorrow');
    });

    test('are not sent late once their moment has passed', () async {
      // Due 22 September with 3 days' notice means 19 September — yesterday.
      feed.unpaid = <Bill>[bill('b-1', due: const PhDate(2026, 9, 22))];

      await refresh()();

      expect(phone.scheduled, isEmpty);
    });

    test('are not scheduled for a bill that is already paid', () async {
      feed.unpaid = <Bill>[
        bill('b-1', totalCentavos: 65830, paidCentavos: 65830),
      ];

      await refresh()();

      expect(phone.scheduled, isEmpty);
    });

    test('are cancelled once the bill is no longer unpaid', () async {
      feed.unpaid = <Bill>[bill('b-1')];
      await refresh()();
      expect(phone.scheduled, hasLength(1));

      // Paid at the cashier; the next refresh no longer sees it unpaid.
      feed.unpaid = <Bill>[];
      await refresh()();

      expect(phone.scheduled, isEmpty);
    });

    test('are left alone when the bills cannot be read', () async {
      feed.unpaid = <Bill>[bill('b-1')];
      await refresh()();

      // No signal is not the same as "paid".
      feed.unpaidFailure = const NetworkFailure();
      await refresh()();

      expect(phone.scheduled, hasLength(1));
    });
  });

  group('whose phone this is', () {
    test(
      'signed out, or staff: everything of a household is removed',
      () async {
        feed.unpaid = <Bill>[bill('b-1')];
        await refresh()();
        expect(phone.scheduled, hasLength(1));

        feed.household = const Ok<ConsumerId?>(null);
        await refresh()();

        expect(phone.cancelAllCalls, 1);
        expect(phone.scheduled, isEmpty);
      },
    );

    test('not knowing who is signed in removes nothing', () async {
      feed.unpaid = <Bill>[bill('b-1')];
      await refresh()();

      feed.household = const Err<ConsumerId?>(NetworkFailure());
      final result = await refresh()();

      expect(result, isA<Err<PhoneAlertReport>>());
      expect(phone.cancelAllCalls, 0);
      expect(phone.scheduled, hasLength(1));
    });
  });

  group('stable notice ids', () {
    test('are the same every time for the same alert, and fit Android', () {
      final int first = stableNoticeId('alert:n-1');

      expect(stableNoticeId('alert:n-1'), first);
      expect(first, inInclusiveRange(0, 0x7fffffff));
    });

    test('differ between an alert and a reminder with the same id', () {
      expect(
        stableNoticeId('alert:abc'),
        isNot(stableNoticeId('reminder:abc')),
      );
    });
  });
}
