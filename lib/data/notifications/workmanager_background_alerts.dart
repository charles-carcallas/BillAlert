import 'dart:ui' show DartPluginRegistrant;

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workmanager/workmanager.dart';

import '../../core/config/app_config.dart';
import '../../domain/notifications/phone_alerts.dart';
import '../../domain/time/ph_clock.dart';
import '../../domain/usecases/consumer/refresh_phone_alerts.dart';
import 'android_phone_notifier.dart';
import 'supabase_alert_feed.dart';

const String _uniqueName = 'billalert-phone-alerts';
const String _taskName = 'refresh-phone-alerts';

/// What Android runs, in a fresh isolate with no app on screen.
///
/// Top-level and marked as an entry point, or the release build's tree
/// shaking removes it and the check silently never runs.
@pragma('vm:entry-point')
void phoneAlertsCallbackDispatcher() {
  Workmanager().executeTask((String task, Map<String, dynamic>? input) async {
    try {
      // Plugins implemented in Dart, such as the shared preferences that hold
      // the saved session, are not registered in a background isolate until
      // this is called.
      DartPluginRegistrant.ensureInitialized();

      if (!AppConfig.isConfigured || AppConfig.demoMode) return true;

      await Supabase.initialize(
        url: AppConfig.supabaseUrl,
        publishableKey: AppConfig.supabaseAnonKey,
        // No screen, so no sign-in link can arrive, and the deep-link
        // listener this would otherwise start needs one.
        authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
      );

      final AndroidPhoneNotifier phone = AndroidPhoneNotifier();
      await phone.initialize();

      await RefreshPhoneAlerts(
        feed: SupabaseAlertFeed(Supabase.instance.client),
        phone: phone,
        clock: const SystemPhClock(),
      )();
    } catch (_) {
      // Nothing to show anyone from here. The next period tries again.
    }
    // True even after a failure. False asks WorkManager to retry on a backoff,
    // which for a check that already repeats every period only adds runs.
    return true;
  });
}

/// Starts and stops the background check.
///
/// Every fifteen minutes is Android's floor, and a floor only: Android runs it
/// less often when the phone is idle, on low battery, or when BillAlert has
/// not been opened for a while, and some manufacturers' battery savers block
/// it unless background activity is allowed for the app.
class WorkmanagerBackgroundAlerts implements BackgroundAlerts {
  const WorkmanagerBackgroundAlerts();

  @override
  Future<void> start() async {
    try {
      await Workmanager().initialize(phoneAlertsCallbackDispatcher);
      await Workmanager().registerPeriodicTask(
        _uniqueName,
        _taskName,
        frequency: const Duration(minutes: 15),
        constraints: Constraints(networkType: NetworkType.connected),
        // Keep: opening the app again must not restart the fifteen-minute
        // clock every time.
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      );
    } catch (_) {}
  }

  @override
  Future<void> stop() async {
    try {
      await Workmanager().cancelByUniqueName(_uniqueName);
    } catch (_) {}
  }
}
