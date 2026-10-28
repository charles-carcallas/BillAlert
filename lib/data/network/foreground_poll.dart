import 'dart:async';
import 'network_status.dart';

/// Keep cached screens steady while offline. A live but unreachable link gets
/// one lightweight reachability check, not a refresh of every work list.
class ForegroundPoll {
  ForegroundPoll(
    this.network,
    this.refresh, {
    this.interval = const Duration(minutes: 1),
  }) {
    network.addListener(_changed);
  }
  final NetworkStatus network;
  final Future<void> Function() refresh;
  final Duration interval;
  Timer? _timer;
  bool active = false;
  bool _busy = false;
  void resume() {
    active = true;
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => unawaited(_tick()));
    unawaited(_tick());
  }

  void pause() {
    active = false;
    _timer?.cancel();
  }

  void _changed() {
    if (active && network.isOnline) unawaited(_tick());
  }

  Future<void> _tick() async {
    if (!active || _busy || !network.hasLink) return;
    _busy = true;
    try {
      if (!network.isOnline) await network.recheck();
      if (active && network.isOnline) await refresh();
    } catch (_) {
      // Keep the saved screen; retry on a later reconnect/resume/interval.
    } finally {
      _busy = false;
    }
  }

  void dispose() {
    pause();
    network.removeListener(_changed);
  }
}
