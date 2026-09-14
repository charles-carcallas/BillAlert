import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/notifications/phone_alerts.dart';
import '../providers.dart';
import '../router.dart';

/// Keeps a household's phone told about its bills, while the app is open and
/// after it is closed.
///
/// It wraps the household's tabs, so it only exists after signing in and
/// after the fingerprint lock. A tapped notification can therefore only ever
/// open the signed-in household's own tabs, whose rows row-level security
/// already limits to that household.
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
        if (payload != null) _open(payload);
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

  void _open(String? payload) {
    if (!mounted) return;
    switch (payload) {
      case PhoneNoticePayload.inbox:
        context.go('/consumer/inbox');
      case PhoneNoticePayload.bill:
        context.go(Routes.consumer);
    }
  }
}
