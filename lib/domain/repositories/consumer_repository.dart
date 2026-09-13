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
  /// Creates a household record in the signed-in Area President's area.
  ///
  /// This does not create an authentication account. Consumer authentication
  /// needs a server-side provisioning path with service-role credentials,
  /// which must never be present in the client application.
  Future<Result<Consumer>> create({
    required ConsumerNumber consumerNo,
    required String firstName,
    required String lastName,
    required AreaId areaId,
    required ProfileId createdBy,
    String? contactNumber,
    String? purok,
  });

  /// MTR-02: the reader's assigned area only. Row-Level Security enforces
  /// the same boundary server-side, so this is a convenience, not the guard.
  Future<Result<List<Consumer>>> areaRoster(AreaId areaId);

  /// Pulls the roster and each consumer's latest reading from Supabase and
  /// writes them into the cache. Fails with a NetworkFailure when offline,
  /// which is not an error worth interrupting the reader for.
  Future<Result<void>> refreshAreaRoster(AreaId areaId);

  /// One household, from the cache.
  Future<Result<Consumer?>> byId(ConsumerId id);

  /// The household of the signed-in consumer.
  ///
  /// A consumer signs in with a `profiles` row, but bills, readings and
  /// payments all hang off a `consumers` row, and the two have different ids.
  /// Without this the consumer screens have no way to ask "which household am
  /// I?", and passing the profile id where a consumer id belongs matches
  /// nothing at all.
  ///
  /// Row-Level Security is what makes this safe and simple: a consumer can
  /// see exactly one row of `consumers` - their own - so the query needs no
  /// filter and cannot return somebody else's household.
  ///
  /// Null when the signed-in user is staff, who have no household.
  Future<Result<Consumer?>> signedInConsumer();

  /// Changes only the signed-in household's SMS destination and returns the
  /// normalized number stored by the database. Online only.
  Future<Result<String>> updateOwnContactNumber(String contactNumber);

  /// When the cache was last filled, so a screen can say so. GEN-11 requires
  /// every screen showing cached data to show this, in case someone acts on
  /// a stale figure believing it is live.
  Future<Result<DateTime?>> lastRefreshedAt();
}
