import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config/app_config.dart';
import 'presentation/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // The URL and the anon key arrive as --dart-define values and are read in
  // exactly one place. Nothing about them is committed to the repository.
  if (!AppConfig.isConfigured) {
    runApp(const MissingConfigApp(message: AppConfig.missingConfigMessage));
    return;
  }

  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    // Supabase now calls this the publishable key; the dashboard and every
    // tutorial still label it "anon key", so the dart-define keeps that name.
    publishableKey: AppConfig.supabaseAnonKey,
  );

  runApp(const ProviderScope(child: BillAlertApp()));
}
