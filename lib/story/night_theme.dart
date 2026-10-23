import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 《天亮以前》的夜色。和主 App 的微信灰白完全分开：这里是深夜、屏幕、
/// 暖灯和雨，不做浅色，也不跟随主 App 的主题。
class NightColors {
  static const bg = Color(0xFF0E1118);
  static const surface = Color(0xFF1B2130);
  static const surfaceRaised = Color(0xFF242B3D);
  static const border = Color(0xFF2E374D);
  static const borderSoft = Color(0xFF202738);
  static const paper = Color(0xFFF2EDE4);
  static const muted = Color(0xFF8A93A6);
  static const faint = Color(0xFF5C6578);
  static const amber = Color(0xFFE8B36A);
  static const amberDim = Color(0xFFB9894C);
  static const heart = Color(0xFFE4576B);
  static const rain = Color(0xFF7FB3C8);
  static const ink = Color(0xFF12141A);
  static const good = Color(0xFF9FD3B4);
}

class NightType {
  static const fallback = AppType.sansFallback;

  static const _family = 'NightSans';

  static const display = TextStyle(
    fontFamily: _family,
    fontSize: 30,
    height: 1.2,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.4,
    color: NightColors.paper,
    fontFamilyFallback: fallback,
  );

  static const title = TextStyle(
    fontFamily: _family,
    fontSize: 17,
    height: 1.3,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.6,
    color: NightColors.paper,
    fontFamilyFallback: fallback,
  );

  static const body = TextStyle(
    fontFamily: _family,
    fontSize: 15,
    height: 1.65,
    color: NightColors.paper,
    fontFamilyFallback: fallback,
  );

  static const read = TextStyle(
    fontFamily: _family,
    fontSize: 14,
    height: 1.7,
    color: NightColors.muted,
    fontFamilyFallback: fallback,
  );

  static const caption = TextStyle(
    fontFamily: _family,
    fontSize: 12,
    height: 1.5,
    color: NightColors.muted,
    fontFamilyFallback: fallback,
  );

  static const micro = TextStyle(
    fontFamily: _family,
    fontSize: 10.5,
    height: 1.4,
    letterSpacing: 0.4,
    color: NightColors.faint,
    fontFamilyFallback: fallback,
  );

  static const mono = TextStyle(
    fontFamily: _family,
    fontSize: 11,
    height: 1.4,
    letterSpacing: 0.8,
    color: NightColors.muted,
    fontFamilyFallback: fallback,
    fontFeatures: [FontFeature.tabularFigures()],
  );
}

ThemeData buildNightTheme() {
  return ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    scaffoldBackgroundColor: NightColors.bg,
    colorScheme: const ColorScheme.dark(
      primary: NightColors.amber,
      onPrimary: NightColors.ink,
      secondary: NightColors.heart,
      onSecondary: NightColors.paper,
      surface: NightColors.surface,
      onSurface: NightColors.paper,
      error: NightColors.heart,
      onError: NightColors.paper,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: NightColors.bg,
      foregroundColor: NightColors.paper,
      elevation: 0,
      centerTitle: true,
    ),
    dividerTheme: const DividerThemeData(
      color: NightColors.borderSoft,
      thickness: 1,
      space: 1,
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: NightColors.surfaceRaised,
      hintStyle: NightType.caption,
      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: NightColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: NightColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: NightColors.amber),
      ),
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: NightColors.amber,
      selectionColor: Color(0x44E8B36A),
      selectionHandleColor: NightColors.amber,
    ),
    splashColor: const Color(0x1FE8B36A),
    highlightColor: Colors.transparent,
  );
}
