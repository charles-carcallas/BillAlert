import '../../../core/errors/app_failure.dart';
import '../../../core/result/result.dart';
import '../../entities/bill.dart';
import '../../repositories/bill_repository.dart';
import '../../repositories/consumer_repository.dart';
import '../../repositories/notice_repository.dart';
import '../../repositories/notification_repository.dart';
import '../../value_objects/ids.dart';

/// Everything the Inbox can show about one notification.
///
/// The notification itself is always here: it is already on the phone. The
/// bill or notice it is about is read when it is opened, and may not be —
/// no signal, or a notice closed since — without taking the notification
/// away with it.
final class NotificationDetails {
  final AppNotification notification;

  /// The bill it is about, when it is about one and the bill could be read.
  final Bill? bill;

  /// The disconnection notice it announces, while that notice is active.
  final ActiveNotice? notice;

  /// Why the bill or notice could not be read. Null when nothing failed.
  final AppFailure? relatedFailure;

  const NotificationDetails({
    required this.notification,
    this.bill,
    this.notice,
    this.relatedFailure,
  });

  /// It announced a disconnection notice that is no longer active. Only
  /// active notices can be read, so a closed one is simply not found.
  bool get noticeNoLongerActive =>
      notification.noticeId != null && notice == null && relatedFailure == null;

  /// It pointed at a bill this account can no longer read.
  bool get billUnavailable =>
      notification.billId != null && bill == null && relatedFailure == null;
}

/// CON-05 — a consumer opens one Inbox notification to see what it is about.
///
/// Reads go through the consumer's own row-level security, as every consumer
/// read does. The Inbox lists only this household's alerts, and the bill or
/// notice behind one is readable by the same household and nobody else.
final class LoadNotificationDetails {
  final BillRepository bills;
  final NoticeRepository notices;
  final ConsumerRepository? consumers;

  const LoadNotificationDetails({
    required this.bills,
    required this.notices,
    this.consumers,
  });

  Future<NotificationDetails> call(AppNotification notification) async {
    ConsumerId? own;
    if (consumers != null) {
      switch (await consumers!.signedInConsumer()) {
        case Ok(value: final household?):
          own = household.id;
        case Ok(value: null):
          return NotificationDetails(
            notification: notification,
            relatedFailure: const PermissionFailure(
              'No household is linked to this account.',
            ),
          );
        case Err(:final failure):
          return NotificationDetails(
            notification: notification,
            relatedFailure: failure,
          );
      }
    }
    final BillId? billId = notification.billId;
    final NoticeId? noticeId = notification.noticeId;

    Bill? bill;
    ActiveNotice? notice;
    AppFailure? failure;

    if (billId != null) {
      final result = await bills.byId(billId, consumerId: own);
      switch (result) {
        case Ok(:final value):
          bill = own == null || value?.consumerId == own ? value : null;
        case Err(failure: final AppFailure reason):
          failure = reason;
      }
    }

    if (noticeId != null) {
      switch (await notices.byId(noticeId, consumerId: own)) {
        case Ok(:final value):
          notice = own == null || value?.consumerId == own ? value : null;
        case Err(failure: final AppFailure reason):
          failure ??= reason;
      }
    }

    return NotificationDetails(
      notification: notification,
      bill: bill,
      notice: notice,
      relatedFailure: failure,
    );
  }
}
