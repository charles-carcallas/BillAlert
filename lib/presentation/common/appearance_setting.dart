import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../appearance_controller.dart';

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
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Choose how BillAlert looks on this device.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          for (final option in ThemeMode.values)
            Material(
              color: Colors.transparent,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(switch (option) {
                  ThemeMode.system => 'System',
                  ThemeMode.light => 'Light',
                  ThemeMode.dark => 'Dark',
                }),
                subtitle: option == ThemeMode.system
                    ? const Text('Follow your device settings')
                    : null,
                leading: Icon(switch (option) {
                  ThemeMode.system => Icons.brightness_auto_outlined,
                  ThemeMode.light => Icons.light_mode_outlined,
                  ThemeMode.dark => Icons.dark_mode_outlined,
                }),
                trailing: mode == option
                    ? Icon(
                        Icons.check,
                        color: Theme.of(context).colorScheme.primary,
                      )
                    : null,
                selected: mode == option,
                enabled: !_saving && !preference.isLoading,
                onTap: () => _select(option),
              ),
            ),
        ],
      ),
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
