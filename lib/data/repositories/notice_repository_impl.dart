import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/result/result.dart';
import '../../domain/repositories/notice_repository.dart';
import '../../domain/value_objects/ids.dart';
import '../local/app_database.dart';
import '../supabase/failure_mapper.dart';

/// DOM-05 — disconnection notices still inside their period.
///
/// Reads `v_active_disconnection_warnings`, which already filters to
/// `status = 'active'` and works out the earliest lawful moment for each one.
///
/// Closing a notice is NOT queued through the outbox, unlike every other
/// mutation in this app. That is deliberate: closing decides whether a
/// household's power may lawfully be cut, and a decision that important must
/// fail loudly at the moment it is made rather than sit in a queue looking
/// accepted. The interface says the same thing.
class NoticeRepositoryImpl implements NoticeRepository {
  // ignore: unused_field
  final AppDatabase _db;
  final SupabaseClient _client;

  const NoticeRepositoryImpl(this._db, this._client);

  static const String _columns =
      'notice_id, notice_no, consumer_id, consumer_name, consumer_no, '
      'served_at, earliest_lawful_at, notice_period_elapsed, amount_overdue';

  @override
  Future<Result<List<ActiveNotice>>> activeFor(AreaId areaId) async {
    try {
      final rows = await _client
          .from('v_active_disconnection_warnings')
          .select(_columns)
          .eq('area_id', areaId.value)
          // Oldest first: the notice closest to its lawful moment is the one
          // that needs a decision soonest.
          .order('served_at', ascending: true);

      return Ok<List<ActiveNotice>>(rows.map(_fromRow).toList());
    } catch (error, stackTrace) {
      return Err<List<ActiveNotice>>(FailureMapper.from(error, stackTrace));
    }
  }

  @override
  Future<Result<ActiveNotice?>> byId(NoticeId id) async {
    try {
      final row = await _client
          .from('v_active_disconnection_warnings')
          .select(_columns)
          .eq('notice_id', id.value)
          .maybeSingle();

      return Ok<ActiveNotice?>(row == null ? null : _fromRow(row));
    } catch (error, stackTrace) {
      return Err<ActiveNotice?>(FailureMapper.from(error, stackTrace));
    }
  }

  @override
  Future<Result<void>> closeNotice({
    required NoticeId noticeId,
    required NoticeOutcome outcome,
    String? notes,
  }) async {
    try {
      await _client.rpc<dynamic>(
        'fn_close_disconnection_notice',
        params: <String, dynamic>{
          'p_notice_id': noticeId.value,
          // The enum's own name is the server's `notice_status` value, which
          // is why NoticeOutcome.code exists rather than a switch here.
          'p_outcome': outcome.code,
          'p_notes': notes,
        },
      );
      return const Ok<void>(null);
    } catch (error, stackTrace) {
      return Err<void>(FailureMapper.from(error, stackTrace));
    }
  }

  /// How long is left of the notice period.
  ///
  /// Worked out from `earliest_lawful_at`, which the server computed with
  /// `fn_earliest_lawful_disconnection` — 48 hours from when the notice was
  /// SERVED, advanced past Sundays and holidays. The app must never derive
  /// that date itself; it only counts down to the one it was given.
  static ActiveNotice _fromRow(Map<String, dynamic> row) {
    final DateTime servedAt = DateTime.parse(row['served_at'] as String);
    final DateTime lawfulAt =
        DateTime.parse(row['earliest_lawful_at'] as String);

    final int hours = lawfulAt.difference(DateTime.now().toUtc()).inHours;

    return ActiveNotice(
      id: NoticeId(row['notice_id'] as String),
      consumerId: ConsumerId(row['consumer_id'] as String),
      consumerLabel: row['consumer_name'] as String? ??
          row['consumer_no'] as String? ??
          '',
      servedAt: servedAt,
      // Never negative: once the period has elapsed the answer is zero hours
      // left, not a negative countdown.
      hoursRemaining: hours < 0 ? 0 : hours,
    );
  }
}
