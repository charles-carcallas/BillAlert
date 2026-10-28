import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

import '../../core/errors/app_failure.dart';
import '../../core/result/result.dart';
import '../../domain/outbox/outbox_entry.dart';
import '../../domain/outbox/outbox_operation.dart';
import '../../domain/repositories/outbox_repository.dart';
import 'outbox_session.dart';

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

/// Serializes capture uploads and never crosses an account boundary.
class SyncService {
  final OutboxRepository _outbox;
  final OutboxGateway _gateway;
  final Connectivity _connectivity;
  final OutboxSession? session;
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  final _reports = StreamController<SyncReport>.broadcast();
  Stream<SyncReport> get reports => _reports.stream;
  Future<Result<SyncReport>>? _inFlight;
  int _generation = 0;
  bool _stopped = false;

  SyncService(
    this._outbox,
    this._gateway, {
    Connectivity? connectivity,
    this.session,
  }) : _connectivity = connectivity ?? Connectivity();

  void start() {
    _stopped = false;
    _subscription ??= _connectivity.onConnectivityChanged.listen((status) {
      if (_hasConnection(status)) unawaited(syncNow());
    });
  }

  Future<void> stop() async {
    _stopped = true;
    _generation++;
    await _subscription?.cancel();
    _subscription = null;
    // Auth must not change while an already dispatched request is returning.
    await _inFlight;
  }

  Future<Result<SyncReport>> syncNow() {
    final running = _inFlight;
    if (running != null) return running;
    if (_stopped) {
      return Future.value(
        const Err<SyncReport>(AuthFailure('Sync is paused until you sign in.')),
      );
    }
    final completer = Completer<Result<SyncReport>>();
    _inFlight = completer.future; // installed BEFORE the first await
    final generation = _generation;
    final ownerGeneration = session?.generation;
    unawaited(() async {
      try {
        final result = await _drain(generation, ownerGeneration);
        if (result case Ok(:final value)) _reports.add(value);
        completer.complete(result);
      } catch (error) {
        completer.complete(
          Err<SyncReport>(
            ServerFailure(
              'Sync could not finish. Your work remains on this phone.',
              '$error',
            ),
          ),
        );
      } finally {
        _inFlight = null;
      }
    }());
    return completer.future;
  }

  bool _current(int generation, int? ownerGeneration) =>
      !_stopped &&
      generation == _generation &&
      ownerGeneration == session?.generation;

  Future<Result<SyncReport>> _drain(
    int generation,
    int? ownerGeneration,
  ) async {
    if (!_hasConnection(await _connectivity.checkConnectivity())) {
      return const Err<SyncReport>(
        NetworkFailure(NetworkFailure.savedForLater),
      );
    }
    final attempted = <String>{};
    var succeeded = 0;
    var failed = 0;
    while (_current(generation, ownerGeneration)) {
      final pending = await _outbox.pending();
      if (pending case Err(:final failure)) return Err<SyncReport>(failure);
      final queue = (pending as Ok<List<OutboxEntry>>).value
          .where(
            (entry) => !attempted.contains(entry.operation.clientUuid.value),
          )
          .toList();
      if (queue.isEmpty) break;
      for (final entry in queue) {
        if (!_current(generation, ownerGeneration)) break;
        final uuid = entry.operation.clientUuid;
        final marking = await _outbox.markSyncing(uuid);
        if (marking case Err(:final failure)) return Err<SyncReport>(failure);
        if (!_current(generation, ownerGeneration)) break;
        attempted.add(uuid.value);
        final result = await entry.operation.submit(_gateway);
        // A server-ended session may have invalidated ownership during upload.
        if (ownerGeneration != session?.generation) break;
        final Result<void> persisted;
        switch (result) {
          case Ok(:final value):
            persisted = await _outbox.markSynced(uuid, value);
            succeeded++;
          case Err(:final failure):
            persisted = await _outbox.markFailed(uuid, failure.message);
            failed++;
        }
        if (persisted case Err(:final failure)) return Err<SyncReport>(failure);
        if (result case Err(
          :final failure,
        ) when failure is NetworkFailure || failure is AuthFailure) {
          return Ok(
            SyncReport(
              attempted: attempted.length,
              succeeded: succeeded,
              failed: failed,
            ),
          );
        }
      }
      // Pick up newly captured work, but try each UUID only once per drain.
    }
    return Ok(
      SyncReport(
        attempted: attempted.length,
        succeeded: succeeded,
        failed: failed,
      ),
    );
  }

  Future<void> dispose() async {
    await stop();
    await _reports.close();
  }

  static bool _hasConnection(List<ConnectivityResult> status) =>
      status.isNotEmpty && !status.every((r) => r == ConnectivityResult.none);
}
