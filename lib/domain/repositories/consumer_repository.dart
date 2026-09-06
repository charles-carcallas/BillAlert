import '../../core/result/result.dart';
import '../entities/consumer.dart';
import '../value_objects/ids.dart';

/// Households, read from the encrypted cache and refreshed from the server.
///
/// [areaRoster] never goes to the network. The meter reader opens it standing
/// in a barangay with no signal, so it answers from the cache or it answers
/// with nothing. [refreshAreaRoster] is the separate, explicitly online call
/// that fills that cache.
abstract class ConsumerRepository {
  /// MTR-02: the reader's assigned area only. Row-Level Security enforces
  /// the same boundary server-side, so this is a convenience, not the guard.
  Future<Result<List<Consumer>>> areaRoster(AreaId areaId);

  /// Pulls the roster and each consumer's latest reading from Supabase and
  /// writes them into the cache. Fails with a NetworkFailure when offline,
  /// which is not an error worth interrupting the reader for.
  Future<Result<void>> refreshAreaRoster(AreaId areaId);

  /// One household, from the cache.
  Future<Result<Consumer?>> byId(ConsumerId id);

  /// When the cache was last filled, so a screen can say so. GEN-11 requires
  /// every screen showing cached data to show this, in case someone acts on
  /// a stale figure believing it is live.
  Future<Result<DateTime?>> lastRefreshedAt();
}
