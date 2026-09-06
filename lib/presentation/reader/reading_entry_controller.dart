import 'dart:async';

// `Consumer` here means a household, which is the domain's word for it.
// Riverpod's Consumer widget is not used in this file, so it is hidden
// rather than the entity being renamed to suit a package.
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Consumer;

import '../../core/errors/app_failure.dart';
import '../../core/result/result.dart';
import '../../domain/entities/consumer.dart';
import '../../domain/usecases/reader/record_meter_reading.dart';
import '../../domain/value_objects/ids.dart';
import '../../domain/value_objects/kwh.dart';
import '../providers.dart';
import 'roster_controller.dart';

/// The state of the reading entry screen.
final class ReadingEntryState {
  final bool isSaving;
  final AppFailure? failure;
  final RecordedReading? saved;

  const ReadingEntryState({
    this.isSaving = false,
    this.failure,
    this.saved,
  });
}

/// Recording one reading.
///
/// The screen hands over the text the reader typed; everything after that is
/// this class calling one use case. There is no Supabase call here, and there
/// is no "if online then upload else queue" — the offline path is the only
/// path, so it cannot rot from disuse.
class ReadingEntryController extends Notifier<ReadingEntryState> {
  @override
  ReadingEntryState build() => const ReadingEntryState();

  Future<void> save({
    required Consumer consumer,
    required String enteredReading,
  }) async {
    // Turning text into a Kwh is the value object's job, and refusing bad
    // text is part of it. Doing it here keeps the widget free of parsing
    // rules and gives the reader a message written for them.
    final reading = Kwh.tryParse(enteredReading);
    if (reading == null) {
      state = const ReadingEntryState(
        failure: ValidationFailure(
          'Enter the reading as it appears on the meter, for example 1392 '
          'or 1392.50.',
        ),
      );
      return;
    }

    state = const ReadingEntryState(isSaving: true);

    final result = await ref.read(recordMeterReadingProvider)(
      consumer: consumer,
      currentReading: reading,
    );

    switch (result) {
      case Ok(:final value):
        state = ReadingEntryState(saved: value);
        // The reading is already safe on the phone. Trying to upload it is a
        // bonus, so it is not awaited and its failure is not shown: there is
        // nothing for the reader to do about it, and they have a next house
        // to get to.
        unawaited(ref.read(syncServiceProvider).syncNow());
        // The roster's counters have to include this house immediately, even
        // though nothing has been uploaded.
        ref.invalidate(rosterControllerProvider);

      case Err(:final failure):
        state = ReadingEntryState(failure: failure);
    }
  }

  void dismissFailure() {
    state = const ReadingEntryState();
  }
}

final readingEntryControllerProvider =
    NotifierProvider<ReadingEntryController, ReadingEntryState>(
  ReadingEntryController.new,
);

/// One household from the cache, for the entry screen.
final consumerByIdProvider =
    FutureProvider.family<Consumer?, String>((Ref ref, String id) async {
  final result = await ref.watch(consumerRepositoryProvider).byId(ConsumerId(id));
  return switch (result) {
    Ok(:final value) => value,
    Err(:final failure) => throw failure,
  };
});
