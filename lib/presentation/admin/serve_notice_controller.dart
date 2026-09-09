import 'dart:async';

// `Consumer` here means a household. Riverpod's widget of that name is not
// used in this file.
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Consumer;

import '../../core/errors/app_failure.dart';
import '../../core/result/result.dart';
import '../../domain/entities/consumer.dart';
import '../../domain/repositories/bill_repository.dart';
import '../../domain/value_objects/ids.dart';
import '../auth/auth_controller.dart';
import '../providers.dart';

/// Serving a disconnection notice.
final class ServeNoticeState {
  final List<Consumer> households;

  /// What each household owes, by consumer id.
  ///
  /// `fn_issue_disconnection_notice` refuses a household with no overdue
  /// bill, so without this the Admin picks a name and is told no. The screen
  /// shows the same fact the server will check.
  final Map<String, ConsumerOutstanding> outstanding;
  final String query;
  final Consumer? selected;
  final bool isLoading;
  final bool isSubmitting;
  final AppFailure? failure;

  /// Set once a notice has been queued, so the screen can confirm it.
  final String? servedTo;

  const ServeNoticeState({
    this.households = const <Consumer>[],
    this.outstanding = const <String, ConsumerOutstanding>{},
    this.query = '',
    this.selected,
    this.isLoading = false,
    this.isSubmitting = false,
    this.failure,
    this.servedTo,
  });

  ServeNoticeState copyWith({
    List<Consumer>? households,
    Map<String, ConsumerOutstanding>? outstanding,
    String? query,
    Consumer? selected,
    bool? isLoading,
    bool? isSubmitting,
    AppFailure? failure,
    String? servedTo,
    bool clearSelected = false,
  }) {
    return ServeNoticeState(
      households: households ?? this.households,
      outstanding: outstanding ?? this.outstanding,
      query: query ?? this.query,
      selected: clearSelected ? null : (selected ?? this.selected),
      isLoading: isLoading ?? this.isLoading,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      failure: failure,
      servedTo: servedTo,
    );
  }

  List<Consumer> get visible {
    final q = query.trim().toLowerCase();
    final matched = q.isEmpty
        ? households
        : households
            .where((Consumer c) =>
                c.fullName.toLowerCase().contains(q) ||
                c.consumerNo.value.toLowerCase().contains(q))
            .toList();

    // Overdue households first: they are the only ones a notice can be served
    // against, and the reason the Admin opened this screen.
    final sorted = <Consumer>[...matched];
    sorted.sort((Consumer a, Consumer b) {
      final int byOverdue =
          overdueCountFor(b).compareTo(overdueCountFor(a));
      return byOverdue != 0 ? byOverdue : a.lastName.compareTo(b.lastName);
    });
    return sorted;
  }

  int overdueCountFor(Consumer c) => outstanding[c.id.value]?.overdueCount ?? 0;

  /// The server's rule, asked before the Admin commits to a name.
  bool canServe(Consumer c) => c.isActive && overdueCountFor(c) > 0;
}

/// DOM-05 — the Area President serves a disconnection notice.
///
/// The household list comes from the encrypted cache, refreshed from the
/// server on demand. The Admin is at a desk with signal, but reusing the
/// cache means this screen behaves the same way the reader's does and needs
/// no second code path.
class ServeNoticeController extends Notifier<ServeNoticeState> {
  Future<void>? _inFlight;

  @override
  ServeNoticeState build() {
    Future<void>.microtask(load);
    return const ServeNoticeState(isLoading: true);
  }

  Future<void> load() {
    final Future<void>? existing = _inFlight;
    if (existing != null) return existing;
    final Future<void> load = _doLoad().whenComplete(() => _inFlight = null);
    _inFlight = load;
    return load;
  }

  Future<void> _doLoad({bool fromServer = false}) async {
    final user = await ref.read(authControllerProvider.future);
    final AreaId? areaId = user?.areaId;

    if (areaId == null) {
      state = const ServeNoticeState(
        failure: PermissionFailure(
          'Only an Area President serves a notice, and no service area is '
          'attached to the account you are signed in with.',
        ),
      );
      return;
    }

    state = state.copyWith(isLoading: true);
    final consumers = ref.read(consumerRepositoryProvider);

    if (fromServer) {
      // A failed refresh keeps whatever is already cached: an out-of-date
      // list is worth more than an empty one.
      await consumers.refreshAreaRoster(areaId);
    }

    final rosterResult = await consumers.areaRoster(areaId);

    // Who is actually overdue. A failure here is not worth blocking the list
    // for - the server still refuses a household with nothing overdue - so it
    // degrades to an empty map and every row simply shows no badge.
    final owed = <String, ConsumerOutstanding>{};
    final owedResult =
        await ref.read(billRepositoryProvider).outstandingInArea(areaId);
    if (owedResult case Ok(:final value)) {
      for (final ConsumerOutstanding c in value) {
        owed[c.consumerId.value] = c;
      }
    }

    switch (rosterResult) {
      case Ok(:final value):
        state = state.copyWith(
          households: value,
          outstanding: owed,
          isLoading: false,
          selected: state.selected,
        );
      case Err(:final failure):
        state = state.copyWith(isLoading: false, failure: failure);
    }
  }

  Future<void> refreshFromServer() => _doLoad(fromServer: true);

  void search(String query) => state = state.copyWith(query: query);

  void select(Consumer household) =>
      state = state.copyWith(selected: household);

  void clearSelection() => state = state.copyWith(clearSelected: true);

  /// Queues the notice. `capturedAt` is stamped now, and the 48-hour period
  /// runs from it — not from whenever this reaches the server.
  Future<void> serve({String? reason}) async {
    final Consumer? household = state.selected;
    if (household == null) return;

    state = state.copyWith(isSubmitting: true);

    final result = await ref.read(issueDisconnectionNoticeProvider)(
      consumer: household,
      reason: (reason == null || reason.trim().isEmpty) ? null : reason.trim(),
    );

    switch (result) {
      case Err(:final failure):
        state = state.copyWith(isSubmitting: false, failure: failure);
      case Ok():
        // Draining now is what makes the notice appear in the Notices list
        // and starts its clock server-side.
        await ref.read(syncServiceProvider).syncNow();
        state = state.copyWith(
          isSubmitting: false,
          servedTo: household.fullName,
          clearSelected: true,
        );
    }
  }
}

final serveNoticeControllerProvider =
    NotifierProvider<ServeNoticeController, ServeNoticeState>(
  ServeNoticeController.new,
);
