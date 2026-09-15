import 'package:billalert/core/errors/app_failure.dart';
import 'package:billalert/core/result/result.dart';
import 'package:billalert/domain/entities/app_user.dart';
import 'package:billalert/domain/entities/bill.dart';
import 'package:billalert/domain/notifications/phone_alerts.dart';
import 'package:billalert/domain/repositories/notice_repository.dart';
import 'package:billalert/domain/repositories/notification_repository.dart';
import 'package:billalert/domain/value_objects/cycle_label.dart';
import 'package:billalert/domain/value_objects/ids.dart';
import 'package:billalert/domain/value_objects/kwh.dart';
import 'package:billalert/domain/value_objects/money.dart';
import 'package:billalert/domain/value_objects/ph_date.dart';
import 'package:billalert/presentation/auth/auth_controller.dart';
import 'package:billalert/presentation/consumer/inbox_controller.dart';
import 'package:billalert/presentation/consumer/inbox_screen.dart';
import 'package:billalert/presentation/providers.dart';
import 'package:billalert/presentation/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';

/// The household's inbox with these rows, remembering which were marked read.
class _SpyInbox extends InboxController {
  final List<AppNotification> alerts;
  final List<String> marked = <String>[];

  _SpyInbox(this.alerts);

  @override
  InboxState build() => InboxState(alerts: alerts);

  @override
  Future<void> markRead(AppNotification alert) async =>
      marked.add(alert.id.value);
}

class _NotificationsOn implements NotificationPermission {
  @override
  Future<bool> isGranted() async => true;

  @override
  Future<bool> request() async => true;

  @override
  Future<void> openSettings() async {}
}

final class _Notices implements NoticeRepository {
  final Map<String, ActiveNotice> active;

  _Notices(this.active);

  @override
  Future<Result<List<ActiveNotice>>> activeFor(AreaId areaId) async =>
      Ok<List<ActiveNotice>>(active.values.toList());

  @override
  Future<Result<ActiveNotice?>> byId(NoticeId id) async =>
      Ok<ActiveNotice?>(active[id.value]);

  @override
  Future<Result<void>> closeNotice({
    required NoticeId noticeId,
    required NoticeOutcome outcome,
    String? notes,
  }) async => const Ok<void>(null);
}

/// CON-05: a household opens an Inbox notification to see what it is about.
void main() {
  const ConsumerUser household = ConsumerUser(
    id: ProfileId('consumer-profile-1'),
    username: 'virgilio.busalanan',
    firstName: 'Virgilio',
    lastName: 'Busalanan',
    mustChangePassword: false,
  );

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

  final AppNotification ready = AppNotification(
    id: const NotificationId('n-ready'),
    type: 'bill_ready',
    channel: 'push',
    message: 'Your August 2026 bill is ready.',
    isRead: false,
    createdAt: DateTime.utc(2026, 9, 9, 3, 30),
    billId: const BillId('bill-aug'),
    status: 'sent',
    sentAt: DateTime.utc(2026, 9, 9, 3, 45),
  );

  final AppNotification noNumber = AppNotification(
    id: const NotificationId('n-overdue'),
    type: 'overdue',
    channel: 'sms',
    message: 'Your July 2026 bill is overdue.',
    isRead: true,
    createdAt: DateTime.utc(2026, 9, 1),
    status: 'failed',
    failedReason: 'No contact number on file for this consumer',
  );

  final AppNotification disconnection = AppNotification(
    id: const NotificationId('n-notice'),
    type: 'disconnection',
    channel: 'sms',
    message: 'A disconnection notice was served.',
    isRead: false,
    createdAt: DateTime.utc(2026, 9, 9, 20, 56),
    noticeId: const NoticeId('notice-1'),
    status: 'pending',
  );

  late FakeBillRepository bills;
  late _SpyInbox inbox;

  setUp(() => bills = FakeBillRepository());

  Future<void> open(
    WidgetTester tester,
    List<AppNotification> alerts, {
    Map<String, ActiveNotice> notices = const <String, ActiveNotice>{},
  }) async {
    inbox = _SpyInbox(alerts);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(
            () => FakeAuthController(signedInUser: household),
          ),
          inboxControllerProvider.overrideWith(() => inbox),
          notificationPermissionProvider.overrideWithValue(_NotificationsOn()),
          billRepositoryProvider.overrideWithValue(bills),
          noticeRepositoryProvider.overrideWithValue(_Notices(notices)),
          phClockProvider.overrideWithValue(
            FixedPhClock.onPhDate(const PhDate(2026, 9, 20)),
          ),
        ],
        child: MaterialApp(theme: AppTheme.light(), home: const InboxScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The sheet is a lazily built list, so a card further down is scrolled to.
  Future<void> scrollSheetTo(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      120,
      scrollable: find
          .descendant(
            of: find.byType(BottomSheet),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('opening a bill notification shows its bill, and reads it', (
    WidgetTester tester,
  ) async {
    bills.billsById['bill-aug'] = august;
    await open(tester, <AppNotification>[ready]);

    await tester.tap(find.text('Your bill is ready'));
    await tester.pumpAndSettle();

    expect(inbox.marked, <String>['n-ready']);
    expect(find.text('Notification'), findsOneWidget);
    expect(find.text('Shown on your phone'), findsOneWidget);
    // Philippine time: 03:30 UTC is 11:30 in the morning in Tubod.
    expect(find.text('9 Sep 2026 · 11:30 AM'), findsOneWidget);

    await scrollSheetTo(tester, find.text('View full bill'));
    expect(find.text('August 2026'), findsOneWidget);
    expect(find.text('₱705.00'), findsOneWidget);
    expect(find.text('Unpaid'), findsOneWidget);

    await tester.tap(find.text('View full bill'));
    await tester.pumpAndSettle();
    expect(find.text('Bill details'), findsOneWidget);
  });

  testWidgets('a text that was never sent says why', (
    WidgetTester tester,
  ) async {
    await open(tester, <AppNotification>[noNumber]);

    await tester.tap(find.text('Bill is overdue'));
    await tester.pumpAndSettle();

    // Already read, so opening it marks nothing.
    expect(inbox.marked, isEmpty);
    expect(find.text('Text message (SMS)'), findsOneWidget);
    expect(find.text('Text message not sent'), findsOneWidget);
    expect(
      find.text('No contact number on file for this consumer'),
      findsOneWidget,
    );
  });

  testWidgets(
    'a disconnection notification shows the notice and its lawful date',
    (WidgetTester tester) async {
      await open(
        tester,
        <AppNotification>[disconnection],
        notices: <String, ActiveNotice>{'notice-1': served},
      );

      await tester.tap(find.text('Disconnection notice served'));
      await tester.pumpAndSettle();

      expect(find.text('Waiting to be sent'), findsOneWidget);

      await scrollSheetTo(tester, find.text('Earliest lawful disconnection'));
      expect(find.text('DN-2026-0910-0033'), findsOneWidget);
      expect(find.text('₱541.20'), findsOneWidget);
      // Midnight UTC on the 14th is 8 in the morning in Tubod.
      expect(find.text('14 Sep 2026 · 8:00 AM'), findsOneWidget);
    },
  );

  testWidgets('a notice closed since says it is no longer active', (
    WidgetTester tester,
  ) async {
    await open(tester, <AppNotification>[disconnection]);

    await tester.tap(find.text('Disconnection notice served'));
    await tester.pumpAndSettle();

    await scrollSheetTo(tester, find.textContaining('no longer active'));
    expect(find.textContaining('no longer active'), findsOneWidget);
  });

  testWidgets('a bill that cannot load offers to try again', (
    WidgetTester tester,
  ) async {
    bills.byIdFailure = const NetworkFailure();
    await open(tester, <AppNotification>[ready]);

    await tester.tap(find.text('Your bill is ready'));
    await tester.pumpAndSettle();

    await scrollSheetTo(tester, find.text('Try again'));
    expect(find.textContaining('loaded right now'), findsOneWidget);
    // The notification itself is still all there.
    expect(find.text('Shown on your phone'), findsOneWidget);
  });
}
