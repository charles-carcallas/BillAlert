import 'dart:async';

// `Consumer` here means a household. Riverpod's widget of that name is not
// used in this file.
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Consumer;

import '../../core/errors/app_failure.dart';
import '../../core/result/result.dart';
import '../../domain/entities/consumer.dart';
import '../../domain/value_objects/ids.dart';
import '../auth/auth_controller.dart';
import '../providers.dart';

/// Serving a disconnection notice.
final class ServeNoticeState {
  final List<Consumer> households;
  final String query;
  final Consumer? selected;
  final bool isLoading;
  final bool isSubmitting;
  final AppFailure? failure;

  /// Set once a notice has been queued, so the screen can confirm it.
  final String? servedTo;

  const ServeNoticeState({
    this.households = const <Consumer>[],
    this.query = '',
    this.selected,
    this.isLoading = false,
    this.isSubmitting = false,
    this.failure,
    this.servedTo,
  });

  ServeNoticeState copyWith({
    List<Consumer>? households,
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
    if (q.isEmpty) return households;
    return households
        .where((Consumer c) =>
            c.fullName.toLowerCase().contains(q) ||
            c.consumerNo.value.toLowerCase().contains(q))
        .toList();
  }
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

    switch (await consumers.areaRoster(areaId)) {
      case Ok(:final value):
        state = state.copyWith(
          households: value,
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
