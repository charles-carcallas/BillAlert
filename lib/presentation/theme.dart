import 'package:flutter/material.dart';

/// One place for colour and type, so four people building four role sections
/// do not each invent their own blue.
///
/// Deliberately thin for Week 11. Polish, dark mode (GEN-12) and the rest of
/// the visual design come later; a screen that moves real data is worth more
/// right now than a beautiful one showing mock data.
class AppTheme {
  const AppTheme._();

  /// BIEC's working colour in the mockups.
  static const Color seed = Color(0xFF0B6E4F);

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(seedColor: seed);
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        filled: true,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
    );
  }
}
