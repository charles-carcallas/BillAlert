import 'package:flutter_riverpod/flutter_riverpod.dart' hide Consumer;

import '../../core/errors/app_failure.dart';
import '../../core/result/result.dart';
import '../../domain/entities/consumer.dart';
import '../../domain/repositories/notification_repository.dart';
import '../../domain/value_objects/ids.dart';
import '../providers.dart';

/// CON-05 — the household's alerts.
final class InboxState {
  final List<AppNotification> alerts;
  final bool isLoading;
  final AppFailure? failure;

  const InboxState({
    this.alerts = const <AppNotification>[],
    this.isLoading = false,
    this.failure,
  });

  int get unreadCount =>
      alerts.where((AppNotification a) => !a.isRead).length;
}

class InboxController extends Notifier<InboxState> {
  Future<void>? _inFlight;
  ConsumerId? _consumerId;

  @override
  InboxState build() {
    Future<void>.microtask(load);
    return const InboxState(isLoading: true);
  }

  Future<void> load() {
    final Future<void>? existing = _inFlight;
    if (existing != null) return existing;

    final Future<void> load = _doLoad().whenComplete(() => _inFlight = null);
    _inFlight = load;
    return load;
  }

  Future<void> _doLoad() async {
    final consumerResult =
        await ref.read(consumerRepositoryProvider).signedInConsumer();

    final Consumer? me = switch (consumerResult) {
      Ok(:final value) => value,
      Err() => null,
    };

    if (me == null) {
      state = const InboxState(
        failure: PermissionFailure(
          'This is a household inbox, and the account you are signed in with '
          'is not attached to one.',
        ),
      );
      return;
    }
    _consumerId = me.id;

    state = InboxState(alerts: state.alerts, isLoading: true);

    switch (await ref.read(notificationRepositoryProvider).inboxFor(me.id)) {
      case Ok(:final value):
        state = InboxState(alerts: value);
      case Err(:final failure):
        state = InboxState(failure: failure);
    }
  }

  /// Marks one alert read, then reloads so the badge and the row agree.
  ///
  /// The server is the one that decides; this does not flip the flag locally
  /// first, because a read that failed would leave the screen claiming
  /// something the database does not say.
  Future<void> markRead(AppNotification alert) async {
    if (alert.isRead || _consumerId == null) return;

    switch (await ref.read(notificationRepositoryProvider).markRead(alert.id)) {
      case Ok():
        await load();
      case Err(:final failure):
        state = InboxState(alerts: state.alerts, failure: failure);
    }
  }
}

final inboxControllerProvider =
    NotifierProvider<InboxController, InboxState>(InboxController.new);
