import 'package:flutter/material.dart';

/// App palette. Fields are mutable so the whole app can switch between
/// dark / light at runtime — call [AppColors.applyMode] then rebuild the
/// `MaterialApp` (see `lib/app.dart`).
///
/// Bloomberg-style: amber accent, signed colour for gains (green) /
/// losses (red). The light variant keeps the same accent so the look stays
/// consistent across modes.
class AppColors {
  // ---- runtime fields (do NOT mark const at call sites) ----
  static Color bgBase = _darkBgBase;
  static Color bgSurface = _darkBgSurface;
  static Color bgRaised = _darkBgRaised;
  static Color bgHover = _darkBgHover;
  static Color borderDim = _darkBorderDim;
  static Color borderMed = _darkBorderMed;

  static Color textPrimary = _darkTextPrimary;
  static Color textSecondary = _darkTextSecondary;
  static Color textTertiary = _darkTextTertiary;

  // Accents that are the same in both modes.
  static const Color amber = Color(0xFFD97706);
  static const Color amberDim = Color(0xFFB35B05);
  static const Color positive = Color(0xFF16A34A);
  static const Color negative = Color(0xFFDC2626);
  static const Color warning = Color(0xFFEAB308);
  static const Color info = Color(0xFF2563EB);

  /// Used for tabs / accent badges that are purely decorative.
  static const sectorPalette = [
    Color(0xFFD97706),
    Color(0xFF2563EB),
    Color(0xFF16A34A),
    Color(0xFF9333EA),
    Color(0xFFDC2626),
    Color(0xFF0EA5E9),
    Color(0xFFCA8A04),
    Color(0xFFE11D48),
    Color(0xFF14B8A6),
    Color(0xFF8B5CF6),
  ];

  // ---- dark palette (the original Bloomberg-dark look) ----
  static const _darkBgBase = Color(0xFF0A0A0A);
  static const _darkBgSurface = Color(0xFF141414);
  static const _darkBgRaised = Color(0xFF1C1C1C);
  static const _darkBgHover = Color(0xFF222222);
  static const _darkBorderDim = Color(0xFF2A2A2A);
  static const _darkBorderMed = Color(0xFF3A3A3A);
  static const _darkTextPrimary = Color(0xFFE5E5E5);
  static const _darkTextSecondary = Color(0xFF9E9E9E);
  static const _darkTextTertiary = Color(0xFF6B6B6B);

  // ---- light palette (Bloomberg-light, near-white surfaces) ----
  static const _lightBgBase = Color(0xFFF5F5F5);
  static const _lightBgSurface = Color(0xFFFFFFFF);
  static const _lightBgRaised = Color(0xFFFAFAFA);
  static const _lightBgHover = Color(0xFFEFEFEF);
  static const _lightBorderDim = Color(0xFFE5E5E5);
  static const _lightBorderMed = Color(0xFFCCCCCC);
  static const _lightTextPrimary = Color(0xFF1A1A1A);
  static const _lightTextSecondary = Color(0xFF5A5A5A);
  static const _lightTextTertiary = Color(0xFF999999);

  /// Push a palette into the static fields. The next `build` on the
  /// `MaterialApp` will pick it up.
  static void applyMode(ThemeMode mode) {
    final dark = mode == ThemeMode.dark;
    bgBase = dark ? _darkBgBase : _lightBgBase;
    bgSurface = dark ? _darkBgSurface : _lightBgSurface;
    bgRaised = dark ? _darkBgRaised : _lightBgRaised;
    bgHover = dark ? _darkBgHover : _lightBgHover;
    borderDim = dark ? _darkBorderDim : _lightBorderDim;
    borderMed = dark ? _darkBorderMed : _lightBorderMed;
    textPrimary = dark ? _darkTextPrimary : _lightTextPrimary;
    textSecondary = dark ? _darkTextSecondary : _lightTextSecondary;
    textTertiary = dark ? _darkTextTertiary : _lightTextTertiary;
  }
}

class AppTheme {
  static ThemeData build(ThemeMode mode) {
    AppColors.applyMode(mode);
    return mode == ThemeMode.dark ? _dark() : _light();
  }

  static ThemeData _dark() {
    final base = ThemeData.dark(useMaterial3: true);
    return _common(
      base,
      ColorScheme.dark(
        primary: AppColors.amber,
        secondary: AppColors.amberDim,
        surface: AppColors.bgSurface,
        error: AppColors.negative,
        onPrimary: Colors.black,
        onSecondary: Colors.black,
        onSurface: AppColors.textPrimary,
      ),
    );
  }

  static ThemeData _light() {
    final base = ThemeData.light(useMaterial3: true);
    return _common(
      base,
      ColorScheme.light(
        primary: AppColors.amber,
        secondary: AppColors.amberDim,
        surface: AppColors.bgSurface,
        error: AppColors.negative,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: AppColors.textPrimary,
      ),
    );
  }

  static ThemeData _common(ThemeData base, ColorScheme scheme) {
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.bgBase,
      colorScheme: scheme,
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.textPrimary,
        displayColor: AppColors.textPrimary,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.bgSurface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: const TextStyle(
          color: AppColors.amber,
          fontSize: 14,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: AppColors.bgSurface,
        selectedItemColor: AppColors.amber,
        unselectedItemColor: AppColors.textTertiary,
        type: BottomNavigationBarType.fixed,
        showUnselectedLabels: true,
        selectedLabelStyle:
            const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
        unselectedLabelStyle: const TextStyle(fontSize: 11),
      ),
      dividerColor: AppColors.borderDim,
      cardColor: AppColors.bgRaised,
      cardTheme: CardThemeData(
        color: AppColors.bgRaised,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(Radius.circular(6)),
          side: BorderSide(color: AppColors.borderDim),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.bgBase,
        hintStyle: TextStyle(color: AppColors.textTertiary, fontSize: 12),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: AppColors.borderMed),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: AppColors.borderMed),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: AppColors.amber, width: 1.4),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.amber,
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          textStyle:
              const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          side: BorderSide(color: AppColors.borderMed),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          textStyle:
              const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.amber,
          textStyle:
              const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.bgSurface,
        elevation: 0,
        titleTextStyle: const TextStyle(
          color: AppColors.amber,
          fontSize: 14,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
        contentTextStyle:
            TextStyle(color: AppColors.textPrimary, fontSize: 12),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.bgRaised,
        contentTextStyle:
            TextStyle(color: AppColors.textPrimary, fontSize: 12),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

/// Pick a deterministic colour for a sector / category label.
Color sectorColorFor(String label) {
  if (label.isEmpty) return AppColors.textTertiary;
  final h = label.codeUnits.fold<int>(0, (acc, c) => acc + c);
  return AppColors.sectorPalette[h % AppColors.sectorPalette.length];
}
