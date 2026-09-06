import '../value_objects/cycle_label.dart';
import '../value_objects/ids.dart';
import 'consumer.dart';

/// One household on the roster, and whether this cycle's reading is done.
final class RosterEntry {
  final Consumer consumer;

  /// True when a reading for this consumer and cycle is sitting in the
  /// outbox, captured but not yet uploaded.
  final bool isQueuedForSync;

  /// True when the server already has this cycle's reading.
  final bool isSynced;

  const RosterEntry({
    required this.consumer,
    required this.isQueuedForSync,
    required this.isSynced,
  });

  /// MTR-11: the reader has visited this house, whether or not the phone has
  /// managed to tell the server about it.
  bool get isDone => isSynced || isQueuedForSync;
}

/// The meter reader's assigned area for one billing cycle.
///
/// The counters live here rather than in the screen because they are the
/// answer to a domain question — "how much of my round is left?" — and they
/// have to count queued work as done. A dashboard that only counted synced
/// readings would tell a reader with no signal that they still have 40 houses
/// to visit when they have already walked all of them.
final class AreaRoster {
  final AreaId areaId;
  final CycleLabel cycle;
  final List<RosterEntry> entries;

  const AreaRoster({
    required this.areaId,
    required this.cycle,
    required this.entries,
  });

  int get totalConsumers => entries.length;

  int get readCount => entries.where((RosterEntry e) => e.isDone).length;

  int get remainingCount => totalConsumers - readCount;

  int get completionPercent =>
      totalConsumers == 0 ? 0 : (readCount * 100 / totalConsumers).round();

  bool get isComplete => totalConsumers > 0 && remainingCount == 0;

  /// The houses still to visit, in the order the roster is walked.
  List<RosterEntry> get remaining =>
      entries.where((RosterEntry e) => !e.isDone).toList();

  /// How many readings are captured but not yet uploaded.
  int get waitingToSync =>
      entries.where((RosterEntry e) => e.isQueuedForSync).length;
}
