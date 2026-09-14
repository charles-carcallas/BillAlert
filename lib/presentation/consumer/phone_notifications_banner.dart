import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';

/// Whether BillAlert may show notifications on this phone.
///
/// Fails towards "on": a check that cannot answer should not nag the
/// household about a setting that may be fine.
final phoneNotificationsOnProvider = FutureProvider.autoDispose<bool>((
  Ref ref,
) async {
  try {
    return await ref.watch(notificationPermissionProvider).isGranted();
  } catch (_) {
    return true;
  }
});

/// Shown in the Inbox when the household has turned notifications off.
///
/// Android shows its permission prompt at most twice. After that the only way
/// back is the phone's settings, and without this the household would simply
/// stop hearing about new bills with nothing to say why.
class PhoneNotificationsBanner extends ConsumerStatefulWidget {
  const PhoneNotificationsBanner({super.key});

  @override
  ConsumerState<PhoneNotificationsBanner> createState() =>
      _PhoneNotificationsBannerState();
}

class _PhoneNotificationsBannerState
    extends ConsumerState<PhoneNotificationsBanner> {
  /// Checks again when the household comes back from the settings screen.
  late final AppLifecycleListener _lifecycle = AppLifecycleListener(
    onResume: () => ref.invalidate(phoneNotificationsOnProvider),
  );

  @override
  void initState() {
    super.initState();
    _lifecycle;
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool on = ref.watch(phoneNotificationsOnProvider).value ?? true;
    if (on) return const SizedBox.shrink();

    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colours = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colours.errorContainer.withValues(alpha: 0.45),
          border: Border.all(color: colours.error.withValues(alpha: 0.5)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(Icons.notifications_off_outlined, color: colours.error),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Phone notifications are off',
                    style: text.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Turn them on to hear about new bills and due dates '
                    'without opening BillAlert.',
                    style: text.bodySmall,
                  ),
                  const SizedBox(height: 6),
                  TextButton(
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 36),
                    ),
                    onPressed: () =>
                        ref.read(notificationPermissionProvider).openSettings(),
                    child: const Text('Turn on in settings'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
