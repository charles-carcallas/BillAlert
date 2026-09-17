import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../appearance_controller.dart';

/// System / Light / Dark, as one segmented control. The surrounding card
/// supplies the title and description.
class AppearanceSetting extends ConsumerStatefulWidget {
  const AppearanceSetting({super.key});

  @override
  ConsumerState<AppearanceSetting> createState() => _AppearanceSettingState();
}

class _AppearanceSettingState extends ConsumerState<AppearanceSetting> {
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final preference = ref.watch(appearanceControllerProvider);
    final mode = preference.value ?? ThemeMode.system;
    final bool enabled = !_saving && !preference.isLoading;
    return SegmentedButton<ThemeMode>(
      showSelectedIcon: false,
      segments: <ButtonSegment<ThemeMode>>[
        for (final option in ThemeMode.values)
          ButtonSegment<ThemeMode>(
            value: option,
            enabled: enabled,
            label: Text(switch (option) {
              ThemeMode.system => 'System',
              ThemeMode.light => 'Light',
              ThemeMode.dark => 'Dark',
            }),
            icon: Icon(switch (option) {
              ThemeMode.system => Icons.brightness_auto_outlined,
              ThemeMode.light => Icons.light_mode_outlined,
              ThemeMode.dark => Icons.dark_mode_outlined,
            }),
          ),
      ],
      selected: <ThemeMode>{mode},
      onSelectionChanged: (Set<ThemeMode> chosen) => _select(chosen.single),
    );
  }

  Future<void> _select(ThemeMode mode) async {
    setState(() => _saving = true);
    final saved = await ref
        .read(appearanceControllerProvider.notifier)
        .select(mode);
    if (!mounted) return;
    setState(() => _saving = false);
    if (!saved) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Appearance could not be saved on this device. Try again.',
          ),
        ),
      );
    }
  }
}
