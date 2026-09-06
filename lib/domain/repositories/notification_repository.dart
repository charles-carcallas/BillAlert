import '../../core/result/result.dart';
import '../value_objects/ids.dart';

/// The consumer alert inbox.
///
/// Not implemented yet - the Consumer screens belong to another member of the
/// team. CON-05 requires the inbox to be readable offline, so this reads from
/// `cached_notifications` and refreshes when there is signal.
abstract class NotificationRepository {
  Future<Result<List<AppNotification>>> inboxFor(ConsumerId consumerId);

  Future<Result<void>> markRead(NotificationId id);

  Future<Result<int>> unreadCount();
}

/// One alert. The app never sends these: the Postgres functions queue them
/// when a bill is priced or a notice is served.
final class AppNotification {
  final NotificationId id;

  /// bill_ready, pre_due_reminder, overdue or disconnection.
  final String type;

  /// sms or push.
  final String channel;

  final String message;
  final bool isRead;
  final DateTime createdAt;

  const AppNotification({
    required this.id,
    required this.type,
    required this.channel,
    required this.message,
    required this.isRead,
    required this.createdAt,
  });
}
