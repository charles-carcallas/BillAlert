import '../../core/result/result.dart';
import '../outbox/outbox_entry.dart';
import '../outbox/outbox_operation.dart';
import '../value_objects/ids.dart';

/// The durable queue of work that has not reached the server.
///
/// [enqueue] is the single most important method in the application. Every
/// mutating use case calls it before it returns, and the screen confirms from
/// that local write rather than from a network round trip. Holding a pending
/// action only in memory is the difference between "works offline" and "loses
/// a morning of field work when Android kills the process".
abstract class OutboxRepository {
  /// Writes the operation to the encrypted database, synchronously, before
  /// anything is shown to the user as saved.
  Future<Result<void>> enqueue(OutboxOperation operation);

  /// Everything not yet accepted, oldest capture first. Sync order.
  Future<Result<List<OutboxEntry>>> pending();

  /// Everything still in the queue, including items the server refused.
  Future<Result<List<OutboxEntry>>> all();

  Future<Result<void>> markSyncing(ClientUuid clientUuid);

  Future<Result<void>> markSynced(ClientUuid clientUuid, String serverId);

  /// Keeps the item in the queue with the reason attached. Never deletes it.
  Future<Result<void>> markFailed(ClientUuid clientUuid, String reason);

  /// Drives the "N waiting to sync" badge without the screen polling.
  Stream<List<OutboxEntry>> watchAll();
}
