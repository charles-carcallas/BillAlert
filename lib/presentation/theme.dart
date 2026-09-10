import 'package:flutter/material.dart';

/// Central design system tokens and theme for BillAlert, matching the Figma
/// design specification (node 12:459).
///
/// Spacing stays in the individual screens, while palette and type scale are
/// configured here so all screens inherit consistent visual styling.
class AppTheme {
  const AppTheme._();

  /// Figma primary brand / Log in button / Accent: #4B6C25
  static const Color primary = Color(0xFF4B6C25);

  /// Backwards-compatible alias for existing references
  static const Color seed = primary;

  /// Figma primary brand container / Logo icon background: #689633
  static const Color primaryContainer = Color(0xFF689633);

  /// Figma scaffold / surface background: #F7F9F4
  static const Color surface = Color(0xFFF7F9F4);

  /// Figma primary text (labels, title, inputs): #1A1C18
  static const Color textPrimary = Color(0xFF1A1C18);

  /// Figma secondary / subtle text (subtitle, divider "or", footer): #5B5F54
  static const Color textSecondary = Color(0xFF5B5F54);

  /// Figma input border / outline: #C2CBB2
  static const Color outline = Color(0xFFC2CBB2);

  /// Figma divider line: #DBE1D1
  static const Color outlineVariant = Color(0xFFDBE1D1);

  /// Pure white used for input and card surfaces: #FFFFFF
  static const Color surfaceWhite = Color(0xFFFFFFFF);

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      primary: primary,
      onPrimary: surfaceWhite,
      primaryContainer: primaryContainer,
      onPrimaryContainer: surfaceWhite,
      surface: surface,
      onSurface: textPrimary,
      onSurfaceVariant: textSecondary,
      outline: outline,
      outlineVariant: outlineVariant,
    );

    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: surface,
      useMaterial3: true,
      appBarTheme: const AppBarTheme(
        backgroundColor: surfaceWhite,
        foregroundColor: textPrimary,
        surfaceTintColor: Colors.transparent,
        shadowColor: outlineVariant,
        elevation: 0,
        scrolledUnderElevation: 2,
        toolbarHeight: 64,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        shape: Border(bottom: BorderSide(color: outlineVariant)),
      ),
      textTheme: const TextTheme(
        // Title ("BillAlert"): Bold, 24px, line-height 32px, tracking -0.6px
        headlineMedium: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          height: 32 / 24,
          letterSpacing: -0.6,
          color: textPrimary,
        ),
        // Screen & card header: 20px, SemiBold
        titleLarge: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        // Section titles: 16px, SemiBold
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        // Field Labels ("Username", "Password"): Medium, 14px, line-height 20px
        titleSmall: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          height: 20 / 14,
          color: textPrimary,
        ),
        // Text Input: Regular, 16px, line-height 24px
        bodyLarge: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.normal,
          height: 24 / 16,
          color: textPrimary,
        ),
        // Subtitle ("Bohol I Electric Cooperative"): Regular, 14px, line-height 20px
        bodyMedium: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.normal,
          height: 20 / 14,
          color: textSecondary,
        ),
        // Divider "or", helper note: Regular, 12px, line-height 16px
        bodySmall: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.normal,
          height: 16 / 12,
          color: textSecondary,
        ),
        // Forgot password: SemiBold, 12px, line-height 16px, color primary
        labelMedium: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          height: 16 / 12,
          color: primary,
        ),
        // Footer ("v1.0 · Bohol I Electric Cooperative"): Regular, 11px, line-height 16.5px
        labelSmall: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.normal,
          height: 16.5 / 11,
          color: textSecondary,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceWhite,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        hintStyle: const TextStyle(
          color: textSecondary,
          fontSize: 16,
          fontWeight: FontWeight.normal,
        ),
        labelStyle: const TextStyle(
          color: textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primary, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          backgroundColor: primary,
          foregroundColor: surfaceWhite,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            height: 24 / 16,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          foregroundColor: primary,
          side: const BorderSide(color: outline, width: 1.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            height: 24 / 16,
          ),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: outlineVariant,
        thickness: 1,
        space: 1,
      ),
      cardTheme: const CardThemeData(
        color: surfaceWhite,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          side: BorderSide(color: outlineVariant),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
      // NOTE: there is no navigationBarTheme. The bottom bar is not a
      // NavigationBar — Material 3 draws its selection indicator behind the
      // icon only, with no way to extend it around the label, so the selected
      // tab read as a highlighted glyph above ordinary text. `RoleTab` in
      // role_shell.dart draws the bar and takes its colours from the scheme
      // and the tokens above.
    );
  }
}
