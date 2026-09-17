import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Whether the app can reach the server right now, as best the phone knows.
///
/// Two signals feed it. The phone's own link state says "offline" the moment
/// Wi-Fi and mobile data are both gone. But a phone can hold a Wi-Fi link
/// with no internet behind it, or one bar of signal that carries nothing, so
/// every real request also reports back: a request that could not get
/// through marks the app offline, and the next one that does marks it online
/// again.
///
/// While the server is known to be unreachable on a live link, requests are
/// not sent at all except for one probe every [probeInterval]. Without that,
/// every screen opened with dead Wi-Fi waits out the full timeout before it
/// falls back to what the phone saved.
class NetworkStatus extends ChangeNotifier {
  NetworkStatus({
    Stream<bool>? linkChanges,
    Future<bool> Function()? checkLink,
    DateTime Function()? clock,
    this.probeInterval = const Duration(seconds: 15),
  }) : _now = clock ?? DateTime.now {
    final Connectivity? connectivity = linkChanges == null || checkLink == null
        ? Connectivity()
        : null;
    _checkLink =
        checkLink ??
        () async => _hasLink(await connectivity!.checkConnectivity());
    _subscription =
        (linkChanges ?? connectivity!.onConnectivityChanged.map(_hasLink))
            .listen(_onLink);
    unawaited(_checkLink().then(_onLink, onError: (_) {}));
  }

  late final Future<bool> Function() _checkLink;
  late final StreamSubscription<bool> _subscription;
  final DateTime Function() _now;

  /// How often one request is let through to see whether the server is back.
  final Duration probeInterval;

  /// Sends one small request through the app's HTTP client, which reports
  /// the outcome back here. Set by `main` once that client exists; without it
  /// [recheck] only re-reads the phone's link state.
  Future<void> Function()? pingServer;

  bool _linkUp = true;
  bool _reachable = true;

  /// When the last request that could reach the server was allowed out while
  /// it was believed unreachable, or when it was found to be unreachable.
  DateTime? _lastProbe;

  /// False when there is no network link at all. Requests are not even
  /// attempted then, because they cannot succeed.
  bool get hasLink => _linkUp;

  /// What the offline indicator shows.
  bool get isOnline => _linkUp && _reachable;

  void _onLink(bool hasLink) {
    final bool wasOnline = isOnline;
    _linkUp = hasLink;
    // A new link deserves a fresh try; whether it carries anything is for
    // the next request to say.
    if (hasLink) _reachable = true;
    if (wasOnline != isOnline) notifyListeners();
  }

  /// Whether a request should be sent now. Always, while the server is
  /// believed reachable. Otherwise only as a periodic probe, so a screen
  /// opened with dead Wi-Fi falls back to saved data at once instead of
  /// waiting out a timeout it already knows the answer to.
  bool allowRequest() {
    if (!_linkUp) return false;
    if (_reachable) return true;
    final DateTime now = _now();
    final DateTime? last = _lastProbe;
    if (last != null && now.difference(last) < probeInterval) return false;
    _lastProbe = now;
    return true;
  }

  /// A request got an answer from the server.
  void reportReachable() => _setReachable(true);

  /// A request could not get through.
  void reportUnreachable() {
    _lastProbe = _now();
    _setReachable(false);
  }

  void _setReachable(bool value) {
    if (_reachable == value) return;
    final bool wasOnline = isOnline;
    _reachable = value;
    if (wasOnline != isOnline) notifyListeners();
  }

  /// Asks the phone again, for a pull-to-refresh or a "Try again", and lets
  /// the very next request through as a probe rather than waiting for the
  /// interval. It does not claim the server is back: only a request that gets
  /// an answer can say that.
  Future<void> recheck() async {
    try {
      final bool hasLink = await _checkLink();
      _lastProbe = null;
      if (hasLink != _linkUp) _onLink(hasLink);
      if (hasLink && !_reachable) await pingServer?.call();
    } catch (_) {}
  }

  static bool _hasLink(List<ConnectivityResult> status) =>
      status.isNotEmpty &&
      !status.every((ConnectivityResult r) => r == ConnectivityResult.none);

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
