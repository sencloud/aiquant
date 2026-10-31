import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// TradingView 式浅色行情终端配色。只用于行情首页及其选择器。
class MarketColors {
  MarketColors._();

  static const background = Color(0xFFFFFFFF);
  static const panel = Color(0xFFF8F9FD);
  static const panelRaised = Color(0xFFF0F3FA);
  static const border = Color(0xFFE0E3EB);
  static const grid = Color(0xFFE9ECF2);
  static const textPrimary = Color(0xFF131722);
  static const textSecondary = Color(0xFF434651);
  static const textMuted = Color(0xFF6A6D78);
  static const accent = Color(0xFF2962FF);
  static const accentSoft = Color(0xFFEAF0FF);
  static const up = Color(0xFFD93025);
  static const down = Color(0xFF007A5A);
  static const support = Color(0xFF00796B);
  static const resistance = Color(0xFFC65300);
  static const warning = Color(0xFFB26A00);
  static const ma5 = Color(0xFF2962FF);
  static const ma10 = Color(0xFFD97706);
  static const ma20 = Color(0xFF8E24AA);
}

ThemeData buildMarketTheme() {
  final base = ThemeData.light(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: MarketColors.background,
    colorScheme: const ColorScheme.light(
      primary: MarketColors.accent,
      secondary: MarketColors.accent,
      surface: MarketColors.panel,
      error: MarketColors.up,
      onPrimary: Colors.white,
      onSurface: MarketColors.textPrimary,
    ),
    dividerTheme: const DividerThemeData(
      color: MarketColors.border,
      thickness: 0.5,
      space: 0.5,
    ),
    textTheme: base.textTheme.apply(
      bodyColor: MarketColors.textPrimary,
      displayColor: MarketColors.textPrimary,
      fontFamilyFallback: AppType.sansFallback,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: MarketColors.panelRaised,
      hintStyle: const TextStyle(color: MarketColors.textMuted, fontSize: 14),
      prefixIconColor: MarketColors.textMuted,
      suffixIconColor: MarketColors.textMuted,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: MarketColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: MarketColors.accent, width: 1),
      ),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: MarketColors.panel,
      surfaceTintColor: Colors.transparent,
      elevation: 12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: MarketColors.accent,
      linearTrackColor: MarketColors.grid,
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: MarketColors.textPrimary,
      contentTextStyle: TextStyle(color: Colors.white),
      behavior: SnackBarBehavior.floating,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: MarketColors.panelRaised,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: MarketColors.border),
      ),
      textStyle: const TextStyle(color: MarketColors.textPrimary, fontSize: 12),
    ),
  );
}
