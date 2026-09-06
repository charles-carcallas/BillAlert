import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/result/result.dart';
import '../../domain/outbox/outbox_operation.dart';
import '../../domain/value_objects/ids.dart';
import '../../domain/value_objects/money.dart';
import '../supabase/failure_mapper.dart';

/// Sends queued operations to Supabase by calling the Postgres functions.
///
/// Every method here is four lines, and that is the point. All the work —
/// finding the previous reading, creating the billing cycle, refusing a
/// duplicate, creating the unpriced bill, queueing the consumer's
/// notification — happens inside the function, in one transaction, under Row
/// Level Security. Reimplementing any of it in Dart would mean a half-applied
/// change the first time a phone loses signal mid-operation.
///
/// `p_client_uuid` is the same value every time an operation is retried,
/// which is what makes calling these twice harmless.
class SupabaseOutboxGateway implements OutboxGateway {
  final SupabaseClient _client;

  const SupabaseOutboxGateway(this._client);

  @override
  Future<Result<String>> submitReading(RecordReadingOperation operation) async {
    try {
      final billId = await _client.rpc<dynamic>(
        'fn_record_meter_reading',
        params: <String, dynamic>{
          'p_consumer_id': operation.consumerId.value,
          // Sent as a decimal string. PostgREST casts it to numeric, and it
          // never becomes a double on the way.
          'p_current_reading': operation.currentReading.toDatabaseString(),
          'p_captured_at': operation.capturedAt.toIso8601String(),
          'p_client_uuid': operation.clientUuid.value,
        },
      );
      return Ok<String>(billId.toString());
    } catch (error, stackTrace) {
      return Err<String>(FailureMapper.from(error, stackTrace));
    }
  }

  @override
  Future<Result<String>> submitPostedAmount(
    PostAmountOperation operation,
  ) async {
    try {
      // Returns the notification id: posting the amount is also the moment
      // the consumer is told, and the function does both together.
      final notificationId = await _client.rpc<dynamic>(
        'fn_post_bill_amount',
        params: <String, dynamic>{
          'p_bill_id': operation.billId.value,
          'p_amount': operation.amount.toDatabaseString(),
          'p_due_date': operation.dueDate.toIso(),
          'p_posted_at': operation.capturedAt.toIso8601String(),
        },
      );
      return Ok<String>(notificationId.toString());
    } catch (error, stackTrace) {
      return Err<String>(FailureMapper.from(error, stackTrace));
    }
  }

  @override
  Future<Result<String>> submitPayment(RecordPaymentOperation operation) async {
    try {
      final transactionId = await _client.rpc<dynamic>(
        'fn_record_payment',
        params: <String, dynamic>{
          'p_bill_ids':
              operation.billIds.map((BillId id) => id.value).toList(),
          'p_amounts': operation.amounts
              .map((Money a) => a.toDatabaseString())
              .toList(),
          'p_cash_tendered': operation.cashTendered?.toDatabaseString(),
          'p_paid_at': operation.capturedAt.toIso8601String(),
          'p_client_uuid': operation.clientUuid.value,
        },
      );
      return Ok<String>(transactionId.toString());
    } catch (error, stackTrace) {
      return Err<String>(FailureMapper.from(error, stackTrace));
    }
  }

  @override
  Future<Result<String>> submitNotice(IssueNoticeOperation operation) async {
    try {
      final noticeId = await _client.rpc<dynamic>(
        'fn_issue_disconnection_notice',
        params: <String, dynamic>{
          'p_consumer_id': operation.consumerId.value,
          'p_reason': operation.reason,
          // The moment it was served. The 48-hour period runs from here.
          'p_served_at': operation.capturedAt.toIso8601String(),
          'p_client_uuid': operation.clientUuid.value,
        },
      );
      return Ok<String>(noticeId.toString());
    } catch (error, stackTrace) {
      return Err<String>(FailureMapper.from(error, stackTrace));
    }
  }
}
