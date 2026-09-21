import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../../firebase_options.dart';

/// Optional telemetry must never gate authentication or offline work.
/// Analytics' native SDK collects standard events; no household data or
/// authenticated user identifiers are attached here.
Future<void> initializeOptionalFirebase({
  Future<void> Function()? initialize,
  bool? isWeb,
  TargetPlatform? platform,
}) async {
  if ((isWeb ?? kIsWeb) ||
      (platform ?? defaultTargetPlatform) != TargetPlatform.android) {
    return;
  }
  try {
    if (initialize != null) {
      await initialize();
    } else {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  } catch (_) {
    // Do not log raw SDK errors or configuration values.
    debugPrint('Optional Firebase initialization failed; BillAlert continues.');
  }
}
