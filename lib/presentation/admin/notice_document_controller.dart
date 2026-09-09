import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_failure.dart';
import '../../core/result/result.dart';
import '../../domain/repositories/notice_repository.dart';
import '../../domain/value_objects/ids.dart';
import '../providers.dart';
import 'disconnections_screen.dart';

/// State for one active disconnection-notice document.
final class NoticeDocumentState {
  final ActiveNotice? notice;
  final bool isLoading;
  final bool isClosing;
  final AppFailure? failure;

  /// Retained after a successful close because `byId` honestly returns null
  /// as soon as the active-view row disappears.
  final NoticeOutcome? closedOutcome;

  const NoticeDocumentState({
    this.notice,
    this.isLoading = false,
    this.isClosing = false,
    this.failure,
    this.closedOutcome,
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

  NoticeDocumentController(this.noticeId);

  @override
  NoticeDocumentState build() {
    Future<void>.microtask(load);
    return const NoticeDocumentState(isLoading: true);
  }

  Future<void> load() {
    final Future<void>? existing = _loadInFlight;
    if (existing != null) return existing;

    final Future<void> pending = _doLoad().whenComplete(
      () => _loadInFlight = null,
    );
    _loadInFlight = pending;
    return pending;
  }

  Future<void> _doLoad() async {
    state = NoticeDocumentState(
      notice: state.notice,
      isLoading: true,
      closedOutcome: state.closedOutcome,
    );

    final Result<ActiveNotice?> result = await ref
        .read(noticeRepositoryProvider)
        .byId(NoticeId(noticeId));

    switch (result) {
      case Ok(:final value):
        state = NoticeDocumentState(notice: value);
      case Err(:final failure):
        state = NoticeDocumentState(notice: state.notice, failure: failure);
    }
  }

  Future<bool> close({required NoticeOutcome outcome, String? notes}) async {
    final ActiveNotice? notice = state.notice;
    if (notice == null || state.isClosing) return false;

    state = NoticeDocumentState(notice: notice, isClosing: true);

    final String? cleanNotes = notes == null || notes.trim().isEmpty
        ? null
        : notes.trim();
    final Result<void> result = await ref.read(recordNoticeOutcomeProvider)(
      noticeId: notice.id,
      outcome: outcome,
      notes: cleanNotes,
    );

    switch (result) {
      case Ok():
        ref.invalidate(activeNoticesProvider);
        state = NoticeDocumentState(closedOutcome: outcome);
        return true;
      case Err(:final failure):
        final AppFailure shownFailure = failure is NetworkFailure
            ? ServerFailure(
                'Could not close this notice because BillAlert is offline. '
                'Nothing was saved. Reconnect and try again.',
                failure.debugDetail,
              )
            : failure;
        state = NoticeDocumentState(notice: notice, failure: shownFailure);
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
