import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import 'auth_controller.dart';

/// Asks the server, when the tabs first open and whenever the app comes back
/// to the front, whether this phone's session still exists.
///
/// An Area President resetting a password ends every session of that account.
/// Without this, a phone still signed in as it could keep showing the
/// account's bills for up to an hour, until its access token expired.
class SessionCheckGate extends ConsumerStatefulWidget {
  final Widget child;

  const SessionCheckGate({required this.child, super.key});

  @override
  ConsumerState<SessionCheckGate> createState() => _SessionCheckGateState();
}

class _SessionCheckGateState extends ConsumerState<SessionCheckGate> {
  late final AppLifecycleListener _lifecycle = AppLifecycleListener(
    onResume: _resume,
    onPause: () => _timer?.cancel(),
  );

  Timer? _timer;
  bool _checking = false;
  void _resume() {
    _check();
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _check());
  }

  @override
  void initState() {
    super.initState();
    _lifecycle;
    WidgetsBinding.instance.addPostFrameCallback((_) => _resume());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _lifecycle.dispose();
    super.dispose();
  }

  void _check() {
    if (!mounted || _checking) return;
    _checking = true;
    unawaited(() async {
      try {
        await ref.read(authControllerProvider.notifier).confirmSession();
        if (!mounted || ref.read(authControllerProvider).value == null) return;
        await ref.read(networkStatusProvider).recheck();
        if (!mounted) return;
        await ref.read(syncServiceProvider).syncNow();
      } catch (_) {
        /* A retry must not break navigation. */
      } finally {
        _checking = false;
      }
    }());
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
