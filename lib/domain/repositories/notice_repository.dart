import '../../core/result/result.dart';
import '../value_objects/ids.dart';
import '../value_objects/money.dart';

/// Disconnection notices.
///
/// The 48-hour period runs from `served_at`, the moment the notice was served
/// in the field, not the moment it synced.
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
///
/// Carries enough to render the notice DOCUMENT as well as the list row. One
/// class and one column list rather than two: both come from the same view,
/// and a second mapping path is a second place for the cycle-label bug to
/// happen again.
final class ActiveNotice {
  final NoticeId id;

  /// The reference printed on the notice, e.g. "DN-2026-0819-0033". This is
  /// what a household quotes when they come to the counter about it.
  final String noticeNo;

  final ConsumerId consumerId;
  final String consumerLabel;
  final String? consumerNo;
  final String? purok;
  final String? meterSerialNo;

  /// Why it was served, in the Area President's own words if they gave any.
  /// The column is `not null default 'Unpaid electricity bill'`.
  final String reason;

  /// Who served it. Null when the issuing profile is not visible to the
  /// reader — the view left-joins rather than dropping the notice.
  final String? issuedByName;

  final DateTime servedAt;

  /// The earliest moment disconnection would be lawful, computed SERVER-side
  /// by `fn_earliest_lawful_disconnection`. The app never derives this.
  final DateTime earliestLawfulAt;

  /// The server's own answer to "is the period over?", not a comparison done
  /// against this device's clock.
  final bool periodElapsed;

  /// What the household owes across every unpaid priced bill.
  final Money amountOverdue;

  final int hoursRemaining;

  const ActiveNotice({
    required this.id,
    required this.noticeNo,
    required this.consumerId,
    required this.consumerLabel,
    required this.servedAt,
    required this.earliestLawfulAt,
    required this.periodElapsed,
    required this.amountOverdue,
    required this.hoursRemaining,
    required this.reason,
    this.consumerNo,
    this.purok,
    this.meterSerialNo,
    this.issuedByName,
  });

  /// The household's address as far as this app knows it. Every consumer is
  /// in Barangay Tubod, Clarin, Bohol; only the purok varies.
  String get addressLine => purok == null
      ? 'Barangay Tubod, Clarin, Bohol'
      : '$purok, Barangay Tubod, Clarin, Bohol';
}
