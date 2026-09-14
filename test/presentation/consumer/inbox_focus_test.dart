import 'package:billalert/domain/entities/app_user.dart';
import 'package:billalert/domain/notifications/phone_alerts.dart';
import 'package:billalert/domain/repositories/notification_repository.dart';
import 'package:billalert/domain/usecases/consumer/open_tapped_notice.dart';
import 'package:billalert/domain/value_objects/ids.dart';
import 'package:billalert/presentation/auth/auth_controller.dart';
import 'package:billalert/presentation/consumer/inbox_controller.dart';
import 'package:billalert/presentation/consumer/inbox_focus.dart';
import 'package:billalert/presentation/consumer/inbox_screen.dart';
import 'package:billalert/presentation/providers.dart';
import 'package:billalert/presentation/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';

/// The household's inbox with these rows, and nothing loaded from a server.
class _FixedInbox extends InboxController {
  final List<AppNotification> alerts;

  _FixedInbox(this.alerts);

  @override
  InboxState build() => InboxState(alerts: alerts);
}

/// The Inbox opened by a tapped notification.
class _Focused extends InboxFocusController {
  final InboxFocus initial;

  _Focused(this.initial);

  @override
  InboxFocus build() => initial;
}

class _NotificationsOn implements NotificationPermission {
  @override
  Future<bool> isGranted() async => true;

  @override
  Future<bool> request() async => true;

  @override
  Future<void> openSettings() async {}
}

/// The Inbox half of "open the app at the related notice": pointing at the
/// notice, and saying so when it is not one of this household's.
void main() {
  const ConsumerUser household = ConsumerUser(
    id: ProfileId('consumer-profile-1'),
    username: 'virgilio.busalanan',
    firstName: 'Virgilio',
    lastName: 'Busalanan',
    mustChangePassword: false,
  );

  final AppNotification ready = AppNotification(
    id: const NotificationId('n-1'),
    type: 'bill_ready',
    channel: 'push',
    message: 'Your August 2026 bill is ready.',
    isRead: true,
    createdAt: DateTime.utc(2026, 9, 9),
  );

  final AppNotification served = AppNotification(
    id: const NotificationId('n-2'),
    type: 'disconnection',
    channel: 'sms',
    message: 'A disconnection notice was served.',
    isRead: false,
    createdAt: DateTime.utc(2026, 9, 10),
  );

  const String notHere = "That notification isn't on this account.";

  Future<void> open(WidgetTester tester, InboxFocus focus) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(
            () => FakeAuthController(signedInUser: household),
          ),
          inboxControllerProvider.overrideWith(
            () => _FixedInbox(<AppNotification>[ready, served]),
          ),
          notificationPermissionProvider.overrideWithValue(_NotificationsOn()),
          inboxFocusProvider.overrideWith(() => _Focused(focus)),
        ],
        child: MaterialApp(theme: AppTheme.light(), home: const InboxScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the tapped notice is highlighted, even outside the filter', (
    WidgetTester tester,
  ) async {
    await open(tester, const InboxFocus(highlight: NotificationId('n-1')));

    expect(find.byKey(const ValueKey<String>('inbox-highlighted')), findsOne);
    expect(find.text(notHere), findsNothing);

    // n-1 is already read, so "Unread" would hide it. The notice the
    // household tapped must not disappear because of a filter.
    await tester.tap(find.text('Unread (1)'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('inbox-highlighted')), findsOne);
  });

  testWidgets("a notice that is not this household's says so", (
    WidgetTester tester,
  ) async {
    // Shown to one household, tapped after another signed in on the phone.
    await open(tester, const InboxFocus(highlight: NotificationId('n-999')));

    expect(find.text(notHere), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('inbox-highlighted')),
      findsNothing,
    );
  });

  testWidgets('a bill that could not be opened explains why, until dismissed', (
    WidgetTester tester,
  ) async {
    await open(
      tester,
      const InboxFocus(explanation: OpenTappedNotice.couldNotOpen),
    );

    expect(find.text(OpenTappedNotice.couldNotOpen), findsOneWidget);

    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pumpAndSettle();

    expect(find.text(OpenTappedNotice.couldNotOpen), findsNothing);
  });
}
