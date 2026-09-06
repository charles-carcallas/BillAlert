import 'dart:convert';

import '../../domain/outbox/outbox_operation.dart';
import '../../domain/value_objects/cycle_label.dart';
import '../../domain/value_objects/ids.dart';
import '../../domain/value_objects/kwh.dart';
import '../../domain/value_objects/money.dart';
import '../../domain/value_objects/ph_date.dart';

/// Rebuilds an [OutboxOperation] from the row it was stored as.
///
/// This is the one honest `switch` in the outbox design, and it is worth
/// knowing why it has to exist. Writing an operation down is polymorphic —
/// the object knows its own `operationCode` and `toPayloadJson()`. Reading
/// one back is not: all that comes out of SQLite is a string and some JSON,
/// and something has to decide which constructor to call. A sealed hierarchy
/// removes the dispatch switches from the sync loop; it does not remove this
/// single decode point, and it should not pretend to.
///
/// Everything else in the app can stay polymorphic because of these fifteen
/// lines.
class OutboxCodec {
  const OutboxCodec._();

  /// Returns null for an operation code this version of the app does not
  /// know — `create_consumer` and `update_consumer` are allowed by the local
  /// schema but have no subclass yet. The sync service marks those failed
  /// with a readable reason rather than crashing on them.
  static OutboxOperation? decode({
    required String operationCode,
    required String payloadJson,
    required String clientUuid,
    required String capturedAt,
  }) {
    final payload = jsonDecode(payloadJson) as Map<String, dynamic>;
    final id = ClientUuid(clientUuid);
    final captured = DateTime.parse(capturedAt).toUtc();

    switch (operationCode) {
      case 'record_reading':
        return RecordReadingOperation(
          clientUuid: id,
          capturedAt: captured,
          consumerId: ConsumerId(payload['consumer_id'] as String),
          currentReading: Kwh.parse(payload['current_reading'] as String),
          cycleLabel: CycleLabel.tryParse(payload['cycle_label'] as String) ??
              CycleLabel.of(PhDate.at(captured)),
          consumerLabel: payload['consumer_label'] as String? ?? '',
        );

      case 'post_amount':
        return PostAmountOperation(
          clientUuid: id,
          capturedAt: captured,
          billId: BillId(payload['bill_id'] as String),
          amount: Money.parse(payload['amount'] as String),
          dueDate: PhDate.tryParse(payload['due_date'] as String) ??
              PhDate.at(captured),
          billLabel: payload['bill_label'] as String? ?? '',
        );

      case 'record_payment':
        return RecordPaymentOperation(
          clientUuid: id,
          capturedAt: captured,
          billIds: (payload['bill_ids'] as List<dynamic>)
              .map((dynamic v) => BillId(v as String))
              .toList(),
          amounts: (payload['amounts'] as List<dynamic>)
              .map((dynamic v) => Money.parse(v as String))
              .toList(),
          cashTendered: payload['cash_tendered'] == null
              ? null
              : Money.parse(payload['cash_tendered'] as String),
          consumerLabel: payload['consumer_label'] as String? ?? '',
        );

      case 'issue_notice':
        return IssueNoticeOperation(
          clientUuid: id,
          capturedAt: captured,
          consumerId: ConsumerId(payload['consumer_id'] as String),
          reason: payload['reason'] as String?,
          consumerLabel: payload['consumer_label'] as String? ?? '',
        );

      default:
        return null;
    }
  }

  /// The other direction is not a switch: the operation serialises itself.
  static String encode(OutboxOperation operation) =>
      jsonEncode(operation.toPayloadJson());
}
