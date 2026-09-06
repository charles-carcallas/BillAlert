import '../../../core/errors/app_failure.dart';
import '../../../core/result/result.dart';
import '../../entities/consumer.dart';
import '../../outbox/outbox_operation.dart';
import '../../repositories/outbox_repository.dart';
import '../../repositories/reading_repository.dart';
import '../../time/ph_clock.dart';
import '../../value_objects/cycle_label.dart';
import '../../value_objects/ids.dart';
import '../../value_objects/kwh.dart';
import '../../value_objects/ph_date.dart';

/// What the screen shows once a reading has been written down.
///
/// There is no amount here, and there is no due date. A reading creates an
/// unpriced bill; the cooperative sends the peso figure about a week later.
final class RecordedReading {
  final ConsumerId consumerId;
  final String consumerLabel;
  final Kwh previousReading;
  final Kwh currentReading;
  final Kwh consumption;
  final CycleLabel cycle;
  final PhDate readingDate;
  final ClientUuid clientUuid;

  const RecordedReading({
    required this.consumerId,
    required this.consumerLabel,
    required this.previousReading,
    required this.currentReading,
    required this.consumption,
    required this.cycle,
    required this.readingDate,
    required this.clientUuid,
  });
}

/// FR-21a — the meter reader records a reading at the meter.
///
/// This is the offline decision point of the whole application. The reading
/// is written to the outbox on this device, and only then is the reader told
/// it is saved. Nothing here waits for the network, because the reader is
/// usually standing somewhere without any.
///
/// The three checks below are also enforced by `fn_record_meter_reading` on
/// the server, which is the real guarantee. They are repeated here for one
/// reason: the reader is holding the phone in front of the meter right now,
/// and a duplicate or a mistyped digit discovered an hour later at sync time
/// means walking back.
///
/// Nothing in this file computes money. It subtracts two meter readings to
/// get kilowatt-hours, and that is the only arithmetic in it.
final class RecordMeterReading {
  final ReadingRepository readings;
  final OutboxRepository outbox;
  final PhClock clock;
  final ClientUuidFactory newClientUuid;

  const RecordMeterReading({
    required this.readings,
    required this.outbox,
    required this.clock,
    required this.newClientUuid,
  });

  Future<Result<RecordedReading>> call({
    required Consumer consumer,
    required Kwh currentReading,
  }) async {
    // An inactive or pending account is not read and not billed.
    if (!consumer.isActive) {
      return Err(ValidationFailure(
        '${consumer.fullName} is not an active account, so no reading can be '
        'recorded. Ask your Area President to check the account first.',
      ));
    }

    final today = clock.today();
    final cycle = CycleLabel.of(today);

    // FR-23, part one: the server already has a reading for this cycle.
    if (consumer.hasBeenReadFor(cycle)) {
      return Err(ConflictFailure(
        '${consumer.fullName} has already been read for ${cycle.displayName}.',
      ));
    }

    // FR-23, part two: a reading is already queued on this phone. Without
    // this check a reader with no signal could record the same house twice
    // and only find out at sync.
    final queuedResult = await readings.isReadingQueuedFor(
      consumerId: consumer.id,
      cycle: cycle,
    );
    switch (queuedResult) {
      case Err(:final failure):
        return Err(failure);
      case Ok(:final value):
        if (value) {
          return Err(ConflictFailure(
            'You already recorded a reading for ${consumer.fullName} this '
            'month. It is still waiting to sync.',
          ));
        }
    }

    // MTR-08: a meter does not run backwards, so this is a mistyped digit.
    if (!consumer.isPlausibleReading(currentReading)) {
      return Err(ValidationFailure(
        '${currentReading.format()} is lower than the last reading of '
        '${consumer.previousReading.format()}. Please check the digits on '
        'the meter.',
      ));
    }

    // The capture time is recorded now and sent to the server as it is. The
    // server must attribute the reading to this moment, not to whenever the
    // phone next finds signal.
    final capturedAt = clock.nowUtc();

    final operation = RecordReadingOperation(
      clientUuid: newClientUuid(),
      capturedAt: capturedAt,
      consumerId: consumer.id,
      currentReading: currentReading,
      cycleLabel: cycle,
      consumerLabel: consumer.fullName,
    );

    // Durable first, confirmation second. If the app is killed on the next
    // line, the reading is still on the phone.
    final enqueued = await outbox.enqueue(operation);
    switch (enqueued) {
      case Err(:final failure):
        return Err(failure);
      case Ok():
        break;
    }

    return Ok(RecordedReading(
      consumerId: consumer.id,
      consumerLabel: consumer.fullName,
      previousReading: consumer.previousReading,
      currentReading: currentReading,
      consumption: consumer.consumptionFor(currentReading),
      cycle: cycle,
      readingDate: PhDate.at(capturedAt),
      clientUuid: operation.clientUuid,
    ));
  }
}
