import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config/app_config.dart';
import 'data/network/fail_fast_http_client.dart';
import 'data/network/network_status.dart';
import 'demo/demo_environment.dart';
import 'presentation/app.dart';
import 'presentation/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // The URL and the anon key arrive as --dart-define values and are read in
  // exactly one place. Nothing about them is committed to the repository.
  if (!AppConfig.isConfigured) {
    runApp(const MissingConfigApp(message: AppConfig.missingConfigMessage));
    return;
  }

  // One instance, shared by the HTTP client that reports to it and the
  // offline indicator that shows it.
  final NetworkStatus networkStatus = NetworkStatus();

  if (!AppConfig.demoMode) {
    final FailFastHttpClient httpClient = FailFastHttpClient(networkStatus);
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      // Supabase now calls this the publishable key; the dashboard and every
      // tutorial still label it "anon key", so the dart-define keeps that
      // name.
      publishableKey: AppConfig.supabaseAnonKey,
      // Fails at once with no signal and gives up on a stalled server, so
      // screens fall back to the phone's cache without a long spinner.
      httpClient: httpClient,
    );
    // "Retry" on the offline bar asks the server directly. Any HTTP answer at
    // all, even a refusal, proves it can be reached.
    networkStatus.pingServer = () async {
      try {
        await httpClient.head(Uri.parse('${AppConfig.supabaseUrl}/rest/v1/'));
      } catch (_) {}
    };
  }

  runApp(
    ProviderScope(
      overrides: <Override>[
        networkStatusProvider.overrideWith((Ref ref) => networkStatus),
        if (AppConfig.demoMode) ...demoProviderOverrides(),
      ],
      child: const BillAlertApp(),
    ),
  );
}
