import 'package:billalert/domain/notifications/phone_alerts.dart';
import 'package:billalert/domain/value_objects/ids.dart';
import 'package:flutter_test/flutter_test.dart';

/// The payload a notification carries, read back when it is tapped.
///
/// A tap can arrive long after the notification was shown, from an older
/// build, or with nothing in it. Every one of those must land somewhere.
void main() {
  test('a bill target survives the round trip', () {
    final NoticeTarget target = NoticeTarget.decode(
      const BillNoticeTarget(BillId('b-42')).encode(),
    );

    expect(target, isA<BillNoticeTarget>());
    expect((target as BillNoticeTarget).bill.value, 'b-42');
  });

  test('a notice target survives the round trip', () {
    final NoticeTarget target = NoticeTarget.decode(
      const InboxNoticeTarget(notice: NotificationId('n-9')).encode(),
    );

    expect(target, isA<InboxNoticeTarget>());
    expect((target as InboxNoticeTarget).notice?.value, 'n-9');
  });

  test('anything unrecognised opens the plain Inbox', () {
    for (final String? payload in <String?>[
      null,
      '',
      'inbox',
      // What the previous build put in its payloads.
      'bill',
      'bill:',
      'notice:',
      'receipt:OR-123',
    ]) {
      final NoticeTarget target = NoticeTarget.decode(payload);
      expect(target, isA<InboxNoticeTarget>(), reason: '$payload');
      expect((target as InboxNoticeTarget).notice, isNull, reason: '$payload');
    }
  });
}
