import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/notifications/phone_alerts.dart';
import '../../domain/usecases/consumer/open_tapped_notice.dart';
import '../providers.dart';
import 'bill_details_sheet.dart';
import 'inbox_focus.dart';

/// Keeps a household's phone told about its bills, while the app is open and
/// after it is closed, and opens the right bill or notice when one is tapped.
///
/// It wraps the household's tabs, so it only exists after signing in and
/// after the fingerprint lock. A tap is then checked against whoever is signed
/// in at that moment — see OpenTappedNotice — before anything is shown.
class PhoneAlertsGate extends ConsumerStatefulWidget {
  final Widget child;

  const PhoneAlertsGate({required this.child, super.key});

  @override
  ConsumerState<PhoneAlertsGate> createState() => _PhoneAlertsGateState();
}

class _PhoneAlertsGateState extends ConsumerState<PhoneAlertsGate> {
  /// Android keeps the notification that launched the app for the life of the
  /// process. Without this, signing out and back in would follow it again.
  static bool _launchHandled = false;

  /// Asked once per run of the app. Android itself stops showing the prompt
  /// after a second "Don't allow", and the Inbox explains how to turn
  /// notifications on after that.
  static bool _permissionAsked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startAlerts());
  }

  @override
  Widget build(BuildContext context) => widget.child;

  Future<void> _startAlerts() async {
    try {
      if (!mounted) return;
      final PhoneNotifier phone = ref.read(phoneNotifierProvider);
      await phone.initialize(onTap: _open);

      if (!_launchHandled) {
        _launchHandled = true;
        final String? payload = await phone.launchPayload();
        if (payload != null) await _open(payload);
      }

      if (!mounted) return;
      if (!_permissionAsked) {
        _permissionAsked = true;
        await ref.read(notificationPermissionProvider).request();
      }

      if (!mounted) return;
      await ref.read(backgroundAlertsProvider).start();

      // Once now, not in fifteen minutes: a household that opens the app to
      // look at a new bill gets its due-date reminder scheduled straight away.
      if (!mounted) return;
      await ref.read(refreshPhoneAlertsProvider)();
    } catch (_) {
      // Notifications are a convenience on top of the Bill and Inbox tabs,
      // which show the same facts. A phone that cannot notify must not stop
      // the household using the app.
    }
  }

  /// A tapped notification: open its bill, or the Inbox at its notice.
  Future<void> _open(String? payload) async {
    try {
      if (!mounted) return;
      final TappedNoticeDestination destination = await ref.read(
        openTappedNoticeProvider,
      )(payload);
      if (!mounted) return;

      switch (destination) {
        case ShowBill(:final bill):
          // The bill sheet's home is History, so it opens over that tab and
          // closing it leaves the household somewhere that makes sense.
          context.go('/consumer/history');
          await WidgetsBinding.instance.endOfFrame;
          if (!mounted) return;
          await showConsumerBillDetails(
            context,
            bill: bill,
            today: ref.read(phClockProvider).today(),
          );
        case ShowInbox(:final highlight, :final explanation):
          ref
              .read(inboxFocusProvider.notifier)
              .focus(highlight: highlight, explanation: explanation);
          context.go('/consumer/inbox');
      }
    } catch (_) {
      // A tap that cannot be followed leaves the household where they are,
      // which is still inside their own account.
    }
  }
}
