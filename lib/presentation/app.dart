import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import 'appearance_controller.dart';
import 'router.dart';
import 'theme.dart';

/// The app itself, once Supabase has been initialised.
class BillAlertApp extends ConsumerWidget {
  const BillAlertApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'BillAlert',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode:
          ref.watch(appearanceControllerProvider).value ?? ThemeMode.system,
      routerConfig: ref.watch(routerProvider),
      builder: (BuildContext context, Widget? child) => AppConfig.demoMode
          ? Banner(
              message: 'DEMO DATA',
              location: BannerLocation.topEnd,
              child: child ?? const SizedBox.shrink(),
            )
          : child ?? const SizedBox.shrink(),
    );
  }
}

/// Shown when the app was built without the Supabase dart-defines.
///
/// This is the most common first-run mistake, and a blank screen with a
/// network error tells nobody what to do about it. The message names the
/// flags that are missing.
class MissingConfigApp extends StatelessWidget {
  final String message;

  const MissingConfigApp({required this.message, super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BillAlert',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(Icons.settings, size: 48),
                  const SizedBox(height: 16),
                  const Text(
                    'BillAlert is not configured',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  Text(message, textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
