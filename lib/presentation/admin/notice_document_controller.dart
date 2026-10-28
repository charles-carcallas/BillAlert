import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_failure.dart';
import '../../core/result/result.dart';
import '../../domain/repositories/notice_repository.dart';
import '../../domain/value_objects/ids.dart';
import '../auth/auth_controller.dart';
import '../providers.dart';
import 'disconnections_screen.dart';

/// State for one active or closed disconnection-notice document.
final class NoticeDocumentState {
  final ActiveNotice? notice;
  final bool isLoading;
  final bool isClosing;
  final AppFailure? failure;

  /// Retained after a successful close because `byId` honestly returns null
  /// as soon as the active-view row disappears.
  final NoticeOutcome? closedOutcome;
  final NoticeReview? review;

  const NoticeDocumentState({
    this.notice,
    this.isLoading = false,
    this.isClosing = false,
    this.failure,
    this.closedOutcome,
    this.review,
  });
}

/// Loads and closes one notice.
///
/// Closing deliberately calls [RecordNoticeOutcome] directly. It is online
/// only and is never written to the outbox: replaying a stale close later
/// could overwrite a newer outcome recorded by cooperative personnel.
class NoticeDocumentController extends Notifier<NoticeDocumentState> {
  final String noticeId;
  Future<void>? _loadInFlight;
  int _generation = 0;

  NoticeDocumentController(this.noticeId);

  @override
  NoticeDocumentState build() {
    ref.watch(
      authControllerProvider.select(
        (s) => (s.value?.id, s.value?.roleCode, s.value?.areaId),
      ),
    );
    _generation++;
    _loadInFlight = null;
    Future<void>.microtask(load);
    return const NoticeDocumentState(isLoading: true);
  }

  Future<void> load() {
    final Future<void>? existing = _loadInFlight;
    if (existing != null) return existing;

    late final Future<void> pending;
    pending = _doLoad().whenComplete(() {
      if (identical(_loadInFlight, pending)) _loadInFlight = null;
    });
    _loadInFlight = pending;
    return pending;
  }

  Future<void> _doLoad() async {
    final generation = _generation;
    if (state.isClosing) return;
    state = NoticeDocumentState(
      notice: state.notice,
      review: state.review,
      isLoading: true,
      closedOutcome: state.closedOutcome,
    );

    final Result<NoticeReview?> result = await ref
        .read(noticeRepositoryProvider)
        .review(NoticeId(noticeId));
    if (!ref.mounted || generation != _generation) return;

    switch (result) {
      case Ok(:final value):
        state = NoticeDocumentState(notice: value?.notice, review: value);
      case Err(:final failure):
        state = NoticeDocumentState(
          notice: state.notice,
          review: state.review,
          failure: failure,
        );
    }
  }

  Future<bool> close({required NoticeOutcome outcome, String? notes}) async {
    final ActiveNotice? notice = state.notice;
    final review = state.review;
    if (notice == null || state.isClosing || review?.isActive != true) {
      return false;
    }
    if (outcome == NoticeOutcome.settled && review?.readyToClose != true) {
      state = NoticeDocumentState(
        notice: notice,
        review: review,
        failure: const ValidationFailure(
          'Payment is not confirmed. Refresh and settle all overdue balances before closing as Settled.',
        ),
      );
      return false;
    }

    final cleanNotes = notes?.trim();
    if (outcome != NoticeOutcome.settled &&
        (cleanNotes == null || cleanNotes.isEmpty)) {
      state = NoticeDocumentState(
        notice: notice,
        review: review,
        failure: const ValidationFailure(
          'Enter a cancellation reason or referral details.',
        ),
      );
      return false;
    }
    // A refresh already in flight must not reopen a successfully closed notice.
    final generation = ++_generation;
    _loadInFlight = null;
    state = NoticeDocumentState(
      notice: notice,
      review: review,
      isClosing: true,
    );

    final Result<void> result = await ref.read(recordNoticeOutcomeProvider)(
      noticeId: notice.id,
      outcome: outcome,
      notes: cleanNotes,
    );
    if (!ref.mounted || generation != _generation) return false;

    switch (result) {
      case Ok():
        ref.invalidate(activeNoticesProvider);
        ref.invalidate(closedNoticesProvider);
        state = NoticeDocumentState(closedOutcome: outcome);
        return true;
      case Err(:final failure):
        final AppFailure shownFailure = failure is NetworkFailure
            ? ServerFailure(
                'Closure could not be confirmed. Reconnect and refresh this notice before trying again.',
                failure.debugDetail,
              )
            : failure;
        state = NoticeDocumentState(
          notice: notice,
          review: review,
          failure: shownFailure,
        );
        return false;
    }
  }
}

final noticeDocumentControllerProvider =
    NotifierProvider.family<
      NoticeDocumentController,
      NoticeDocumentState,
      String
    >(NoticeDocumentController.new);
