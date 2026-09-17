import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/network/network_status.dart';
import '../providers.dart';

/// A slim bar above the tabs that says when the app is offline, and briefly
/// says so when it is back.
///
/// It sits in the shell rather than on each screen, so going offline is
/// visible wherever the person happens to be, and no screen has to remember
/// to ask.
class OfflineIndicator extends ConsumerStatefulWidget {
  const OfflineIndicator({super.key});

  /// How long "Back online" stays before the bar folds away.
  static const Duration backOnlineFor = Duration(milliseconds: 2500);

  @override
  ConsumerState<OfflineIndicator> createState() => _OfflineIndicatorState();
}

enum _Shown { nothing, offline, backOnline }

class _OfflineIndicatorState extends ConsumerState<OfflineIndicator> {
  late final NetworkStatus _status = ref.read(networkStatusProvider);
  _Shown _shown = _Shown.nothing;
  Timer? _hide;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _shown = _status.isOnline ? _Shown.nothing : _Shown.offline;
    _status.addListener(_onChange);
  }

  @override
  void dispose() {
    _status.removeListener(_onChange);
    _hide?.cancel();
    super.dispose();
  }

  void _onChange() {
    _hide?.cancel();
    if (!_status.isOnline) {
      setState(() => _shown = _Shown.offline);
      return;
    }
    // Only announce a return from offline, not every quiet success.
    if (_shown != _Shown.offline) return;
    setState(() => _shown = _Shown.backOnline);
    _hide = Timer(OfflineIndicator.backOnlineFor, () {
      if (mounted) setState(() => _shown = _Shown.nothing);
    });
  }

  Future<void> _recheck() async {
    setState(() => _checking = true);
    await _status.recheck();
    if (mounted) setState(() => _checking = false);
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colours = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;

    final Widget bar = switch (_shown) {
      _Shown.nothing => const SizedBox(width: double.infinity),
      _Shown.offline => _Bar(
        key: const ValueKey<String>('offline'),
        background: colours.inverseSurface,
        foreground: colours.onInverseSurface,
        icon: Icons.cloud_off_outlined,
        message: "You're offline · showing data saved on this phone",
        action: _checking
            ? SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colours.onInverseSurface,
                ),
              )
            : TextButton(
                onPressed: _recheck,
                style: TextButton.styleFrom(
                  foregroundColor: colours.inversePrimary,
                  visualDensity: VisualDensity.compact,
                  textStyle: text.labelLarge,
                ),
                child: const Text('Retry'),
              ),
      ),
      _Shown.backOnline => _Bar(
        key: const ValueKey<String>('back-online'),
        background: colours.primary,
        foreground: colours.onPrimary,
        icon: Icons.cloud_done_outlined,
        message: 'Back online',
      ),
    };

    return Semantics(
      liveRegion: true,
      child: AnimatedSize(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        alignment: Alignment.bottomCenter,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: bar,
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  final Color background;
  final Color foreground;
  final IconData icon;
  final String message;
  final Widget? action;

  const _Bar({
    required this.background,
    required this.foreground,
    required this.icon,
    required this.message,
    this.action,
    super.key,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: background,
    child: Padding(
      padding: EdgeInsets.fromLTRB(16, 6, action == null ? 16 : 8, 6),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 32),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 18, color: foreground),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: foreground),
              ),
            ),
            if (action != null) ...<Widget>[const SizedBox(width: 8), action!],
          ],
        ),
      ),
    ),
  );
}
