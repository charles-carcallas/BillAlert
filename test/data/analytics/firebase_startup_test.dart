import 'dart:async';

import 'package:billalert/data/analytics/firebase_startup.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('initializes Firebase on Android', () async {
    var calls = 0;
    await initializeOptionalFirebase(
      isWeb: false,
      platform: TargetPlatform.android,
      initialize: () async {
        calls++;
      },
    );
    expect(calls, 1);
  });

  test('skips web even when target platform is Android', () async {
    var calls = 0;
    await initializeOptionalFirebase(
      isWeb: true,
      platform: TargetPlatform.android,
      initialize: () async {
        calls++;
      },
    );
    expect(calls, 0);
  });

  test('skips every unconfigured native platform', () async {
    var calls = 0;
    for (final platform in TargetPlatform.values) {
      if (platform == TargetPlatform.android) continue;
      await initializeOptionalFirebase(
        isWeb: false,
        platform: platform,
        initialize: () async {
          calls++;
        },
      );
    }
    expect(calls, 0);
  });

  test('SDK failure does not escape into app startup', () async {
    await initializeOptionalFirebase(
      isWeb: false,
      platform: TargetPlatform.android,
      initialize: () async {
        throw StateError('SDK unavailable');
      },
    );
  });

  test('delayed SDK failure is also contained', () async {
    final completion = Completer<void>();
    final startup = initializeOptionalFirebase(
      isWeb: false,
      platform: TargetPlatform.android,
      initialize: () => completion.future,
    );
    completion.completeError(StateError('Delayed failure'));
    await startup;
  });
}
