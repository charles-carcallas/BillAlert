import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

import '../../core/errors/app_failure.dart';
import '../../core/result/result.dart';
import '../../domain/outbox/outbox_entry.dart';
import '../../domain/outbox/outbox_operation.dart';
import '../../domain/repositories/outbox_repository.dart';

/// What one drain of the queue achieved.
final class SyncReport {
  final int attempted;
  final int succeeded;
  final int failed;

  const SyncReport({
    required this.attempted,
    required this.succeeded,
    required this.failed,
  });

  static const SyncReport nothingToDo = SyncReport(
    attempted: 0,
    succeeded: 0,
    failed: 0,
  );

  bool get didAnything => attempted > 0;
}

/// Drains the outbox when there is a connection.
///
/// Look at [_drain] and notice what is not there: no `switch` on an operation
/// name, and no knowledge of readings, payments or notices. It asks each
/// operation to submit itself. That is the payoff for making OutboxOperation
/// a sealed class with real behaviour — the fifth kind of queued action will
/// need no change in this file at all.
class SyncService {
  final OutboxRepository _outbox;
  final OutboxGateway _gateway;
  final Connectivity _connectivity;

  StreamSubscription<List<ConnectivityResult>>? _subscription;
  final StreamController<SyncReport> _reports =
      StreamController<SyncReport>.broadcast();

  /// Completed drain reports. Screens that show server-backed work queues
  /// use this to refresh after a reconnect finishes syncing the outbox.
  Stream<SyncReport> get reports => _reports.stream;

  /// True while a drain is running, so a connectivity change in the middle of
  /// one does not start a second pass over the same rows.
  bool _isDraining = false;

  /// Positional rather than named because a named parameter cannot be
  /// private, and these two fields should not be public.
  SyncService(this._outbox, this._gateway, {Connectivity? connectivity})
    : _connectivity = connectivity ?? Connectivity();

  /// Starts watching the connection. Call once, after sign-in.
  void start() {
    _subscription ??= _connectivity.onConnectivityChanged.listen((
      List<ConnectivityResult> status,
    ) {
      if (_hasConnection(status)) {
        unawaited(syncNow());
      }
    });
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  /// Drains the queue now, if there is a connection. Safe to call at any
  /// time — pull to refresh, app resume, or straight after saving a reading.
  Future<Result<SyncReport>> syncNow() async {
    if (_isDraining) {
      return const Ok<SyncReport>(SyncReport.nothingToDo);
    }

    final status = await _connectivity.checkConnectivity();
    if (!_hasConnection(status)) {
      // Everything this would have sent is still in the outbox, so here the
      // promise is true.
      return const Err<SyncReport>(
        NetworkFailure(NetworkFailure.savedForLater),
      );
    }

    _isDraining = true;
    try {
      final result = await _drain();
      if (result case Ok(:final value)) _reports.add(value);
      return result;
    } finally {
      _isDraining = false;
    }
  }

  Future<void> dispose() async {
    await stop();
    await _reports.close();
  }

  Future<Result<SyncReport>> _drain() async {
    final List<OutboxEntry> queue;
    switch (await _outbox.pending()) {
      case Err(:final failure):
        return Err<SyncReport>(failure);
      case Ok(:final value):
        queue = value;
    }

    var succeeded = 0;
    var failed = 0;

    // Oldest capture first, so the server sees the work in the order it was
    // actually done.
    for (final OutboxEntry entry in queue) {
      await _outbox.markSyncing(entry.operation.clientUuid);

      // The one line that matters. No switch, no if-chain: the operation
      // knows which function it belongs to.
      final result = await entry.operation.submit(_gateway);

      switch (result) {
        case Ok(:final value):
          await _outbox.markSynced(entry.operation.clientUuid, value);
          succeeded++;

        case Err(:final failure):
          if (failure is NetworkFailure) {
            // Signal went again mid-drain. Put it back as pending and stop:
            // the rest of the queue is almost certainly in the same boat, and
            // hammering a dead connection helps nobody.
            await _outbox.markFailed(
              entry.operation.clientUuid,
              NetworkFailure.savedForLater,
            );
            return Ok<SyncReport>(
              SyncReport(
                attempted: succeeded + failed + 1,
                succeeded: succeeded,
                failed: failed + 1,
              ),
            );
          }
          // The server refused it for a reason the user has to see — a
          // duplicate, an inactive account. The item stays in the queue with
          // the reason attached. It is never silently dropped.
          await _outbox.markFailed(entry.operation.clientUuid, failure.message);
          failed++;
      }
    }

    return Ok<SyncReport>(
      SyncReport(attempted: queue.length, succeeded: succeeded, failed: failed),
    );
  }

  static bool _hasConnection(List<ConnectivityResult> status) =>
      status.isNotEmpty &&
      !status.every((ConnectivityResult r) => r == ConnectivityResult.none);
}
