import '../../core/result/result.dart';
import '../value_objects/ids.dart';

/// Disconnection notices.
///
/// Not implemented yet - the Admin review screen belongs to another member of
/// the team. The 48-hour period runs from `served_at`, the moment the notice
/// was served in the field, not the moment it synced.
abstract class NoticeRepository {
  /// Backed by `v_active_disconnection_warnings`.
  Future<Result<List<ActiveNotice>>> activeFor(AreaId areaId);

  Future<Result<ActiveNotice?>> byId(NoticeId id);

  /// Calls `fn_close_disconnection_notice`. Online only - see
  /// RecordNoticeOutcome for why this one is not queued.
  Future<Result<void>> closeNotice({
    required NoticeId noticeId,
    required NoticeOutcome outcome,
    String? notes,
  });
}

/// How a served notice ended. The three closing values of the server side
/// `notice_status` enum; `active` is the state it starts in, not an outcome.
enum NoticeOutcome {
  /// The household paid, so the notice is discharged.
  settled,

  /// Served in error, or withdrawn.
  cancelled,

  /// Handed to the cooperative for disconnection.
  referred;

  String get code => name;
}

/// A served notice still inside its period.
final class ActiveNotice {
  final NoticeId id;
  final ConsumerId consumerId;
  final String consumerLabel;
  final DateTime servedAt;
  final int hoursRemaining;

  const ActiveNotice({
    required this.id,
    required this.consumerId,
    required this.consumerLabel,
    required this.servedAt,
    required this.hoursRemaining,
  });
}
