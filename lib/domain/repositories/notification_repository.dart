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

  /// The bill a bill-ready, reminder or overdue alert is about.
  final BillId? billId;

  /// The disconnection notice a disconnection alert announces.
  final NoticeId? noticeId;

  /// pending, sent or failed: how far delivery got. Empty when not known.
  final String status;

  /// Why delivery failed. The database requires one on every failed row, so
  /// a household is told why a text never came (SYS-04).
  final String? failedReason;

  /// When it went out: shown on the phone, or sent as a text.
  final DateTime? sentAt;

  const AppNotification({
    required this.id,
    required this.type,
    required this.channel,
    required this.message,
    required this.isRead,
    required this.createdAt,
    this.billId,
    this.noticeId,
    this.status = '',
    this.failedReason,
    this.sentAt,
  });

  /// The same alert, read.
  AppNotification asRead() => AppNotification(
    id: id,
    type: type,
    channel: channel,
    message: message,
    isRead: true,
    createdAt: createdAt,
    billId: billId,
    noticeId: noticeId,
    status: status,
    failedReason: failedReason,
    sentAt: sentAt,
  );
}

/// The Inbox, with each alert once.
///
/// A posted bill reaches the household in the app and as a text
/// (`14_bill_sms.sql`), and each is its own row. The text says what the app
/// alert already says, so it is left out wherever the app alert for the same
/// bill is there. A text with no app alert beside it, such as a disconnection
/// notice, stays.
List<AppNotification> withoutTextCopies(List<AppNotification> alerts) {
  String key(AppNotification alert) => '${alert.type}|${alert.billId?.value}';

  final Set<String> inApp = <String>{
    for (final AppNotification alert in alerts)
      if (alert.channel != 'sms' && alert.billId != null) key(alert),
  };

  return <AppNotification>[
    for (final AppNotification alert in alerts)
      if (alert.channel != 'sms' ||
          alert.billId == null ||
          !inApp.contains(key(alert)))
        alert,
  ];
}
