import 'package:billalert/domain/value_objects/kwh.dart';
import 'package:billalert/domain/value_objects/ph_date.dart';
import 'package:billalert/presentation/providers.dart';
import 'package:billalert/presentation/reader/reading_entry_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';

void main() {
  testWidgets('reading is queued only after the reader confirms its values', (
    WidgetTester tester,
  ) async {
    final consumer = household(previousReading: Kwh.of(1250));
    final consumers = FakeConsumerRepository([consumer]);
    final readings = FakeReadingRepository();
    final outbox = FakeOutboxRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          consumerRepositoryProvider.overrideWithValue(consumers),
          readingRepositoryProvider.overrideWithValue(readings),
          outboxRepositoryProvider.overrideWithValue(outbox),
          syncServiceProvider.overrideWithValue(FakeSyncService()),
          phClockProvider.overrideWithValue(
            FixedPhClock.onPhDate(const PhDate(2026, 9, 13)),
          ),
          clientUuidFactoryProvider.overrideWithValue(
            CountingUuidFactory().call,
          ),
        ],
        child: MaterialApp(
          home: ReadingEntryScreen(consumerId: consumer.id.value),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '1300');
    await tester.tap(find.text('Save reading'));
    await tester.pumpAndSettle();

    expect(find.text('Confirm meter reading'), findsOneWidget);
    expect(find.text('Elena Ravelo'), findsWidgets);
    expect(find.text('Previous reading'), findsWidgets);
    expect(find.text('Present reading'), findsWidgets);
    expect(find.text('Consumption'), findsWidgets);
    expect(outbox.enqueued, isEmpty);

    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();
    expect(outbox.enqueued, isEmpty);

    await tester.tap(find.text('Save reading'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Save reading'),
      ),
    );
    await tester.pumpAndSettle();

    expect(outbox.enqueued, hasLength(1));
  });
}
