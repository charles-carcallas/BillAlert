import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors/app_failure.dart';
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
  final AppDatabase _db;
  final SupabaseClient _client;

  const NotificationRepositoryImpl(this._db, this._client);

  /// The bill or notice each alert is about, and how far its delivery got,
  /// come with it: the Inbox opens an alert onto both.
  static const String _columns =
      'id, consumer_id, notif_type, channel, message_content, status, '
      'is_read, created_at, bill_id, disconnection_id, failed_reason, sent_at';

  static String _consumerCacheKey(ConsumerId id) =>
      'consumer_notifications:${id.value}';

  @override
  Future<Result<List<AppNotification>>> inboxFor(ConsumerId consumerId) async {
    try {
      final rows = await _client
          .from('notifications')
          .select(_columns)
          .eq('consumer_id', consumerId.value)
          .order('created_at', ascending: false);

      await _replaceConsumerCache(consumerId, rows);
      await _markConsumerNotificationsRefreshed(consumerId);
      return Ok<List<AppNotification>>(
        withoutTextCopies(rows.map(_fromRow).toList()),
      );
    } catch (error, stackTrace) {
      final failure = FailureMapper.from(error, stackTrace);
      if (failure is NetworkFailure) {
        final cached = await _cachedInboxFor(consumerId);
        switch (cached) {
          case Err(:final failure):
            return Err<List<AppNotification>>(failure);
          case Ok(:final value):
            if (value.isNotEmpty ||
                await _hasConsumerNotificationsCache(consumerId)) {
              return Ok<List<AppNotification>>(value);
            }
        }
      }
      return Err<List<AppNotification>>(failure);
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

      await (_db.update(_db.cachedNotifications)
            ..where((table) => table.id.equals(id.value)))
          .write(const CachedNotificationsCompanion(isRead: Value<bool>(true)));

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
      final failure = FailureMapper.from(error, stackTrace);
      if (failure is NetworkFailure) {
        try {
          final cached = await (_db.select(
            _db.cachedNotifications,
          )..where((table) => table.isRead.equals(false))).get();
          final marker =
              await (_db.select(_db.syncMeta)..where(
                    (table) =>
                        table.tableName_.like('consumer_notifications:%'),
                  ))
                  .getSingleOrNull();
          if (cached.isNotEmpty || marker != null) {
            return Ok<int>(cached.length);
          }
        } catch (cacheError) {
          return Err<int>(
            ServerFailure(
              'Could not count the alerts saved on this phone.',
              cacheError.toString(),
            ),
          );
        }
      }
      return Err<int>(failure);
    }
  }

  static AppNotification _fromRow(Map<String, dynamic> row) {
    final String? billId = row['bill_id'] as String?;
    final String? noticeId = row['disconnection_id'] as String?;
    final String? sentAt = row['sent_at'] as String?;

    return AppNotification(
      id: NotificationId(row['id'] as String),
      type: row['notif_type'] as String? ?? '',
      channel: row['channel'] as String? ?? '',
      message: row['message_content'] as String? ?? '',
      isRead: row['is_read'] as bool? ?? false,
      createdAt: DateTime.parse(row['created_at'] as String),
      billId: billId == null ? null : BillId(billId),
      noticeId: noticeId == null ? null : NoticeId(noticeId),
      status: row['status'] as String? ?? '',
      failedReason: row['failed_reason'] as String?,
      sentAt: sentAt == null ? null : DateTime.parse(sentAt),
    );
  }

  Future<void> _replaceConsumerCache(
    ConsumerId consumerId,
    List<Map<String, dynamic>> rows,
  ) async {
    await _db.transaction(() async {
      await (_db.delete(
        _db.cachedNotifications,
      )..where((table) => table.consumerId.equals(consumerId.value))).go();
      for (final row in rows) {
        await _db
            .into(_db.cachedNotifications)
            .insertOnConflictUpdate(
              CachedNotificationsCompanion.insert(
                id: row['id'] as String,
                consumerId: Value<String?>(row['consumer_id'] as String),
                notifType: row['notif_type'] as String? ?? '',
                channel: row['channel'] as String? ?? '',
                message: row['message_content'] as String? ?? '',
                status: row['status'] as String? ?? '',
                isRead: Value<bool>(row['is_read'] as bool? ?? false),
                createdAt: row['created_at'] as String,
                billId: Value<String?>(row['bill_id'] as String?),
                disconnectionId: Value<String?>(
                  row['disconnection_id'] as String?,
                ),
                failedReason: Value<String?>(row['failed_reason'] as String?),
                sentAt: Value<String?>(row['sent_at'] as String?),
              ),
            );
      }
    });
  }

  Future<Result<List<AppNotification>>> _cachedInboxFor(
    ConsumerId consumerId,
  ) async {
    try {
      final query = _db.select(_db.cachedNotifications)
        ..where((table) => table.consumerId.equals(consumerId.value))
        ..orderBy(<OrderingTerm Function($CachedNotificationsTable)>[
          (table) => OrderingTerm.desc(table.createdAt),
        ]);
      final rows = await query.get();
      return Ok<List<AppNotification>>(
        withoutTextCopies(
          rows
              .map(
                (row) => AppNotification(
                  id: NotificationId(row.id),
                  type: row.notifType,
                  channel: row.channel,
                  message: row.message,
                  isRead: row.isRead,
                  createdAt: DateTime.parse(row.createdAt),
                  billId: row.billId == null ? null : BillId(row.billId!),
                  noticeId: row.disconnectionId == null
                      ? null
                      : NoticeId(row.disconnectionId!),
                  status: row.status,
                  failedReason: row.failedReason,
                  sentAt: row.sentAt == null
                      ? null
                      : DateTime.parse(row.sentAt!),
                ),
              )
              .toList(),
        ),
      );
    } catch (error) {
      return Err<List<AppNotification>>(
        ServerFailure(
          'Could not read the alerts saved on this phone.',
          error.toString(),
        ),
      );
    }
  }

  Future<void> _markConsumerNotificationsRefreshed(
    ConsumerId consumerId,
  ) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _db
        .into(_db.syncMeta)
        .insertOnConflictUpdate(
          SyncMetaCompanion.insert(
            tableName_: _consumerCacheKey(consumerId),
            lastRefreshedAt: Value<String?>(now),
            lastAttemptAt: Value<String?>(now),
            lastError: const Value<String?>(null),
          ),
        );
  }

  Future<bool> _hasConsumerNotificationsCache(ConsumerId consumerId) async {
    final query = _db.select(
      _db.syncMeta,
    )..where((table) => table.tableName_.equals(_consumerCacheKey(consumerId)));
    return await query.getSingleOrNull() != null;
  }
}
