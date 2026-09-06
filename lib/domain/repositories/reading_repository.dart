import '../../core/result/result.dart';
import '../value_objects/cycle_label.dart';
import '../value_objects/ids.dart';

/// Meter readings that have been captured on this device.
///
/// Deliberately narrow. Recording a reading goes through the outbox, not
/// through here; what this interface answers is the FR-23 question the reader
/// needs settled before typing anything: has this house been done this month?
abstract class ReadingRepository {
  /// Consumers with a reading already queued for [cycle] on this device.
  Future<Result<Set<ConsumerId>>> queuedConsumerIdsFor(CycleLabel cycle);

  /// FR-23, asked about one consumer. Checked at the meter, not at sync an
  /// hour later, because by then the reader has walked away.
  Future<Result<bool>> isReadingQueuedFor({
    required ConsumerId consumerId,
    required CycleLabel cycle,
  });
}
