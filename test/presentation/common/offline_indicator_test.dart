import 'dart:async';

import 'package:billalert/data/network/network_status.dart';
import 'package:billalert/presentation/common/offline_indicator.dart';
import 'package:billalert/presentation/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late StreamController<bool> link;
  late NetworkStatus status;

  Future<void> pump(WidgetTester tester) async {
    // Made inside the test, so the indicator's hide timer runs on the test's
    // fake clock rather than a real one.
    link = StreamController<bool>();
    status = NetworkStatus(
      linkChanges: link.stream,
      checkLink: () async => true,
    );
    addTearDown(link.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [networkStatusProvider.overrideWithValue(status)],
        child: const MaterialApp(
          home: Scaffold(bottomNavigationBar: OfflineIndicator()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows nothing while online', (WidgetTester tester) async {
    await pump(tester);

    expect(find.textContaining("You're offline"), findsNothing);
    expect(find.text('Back online'), findsNothing);
  });

  testWidgets('appears when the phone loses its network link', (
    WidgetTester tester,
  ) async {
    await pump(tester);

    link.add(false);
    await tester.pumpAndSettle();

    expect(find.textContaining("You're offline"), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('appears when requests stop getting through on a live link', (
    WidgetTester tester,
  ) async {
    await pump(tester);

    status.reportUnreachable();
    await tester.pumpAndSettle();

    expect(find.textContaining("You're offline"), findsOneWidget);
  });

  testWidgets('says "Back online" on return, then folds away', (
    WidgetTester tester,
  ) async {
    await pump(tester);
    link.add(false);
    await tester.pumpAndSettle();

    link.add(true);
    // Settles the swap animation; the 2.5 s hide timer is not a frame, so
    // this does not run past it.
    await tester.pumpAndSettle();
    expect(find.text('Back online'), findsOneWidget);
    expect(find.textContaining("You're offline"), findsNothing);

    await tester.pump(OfflineIndicator.backOnlineFor);
    await tester.pumpAndSettle();
    expect(find.text('Back online'), findsNothing);
  });
}
