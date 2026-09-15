import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final appearanceStorageProvider = Provider<FlutterSecureStorage>(
  (ref) => const FlutterSecureStorage(),
);

/// Device-wide preference, independent of authentication and cached bills.
final appearanceControllerProvider =
    AsyncNotifierProvider<AppearanceController, ThemeMode>(
      AppearanceController.new,
    );

class AppearanceController extends AsyncNotifier<ThemeMode> {
  static const storageKey = 'billalert_appearance';

  @override
  Future<ThemeMode> build() async {
    try {
      final saved = await ref
          .watch(appearanceStorageProvider)
          .read(key: storageKey);
      return ThemeMode.values.firstWhere(
        (mode) => mode.name == saved,
        orElse: () => ThemeMode.system,
      );
    } catch (_) {
      return ThemeMode.system;
    }
  }

  /// Only confirm a selection once it is on disk. Keep the old mode on failure.
  Future<bool> select(ThemeMode mode) async {
    try {
      await ref
          .read(appearanceStorageProvider)
          .write(key: storageKey, value: mode.name);
      state = AsyncData(mode);
      return true;
    } catch (_) {
      return false;
    }
  }
}
