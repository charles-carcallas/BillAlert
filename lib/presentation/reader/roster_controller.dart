import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_failure.dart';
import '../../core/result/result.dart';
import '../../data/sync/sync_service.dart';
import '../../domain/entities/area_roster.dart';
import '../auth/auth_controller.dart';
import '../providers.dart';

/// What the roster screen draws.
final class RosterView {
  final AreaRoster roster;

  /// GEN-11: when the cached list was last filled from the server, so the
  /// screen can say so rather than letting somebody act on a stale figure
  /// believing it is live.
  final DateTime? lastRefreshedAt;

  const RosterView({required this.roster, this.lastRefreshedAt});
}

/// The meter reader's round for this cycle.
///
/// A view model, and note what it does not have: no Supabase client, no
/// database, no SQL. It calls two use cases and turns their [Result] into the
/// [AsyncValue] the widgets understand. That conversion — a Result becoming
/// an AsyncValue — is the only reason this class exists.
class RosterController extends AsyncNotifier<RosterView> {
  @override
  Future<RosterView> build() async {
    final user = ref.watch(authControllerProvider).value;
    final areaId = user?.areaId;

    if (areaId == null) {
      throw const PermissionFailure(
        'You are not assigned to a service area, so there is no round to '
        'show. Ask your Area President to check your account.',
      );
    }

    // Reads the cache. Works with no signal, which is the whole point.
    final result = await ref.read(loadAreaRosterProvider)(areaId: areaId);
    final roster = switch (result) {
      Ok(:final value) => value,
      // AsyncValue carries the failure in its error channel, and the screen
      // renders `failure.message`. Nothing technical reaches the user.
      Err(:final failure) => throw failure,
    };

    final refreshed = await ref
        .read(consumerRepositoryProvider)
        .lastRefreshedAt();

    return RosterView(
      roster: roster,
      lastRefreshedAt: switch (refreshed) {
        Ok(:final value) => value,
        Err() => null,
      },
    );
  }

  /// Pull to refresh: fetch the roster from Supabase, then reload from cache.
  ///
  /// Returns the failure to show as a banner, or null. A failure here does
  /// not empty the screen — the reader keeps yesterday's roster, which is far
  /// more useful than a blank list.
  Future<AppFailure?> refreshFromServer() async {
    final areaId = state.value?.roster.areaId;
    if (areaId == null) return null;

    final result = await ref.read(refreshAreaRosterProvider)(areaId: areaId);

    // Reload from the cache either way: even a failed refresh may follow a
    // successful sync that changed what is queued.
    ref.invalidateSelf();
    await future;

    return switch (result) {
      Ok() => null,
      Err(:final failure) => failure,
    };
  }

  /// Drains the outbox now, then reloads so the counters move.
  Future<Result<SyncReport>> syncNow() async {
    final result = await ref.read(syncServiceProvider).syncNow();
    ref.invalidateSelf();
    await future;
    return result;
  }
}

final rosterControllerProvider =
    AsyncNotifierProvider<RosterController, RosterView>(RosterController.new);
