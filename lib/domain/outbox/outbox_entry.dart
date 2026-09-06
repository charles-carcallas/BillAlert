import 'outbox_operation.dart';

/// Where a queued operation has got to. Mirrors `outbox.status`.
enum OutboxStatus {
  /// Written down, waiting for signal.
  pending,

  /// Currently being uploaded.
  syncing,

  /// The server refused it. It stays in the queue, visible, with the reason,
  /// so the user can fix it. A rejected item is never silently dropped.
  failed,

  /// Accepted by the server.
  synced;

  static OutboxStatus fromCode(String code) {
    switch (code) {
      case 'syncing':
        return OutboxStatus.syncing;
      case 'failed':
        return OutboxStatus.failed;
      case 'synced':
        return OutboxStatus.synced;
      default:
        return OutboxStatus.pending;
    }
  }

  String get code => name;
}

/// One row of the outbox: the operation, plus how its upload is going.
final class OutboxEntry {
  final OutboxOperation operation;
  final OutboxStatus status;
  final int attempts;

  /// Why the server refused it, in the words the failure mapper produced.
  final String? lastError;

  /// The id the server created, once accepted.
  final String? serverId;

  final DateTime createdAt;

  const OutboxEntry({
    required this.operation,
    required this.status,
    required this.attempts,
    required this.createdAt,
    this.lastError,
    this.serverId,
  });

  bool get isPending => status == OutboxStatus.pending;
  bool get hasFailed => status == OutboxStatus.failed;

  /// What the reader sees in the sync list.
  String get description => operation.description;
}
