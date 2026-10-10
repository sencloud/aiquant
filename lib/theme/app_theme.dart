import 'package:flutter/material.dart';

/// 喜爱 · 设计系统「纸上墨金」。
///
/// 结构取自微信（分组列表、行式导航、居中标题、克制的层次），材质取自
/// 微信读书（暖纸底、墨色文字、大留白、高行距）。两者合成一套语言：
///
/// - 纸：#F3F0E8 页面底，白面卡片浮在上面，不靠描边靠面/底对比分层。
/// - 墨：正文用近黑暖墨，不用纯黑；次级文字按 4.5:1 门槛定档，不再拿浅灰充数。
/// - 墨金：品牌主色，是旧金黄在纸上的沉色版。刻意不取绿——A 股里绿 = 跌，
///   主色若为绿会和涨跌语义打架。
///
/// AppColors 的字段名与旧版保持一致（amber 就是品牌主色），这样全 App
/// 一千多处引用会跟着一起换世界，不需要逐个改调用点。
class AppColors {
  // ---- runtime fields (do NOT mark const at call sites) ----
  static Color bgBase = _lightBgBase;
  static Color bgSurface = _lightBgSurface;
  static Color bgRaised = _lightBgRaised;
  static Color bgHover = _lightBgHover;
  static Color borderDim = _lightBorderDim;
  static Color borderMed = _lightBorderMed;

  static Color textPrimary = _lightTextPrimary;
  static Color textSecondary = _lightTextSecondary;
  static Color textTertiary = _lightTextTertiary;

  /// 主色浅底：选中态、标签底、引用块。
  static Color accentSoft = _lightAccentSoft;

  /// 主色上的前景色（按钮文字、选中图标）。
  static Color onAccent = _lightOnAccent;

  /// 唯一的投影色：暖墨的低透明度，别处不要再 hand-roll 阴影。
  static const Color shadow = Color(0x1A2A2118);

  /// 品牌主色「墨金」。旧的亮金黄 (#D97706) 是为深色底准备的，落在暖纸上会
  /// 发飘；这里压深一档，白字压在上面 5.4:1，够正文门槛。
  /// **全 App 的品牌色一律引用这个字段**，不要写死色值。
  static const Color amber = Color(0xFF9E6322);
  static const Color amberDim = Color(0xFF7A4A16);

  // 中国市场惯例：涨 = 红、跌 = 绿。positive 永远代表「正向 = 上涨 / 盈利 /
  // 买入」→ 红；negative 永远代表「负向 = 下跌 / 亏损 / 卖出」→ 绿。
  // 调用方按语义使用，不要根据数值正负硬编码颜色。
  static const Color positive = Color(0xFFCC3A2E); // 红 = 涨/盈利/买入
  static const Color negative = Color(0xFF17864E); // 绿 = 跌/亏损/卖出
  static const Color warning = Color(0xFFB4780F);
  static const Color info = Color(0xFF2F5EA8);

  /// 破坏性 / 错误 UI（删除按钮、错误图标等），与「涨跌色」语义解耦。
  static const Color danger = Color(0xFFCC3A2E);

  /// 分组标签的轮转配色：在纸上压过一档饱和度，避免互相打架。
  static const sectorPalette = [
    Color(0xFF9E6322),
    Color(0xFF2F5EA8),
    Color(0xFF17864E),
    Color(0xFF6D4AA8),
    Color(0xFFB03A34),
    Color(0xFF1F7A8C),
    Color(0xFF8A6A14),
    Color(0xFFA63A5E),
    Color(0xFF12766B),
    Color(0xFF5A4E9C),
  ];

  // ---- light palette：纸 / 墨 / 墨金 ----
  static const _lightBgBase = Color(0xFFF3F0E8); // 纸
  static const _lightBgSurface = Color(0xFFFFFFFF); // 面
  static const _lightBgRaised = Color(0xFFF8F5EE); // 内嵌块
  static const _lightBgHover = Color(0xFFEDE8DC);
  static const _lightBorderDim = Color(0xFFE7E2D6); // 发丝线
  static const _lightBorderMed = Color(0xFFD5CDBD);
  static const _lightTextPrimary = Color(0xFF1F1C17); // 墨
  static const _lightTextSecondary = Color(0xFF5F5850);
  static const _lightTextTertiary = Color(0xFF7C746A);
  static const _lightAccentSoft = Color(0xFFF1E6D3);
  static const _lightOnAccent = Color(0xFFFFFFFF);

  // ---- dark palette：墨夜（当前入口已隐藏，保留完整一套以免半残）----
  static const _darkBgBase = Color(0xFF121110);
  static const _darkBgSurface = Color(0xFF1C1A18);
  static const _darkBgRaised = Color(0xFF232120);
  static const _darkBgHover = Color(0xFF2B2826);
  static const _darkBorderDim = Color(0xFF302D2A);
  static const _darkBorderMed = Color(0xFF443F3A);
  static const _darkTextPrimary = Color(0xFFEDE9E1);
  static const _darkTextSecondary = Color(0xFFAFA79C);
  static const _darkTextTertiary = Color(0xFF8B8378);
  static const _darkAccentSoft = Color(0xFF3A2B18);
  static const _darkOnAccent = Color(0xFF121110);

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
    accentSoft = dark ? _darkAccentSoft : _lightAccentSoft;
    onAccent = dark ? _darkOnAccent : _lightOnAccent;
  }
}

/// 间距刻度。全 App 只用这几个值，禁止再写 7 / 11 / 13 这类散数。
class AppSpace {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;

  /// 页面左右安全边距。
  static const double gutter = 16;
}

/// 圆角刻度。卡片 12–14，小控件用 pill。
class AppRadius {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 14;
  static const double pill = 999;
}

/// 字体刻度。
///
/// 旧版正文 12–13px，手机竖屏单手阅读偏小；微信正文 17、微信读书正文 17–18
/// 且行高 1.7。这里把基准抬到 15，正文行高 1.45，阅读段落 1.75。
class AppType {
  /// 正文 / 界面用无衬线，跟随系统（PingFang SC / 微软雅黑 / Noto Sans SC）。
  static const sansFallback = <String>[
    'PingFang SC',
    'Microsoft YaHei',
    'Noto Sans SC',
    'Noto Sans CJK SC',
    'sans-serif',
  ];

  /// 阅读体：只在开屏题字、结论句、数字大字这些「值得停一下」的地方用。
  /// 平台自带衬线，不额外打包字体（CJK 字体动辄几十 MB，首版不值得）。
  static const readFallback = <String>[
    'Songti SC',
    'Noto Serif CJK SC',
    'Noto Serif SC',
    'SimSun',
    'serif',
  ];

  /// 大数 / 结论字。衬线 + 收紧字距。
  static const TextStyle display = TextStyle(
    fontSize: 28,
    height: 1.15,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.4,
    fontFamilyFallback: readFallback,
  );

  /// 页面标题（导航栏）与卡片大标题。
  static const TextStyle title = TextStyle(
    fontSize: 17,
    height: 1.3,
    fontWeight: FontWeight.w600,
    fontFamilyFallback: sansFallback,
  );

  /// 小节名字（分组头）。
  static const TextStyle section = TextStyle(
    fontSize: 13,
    height: 1.3,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.3,
    fontFamilyFallback: sansFallback,
  );

  /// 列表主行文字。微信列表行就是这么重。
  static const TextStyle body = TextStyle(
    fontSize: 15,
    height: 1.45,
    fontWeight: FontWeight.w400,
    fontFamilyFallback: sansFallback,
  );

  /// 可读段落（结论、说明、聊天正文）：行高给到 1.75。
  static const TextStyle read = TextStyle(
    fontSize: 15,
    height: 1.75,
    fontWeight: FontWeight.w400,
    fontFamilyFallback: sansFallback,
  );

  /// 次级文字。
  static const TextStyle caption = TextStyle(
    fontSize: 12.5,
    height: 1.5,
    fontWeight: FontWeight.w400,
    fontFamilyFallback: sansFallback,
  );

  /// 最小号：单位、脚注、标签。
  static const TextStyle micro = TextStyle(
    fontSize: 11,
    height: 1.4,
    fontWeight: FontWeight.w500,
    fontFamilyFallback: sansFallback,
  );

  /// 数字用等宽字形，避免表格里数字跳舞。
  static const numericFallback = <String>[
    'SF Mono',
    'Roboto Mono',
    'Menlo',
    'Consolas',
    'monospace',
  ];
}

class AppTheme {
  static ThemeData build(ThemeMode mode) {
    AppColors.applyMode(mode);
    return mode == ThemeMode.dark ? _dark() : _light();
  }

  static ThemeData _light() {
    final base = ThemeData.light(useMaterial3: true);
    return _common(
      base,
      ColorScheme.light(
        primary: AppColors.amber,
        secondary: AppColors.amberDim,
        surface: AppColors.bgSurface,
        error: AppColors.danger,
        onPrimary: AppColors.onAccent,
        onSecondary: AppColors.onAccent,
        onSurface: AppColors.textPrimary,
      ),
    );
  }

  static ThemeData _dark() {
    final base = ThemeData.dark(useMaterial3: true);
    return _common(
      base,
      ColorScheme.dark(
        primary: AppColors.amber,
        secondary: AppColors.amberDim,
        surface: AppColors.bgSurface,
        error: AppColors.danger,
        onPrimary: AppColors.onAccent,
        onSecondary: AppColors.onAccent,
        onSurface: AppColors.textPrimary,
      ),
    );
  }

  static ThemeData _common(ThemeData base, ColorScheme scheme) {
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.bgBase,
      colorScheme: scheme,
      textTheme: base.textTheme
          .apply(
            bodyColor: AppColors.textPrimary,
            displayColor: AppColors.textPrimary,
            fontFamilyFallback: AppType.sansFallback,
          )
          .copyWith(
            // 只覆盖「不指定字体时」的默认档，显式写了 fontSize 的调用点不受影响。
            bodyLarge: AppType.body.copyWith(color: AppColors.textPrimary),
            bodyMedium: AppType.body.copyWith(color: AppColors.textPrimary),
            bodySmall: AppType.caption.copyWith(color: AppColors.textSecondary),
            titleLarge: AppType.title.copyWith(color: AppColors.textPrimary),
            titleMedium: AppType.section.copyWith(color: AppColors.textPrimary),
            labelLarge: AppType.body.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
      appBarTheme: AppBarTheme(
        // 微信式导航栏：和页面同底色，（原文无 elevation）靠发丝线收边。
        backgroundColor: AppColors.bgBase,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: AppColors.textPrimary, size: 22),
        titleTextStyle: AppType.title.copyWith(color: AppColors.textPrimary),
        shape: Border(bottom: BorderSide(color: AppColors.borderDim)),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: AppColors.bgSurface,
        selectedItemColor: AppColors.amber,
        unselectedItemColor: AppColors.textTertiary,
        type: BottomNavigationBarType.fixed,
        showUnselectedLabels: true,
        selectedLabelStyle:
            const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontSize: 11),
      ),
      dividerTheme: DividerThemeData(
        color: AppColors.borderDim,
        thickness: 0.5,
        space: 0.5,
      ),
      dividerColor: AppColors.borderDim,
      cardColor: AppColors.bgSurface,
      // 卡片只声明一层深度：白面 + 大圆角，不用描边，也不用宽阴影。
      cardTheme: CardThemeData(
        color: AppColors.bgSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.lg)),
        ),
      ),
      listTileTheme: ListTileThemeData(
        minVerticalPadding: AppSpace.md,
        titleTextStyle: AppType.body.copyWith(color: AppColors.textPrimary),
        subtitleTextStyle:
            AppType.caption.copyWith(color: AppColors.textSecondary),
        iconColor: AppColors.textSecondary,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.md)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.bgSurface,
        hintStyle: AppType.body.copyWith(color: AppColors.textTertiary),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: AppColors.borderDim),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: AppColors.borderDim),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.amber, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.danger, width: 1.2),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.amber,
          foregroundColor: AppColors.onAccent,
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md)),
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.xl, vertical: 14),
          textStyle: const TextStyle(
              fontWeight: FontWeight.w600, fontSize: 15, height: 1.2),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          side: BorderSide(color: AppColors.borderMed),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md)),
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.xl, vertical: 14),
          textStyle: const TextStyle(
              fontWeight: FontWeight.w600, fontSize: 15, height: 1.2),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.amber,
          textStyle: const TextStyle(
              fontWeight: FontWeight.w600, fontSize: 15, height: 1.2),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.bgRaised,
        selectedColor: AppColors.accentSoft,
        side: BorderSide(color: AppColors.borderDim),
        labelStyle: AppType.micro.copyWith(color: AppColors.textSecondary),
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.bgSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg)),
        titleTextStyle: AppType.title.copyWith(color: AppColors.textPrimary),
        contentTextStyle:
            AppType.body.copyWith(color: AppColors.textSecondary),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: AppColors.bgSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.textPrimary,
        contentTextStyle: AppType.body.copyWith(color: AppColors.bgSurface),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md)),
      ),
      progressIndicatorTheme:
          const ProgressIndicatorThemeData(color: AppColors.amber),
      splashColor: AppColors.bgHover,
      highlightColor: AppColors.bgHover,
    );
  }
}

/// Pick a deterministic colour for a sector / category label.
Color sectorColorFor(String label) {
  if (label.isEmpty) return AppColors.textTertiary;
  final h = label.codeUnits.fold<int>(0, (acc, c) => acc + c);
  return AppColors.sectorPalette[h % AppColors.sectorPalette.length];
}
