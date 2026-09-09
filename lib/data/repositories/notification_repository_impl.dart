import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/result/result.dart';
import '../../domain/repositories/notification_repository.dart';
import '../../domain/value_objects/ids.dart';
import '../local/app_database.dart';
import '../supabase/failure_mapper.dart';

/// CON-05 — the consumer's alert inbox.
///
/// Reads the `notifications` table rather than `v_notification_status`. The
/// view exists for delivery monitoring and carries the type, channel and
/// status but NOT `message_content`, which is the one column an inbox is
/// actually made of. This is a single-table read with no joins, so it does
/// not break the "read through the views" rule that exists to keep joins out
/// of Dart.
///
/// The app never creates a notification. `fn_post_bill_amount` and
/// `fn_issue_disconnection_notice` queue them server-side, which is why there
/// is no write here beyond marking one read.
class NotificationRepositoryImpl implements NotificationRepository {
  // ignore: unused_field
  final AppDatabase _db;
  final SupabaseClient _client;

  const NotificationRepositoryImpl(this._db, this._client);

  static const String _columns =
      'id, notif_type, channel, message_content, is_read, created_at';

  @override
  Future<Result<List<AppNotification>>> inboxFor(ConsumerId consumerId) async {
    try {
      final rows = await _client
          .from('notifications')
          .select(_columns)
          .eq('consumer_id', consumerId.value)
          .order('created_at', ascending: false);

      return Ok<List<AppNotification>>(rows.map(_fromRow).toList());
    } catch (error, stackTrace) {
      return Err<List<AppNotification>>(FailureMapper.from(error, stackTrace));
    }
  }

  /// CON-05. The consumer may mark their own alerts read and nothing else —
  /// `notif_consumer_mark_read` is scoped to their own household, so this
  /// needs no ownership check of its own.
  @override
  Future<Result<void>> markRead(NotificationId id) async {
    try {
      await _client
          .from('notifications')
          .update(<String, dynamic>{
            'is_read': true,
            'read_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', id.value);

      return const Ok<void>(null);
    } catch (error, stackTrace) {
      return Err<void>(FailureMapper.from(error, stackTrace));
    }
  }

  /// The badge on the Inbox tab.
  ///
  /// Row-Level Security already limits this to the caller's own alerts, so
  /// there is no consumer filter: a consumer counts theirs, and nobody can
  /// count somebody else's.
  @override
  Future<Result<int>> unreadCount() async {
    try {
      final rows = await _client
          .from('notifications')
          .select('id')
          .eq('is_read', false);

      return Ok<int>(rows.length);
    } catch (error, stackTrace) {
      return Err<int>(FailureMapper.from(error, stackTrace));
    }
  }

  static AppNotification _fromRow(Map<String, dynamic> row) => AppNotification(
        id: NotificationId(row['id'] as String),
        type: row['notif_type'] as String? ?? '',
        channel: row['channel'] as String? ?? '',
        message: row['message_content'] as String? ?? '',
        isRead: row['is_read'] as bool? ?? false,
        createdAt: DateTime.parse(row['created_at'] as String),
      );
}
