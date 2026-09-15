import 'package:billalert/domain/repositories/notification_repository.dart';
import 'package:billalert/domain/value_objects/ids.dart';
import 'package:flutter_test/flutter_test.dart';

AppNotification _alert(
  String id, {
  required String type,
  required String channel,
  String? bill,
  bool isRead = false,
}) => AppNotification(
  id: NotificationId(id),
  type: type,
  channel: channel,
  message: 'Alert $id',
  isRead: isRead,
  createdAt: DateTime.utc(2026, 9, 15),
  billId: bill == null ? null : BillId(bill),
);

List<String> _ids(List<AppNotification> alerts) =>
    alerts.map((AppNotification alert) => alert.id.value).toList();

void main() {
  test('a bill text is left out when the app alert for that bill is there', () {
    final List<AppNotification> inbox = withoutTextCopies(<AppNotification>[
      _alert('app', type: 'bill_ready', channel: 'push', bill: 'bill-aug'),
      _alert(
        'text',
        type: 'bill_ready',
        channel: 'sms',
        bill: 'bill-aug',
        isRead: true,
      ),
    ]);

    expect(_ids(inbox), const <String>['app']);
  });

  test('a text with no app alert beside it stays', () {
    final List<AppNotification> inbox = withoutTextCopies(<AppNotification>[
      _alert('notice', type: 'disconnection', channel: 'sms'),
      _alert('app-aug', type: 'bill_ready', channel: 'push', bill: 'bill-aug'),
      // A different bill: its app alert is not in this list.
      _alert('text-jul', type: 'bill_ready', channel: 'sms', bill: 'bill-jul'),
      // Same bill, different kind of alert.
      _alert('overdue-aug', type: 'overdue', channel: 'sms', bill: 'bill-aug'),
    ]);

    expect(_ids(inbox), const <String>[
      'notice',
      'app-aug',
      'text-jul',
      'overdue-aug',
    ]);
  });
}
