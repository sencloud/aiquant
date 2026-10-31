import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// TradingView 式深色行情终端配色。只用于行情首页及其选择器。
class MarketColors {
  MarketColors._();

  static const background = Color(0xFF131722);
  static const panel = Color(0xFF1E222D);
  static const panelRaised = Color(0xFF252A36);
  static const border = Color(0xFF2A2E39);
  static const grid = Color(0xFF1F2430);
  static const textPrimary = Color(0xFFD1D4DC);
  static const textSecondary = Color(0xFFA3A6AF);
  static const textMuted = Color(0xFF787B86);
  static const accent = Color(0xFF2962FF);
  static const accentSoft = Color(0x262962FF);
  static const up = Color(0xFFF23645);
  static const down = Color(0xFF089981);
  static const support = Color(0xFF26A69A);
  static const resistance = Color(0xFFFF9800);
  static const warning = Color(0xFFF7A600);
  static const ma5 = Color(0xFF2962FF);
  static const ma10 = Color(0xFFFF9800);
  static const ma20 = Color(0xFFAB47BC);
}

ThemeData buildMarketTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: MarketColors.background,
    colorScheme: const ColorScheme.dark(
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
      backgroundColor: MarketColors.panelRaised,
      contentTextStyle: TextStyle(color: MarketColors.textPrimary),
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
