import '../../../core/errors/app_failure.dart';
import '../../../core/result/result.dart';
import '../../entities/consumer.dart';
import '../../outbox/outbox_operation.dart';
import '../../repositories/notice_repository.dart';
import '../../repositories/outbox_repository.dart';
import '../../time/ph_clock.dart';
import '../../value_objects/ids.dart';

/// The Area President serves a disconnection notice.
///
/// Owned by Charles. The screen is still to be written.
///
/// The important field is the one you cannot see here: [capturedAt] on the
/// operation is the moment the notice was served, and the 48-hour period runs
/// from it. If that were replaced by the sync time, a notice served on a
/// Friday afternoon with no signal would give the household two hours less
/// than the law allows. This is why every queued operation carries its own
/// capture time rather than letting the server stamp `now()`.
final class IssueDisconnectionNotice {
  final OutboxRepository outbox;
  final PhClock clock;
  final ClientUuidFactory newClientUuid;

  const IssueDisconnectionNotice({
    required this.outbox,
    required this.clock,
    required this.newClientUuid,
  });

  Future<Result<void>> call({
    required Consumer consumer,
    String? reason,
  }) async {
    if (!consumer.isActive) {
      return Err(ValidationFailure(
        '${consumer.fullName} is not an active account, so a disconnection '
        'notice does not apply.',
      ));
    }

    final operation = IssueNoticeOperation(
      clientUuid: newClientUuid(),
      capturedAt: clock.nowUtc(),
      consumerId: consumer.id,
      consumerLabel: consumer.fullName,
      reason: reason,
    );

    return switch (await outbox.enqueue(operation)) {
      Err(:final failure) => Err<void>(failure),
      Ok() => const Ok<void>(null),
    };
  }
}

/// The Area President records how a served notice ended.
///
/// Owned by Charles. Unlike the four operations above, this one is online
/// only: the local `outbox.operation` CHECK constraint has no code for
/// closing a notice, so there is nothing to queue it as. If the team decides
/// this needs to work offline, the local schema needs a new operation code
/// and this becomes a fifth OutboxOperation subclass. Ask before changing
/// the schema.
final class RecordNoticeOutcome {
  final NoticeRepository notices;

  const RecordNoticeOutcome({required this.notices});

  Future<Result<void>> call({
    required NoticeId noticeId,
    required NoticeOutcome outcome,
    String? notes,
  }) =>
      notices.closeNotice(noticeId: noticeId, outcome: outcome, notes: notes);
}
