import '../../../core/result/result.dart';
import '../../entities/area_roster.dart';
import '../../entities/consumer.dart';
import '../../repositories/consumer_repository.dart';
import '../../repositories/reading_repository.dart';
import '../../time/ph_clock.dart';
import '../../value_objects/cycle_label.dart';
import '../../value_objects/ids.dart';

/// MTR-11 — the meter reader opens their round for this cycle.
///
/// Reads from the encrypted cache only. It must work with no signal, so it
/// never touches the network; [RefreshAreaRoster] is the separate, explicitly
/// online action behind pull-to-refresh.
///
/// A house counts as done when the server has its reading *or* when one is
/// still sitting in the outbox. Counting only synced readings would tell a
/// reader with no signal that they still have 40 houses left when they have
/// already walked all of them.
final class LoadAreaRoster {
  final ConsumerRepository consumers;
  final ReadingRepository readings;
  final PhClock clock;

  const LoadAreaRoster({
    required this.consumers,
    required this.readings,
    required this.clock,
  });

  Future<Result<AreaRoster>> call({required AreaId areaId}) async {
    final cycle = CycleLabel.of(clock.today());

    final List<Consumer> households;
    switch (await consumers.areaRoster(areaId)) {
      case Err(:final failure):
        return Err(failure);
      case Ok(:final value):
        households = value;
    }

    final Set<ConsumerId> queued;
    switch (await readings.queuedConsumerIdsFor(cycle)) {
      case Err(:final failure):
        return Err(failure);
      case Ok(:final value):
        queued = value;
    }

    final entries = households
        .where((Consumer c) => c.isActive)
        .map((Consumer c) => RosterEntry(
              consumer: c,
              isSynced: c.hasBeenReadFor(cycle),
              isQueuedForSync: queued.contains(c.id),
            ))
        .toList();

    return Ok(AreaRoster(areaId: areaId, cycle: cycle, entries: entries));
  }
}

/// Pull-to-refresh: fill the cache from Supabase.
///
/// Kept apart from [LoadAreaRoster] because it is a different user intention
/// and a different failure mode. Failing here means "could not reach the
/// server", which is normal in the field and must not empty the roster.
final class RefreshAreaRoster {
  final ConsumerRepository consumers;

  const RefreshAreaRoster({required this.consumers});

  Future<Result<void>> call({required AreaId areaId}) =>
      consumers.refreshAreaRoster(areaId);
}
