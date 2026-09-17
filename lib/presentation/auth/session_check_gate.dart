import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    onResume: _check,
  );

  @override
  void initState() {
    super.initState();
    _lifecycle;
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  void _check() {
    if (!mounted) return;
    unawaited(ref.read(authControllerProvider.notifier).confirmSession());
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
