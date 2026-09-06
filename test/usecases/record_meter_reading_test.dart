import 'package:billalert/core/errors/app_failure.dart';
import 'package:billalert/core/result/result.dart';
import 'package:billalert/domain/entities/consumer.dart';
import 'package:billalert/domain/outbox/outbox_operation.dart';
import 'package:billalert/domain/usecases/reader/record_meter_reading.dart';
import 'package:billalert/domain/value_objects/cycle_label.dart';
import 'package:billalert/domain/value_objects/ids.dart';
import 'package:billalert/domain/value_objects/kwh.dart';
import 'package:billalert/domain/value_objects/ph_date.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

/// The vertical slice, tested with no network, no database and no Flutter.
///
/// Every collaborator below is a plain Dart class written by hand in
/// `test/support/fakes.dart`. That is the point of putting the repository
/// interfaces in `domain/`: this use case has never heard of Supabase, so
/// nothing has to be started, stubbed or mocked to exercise it.
void main() {
  late FakeOutboxRepository outbox;
  late FakeReadingRepository readings;
  late CountingUuidFactory uuids;
  late RecordMeterReading recordReading;

  const today = PhDate(2026, 9, 13);
  const cycle = CycleLabel(2026, 9);

  setUp(() {
    outbox = FakeOutboxRepository();
    readings = FakeReadingRepository();
    uuids = CountingUuidFactory();
    recordReading = RecordMeterReading(
      readings: readings,
      outbox: outbox,
      clock: FixedPhClock.onPhDate(today),
      newClientUuid: uuids.call,
    );
  });

  group('recording a reading', () {
    test('queues the reading and reports the consumption', () async {
      final result = await recordReading(
        consumer: household(previousReading: Kwh.of(1250)),
        currentReading: Kwh.of(1392),
      );

      expect(result, isA<Ok<RecordedReading>>());
      final recorded = (result as Ok<RecordedReading>).value;

      // 1392 - 1250. Energy, not pesos.
      expect(recorded.consumption, Kwh.of(142));
      expect(recorded.previousReading, Kwh.of(1250));
      expect(recorded.cycle, cycle);
      expect(recorded.readingDate, today);
    });

    test('writes to the outbox before returning', () async {
      await recordReading(
        consumer: household(),
        currentReading: Kwh.of(1392),
      );

      // The screen confirms from this write, not from a network round trip.
      expect(outbox.enqueued, hasLength(1));
      final operation = outbox.enqueued.single;
      expect(operation, isA<RecordReadingOperation>());
      expect(operation.operationCode, 'record_reading');
    });

    test('the queued operation carries the cycle and the capture time',
        () async {
      await recordReading(
        consumer: household(),
        currentReading: Kwh.of(1392),
      );

      final operation = outbox.enqueued.single as RecordReadingOperation;
      expect(operation.cycleLabel, cycle);
      expect(operation.currentReading, Kwh.of(1392));
      // captured_at is the moment of capture. The 48-hour notice period and
      // the billing cycle both depend on the server seeing this, not the
      // time the phone happened to find signal.
      expect(PhDate.at(operation.capturedAt), today);
    });

    test('the client uuid is minted once and travels with the operation',
        () async {
      final result = await recordReading(
        consumer: household(),
        currentReading: Kwh.of(1392),
      );

      final recorded = (result as Ok<RecordedReading>).value;
      final operation = outbox.enqueued.single;
      expect(operation.clientUuid, const ClientUuid('test-uuid-1'));
      expect(recorded.clientUuid, operation.clientUuid);
    });

    test('the payload serialises the reading as a decimal string', () async {
      await recordReading(
        consumer: household(),
        currentReading: Kwh.parse('1392.50'),
      );

      final payload = outbox.enqueued.single.toPayloadJson();
      expect(payload['current_reading'], '1392.50');
      expect(payload['cycle_label'], '2026-09');
    });
  });

  group('FR-23 - one reading per household per cycle', () {
    test('refuses a household the server has already recorded', () async {
      final result = await recordReading(
        consumer: household(lastReadCycle: cycle),
        currentReading: Kwh.of(1392),
      );

      expect(result, isA<Err<RecordedReading>>());
      final failure = (result as Err<RecordedReading>).failure;
      expect(failure, isA<ConflictFailure>());
      expect(failure.message, contains('already been read'));
      expect(outbox.enqueued, isEmpty);
    });

    test('refuses a household already queued on this phone', () async {
      // The reader recorded this house an hour ago and still has no signal.
      readings.markQueued(const ConsumerId('consumer-1'), cycle);

      final result = await recordReading(
        consumer: household(),
        currentReading: Kwh.of(1392),
      );

      final failure = (result as Err<RecordedReading>).failure;
      expect(failure, isA<ConflictFailure>());
      expect(failure.message, contains('waiting to sync'));
      expect(outbox.enqueued, isEmpty);
    });

    test('allows the same household in a different cycle', () async {
      final result = await recordReading(
        consumer: household(lastReadCycle: const CycleLabel(2026, 8)),
        currentReading: Kwh.of(1392),
      );

      expect(result, isA<Ok<RecordedReading>>());
    });
  });

  group('MTR-08 - a meter does not run backwards', () {
    test('refuses a reading below the previous one', () async {
      final result = await recordReading(
        consumer: household(previousReading: Kwh.of(1250)),
        currentReading: Kwh.of(1150),
      );

      final failure = (result as Err<RecordedReading>).failure;
      expect(failure, isA<ValidationFailure>());
      // The message has to be usable by someone standing at the meter.
      expect(failure.message, contains('lower than the last reading'));
      expect(outbox.enqueued, isEmpty);
    });

    test('allows a reading equal to the previous one', () async {
      // A household that used nothing all month. Zero consumption is real.
      final result = await recordReading(
        consumer: household(previousReading: Kwh.of(1250)),
        currentReading: Kwh.of(1250),
      );

      expect(result, isA<Ok<RecordedReading>>());
      expect((result as Ok<RecordedReading>).value.consumption, Kwh.zero);
    });
  });

  group('accounts that cannot be read', () {
    test('refuses an inactive household', () async {
      final result = await recordReading(
        consumer: household(status: AccountStatus.inactive),
        currentReading: Kwh.of(1392),
      );

      expect((result as Err<RecordedReading>).failure, isA<ValidationFailure>());
      expect(outbox.enqueued, isEmpty);
    });
  });

  group('when the phone cannot save', () {
    test('the failure reaches the caller and nothing is reported as saved',
        () async {
      outbox.failNextWith = const ServerFailure('Could not save to this phone.');

      final result = await recordReading(
        consumer: household(),
        currentReading: Kwh.of(1392),
      );

      expect(result, isA<Err<RecordedReading>>());
      expect((result as Err<RecordedReading>).failure, isA<ServerFailure>());
    });
  });
}
