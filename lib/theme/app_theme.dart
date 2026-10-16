import 'package:flutter/material.dart';

/// 喜爱 · 设计系统「微信式 + 墨金」。
///
/// 2026-10 这次重构把视觉世界整体换成微信那一套：灰底白列表、行式导航、
/// 居中标题、一条发丝线收边；**主色仍是喜爱自己的墨金**，只出现在
/// 「选中 / 主动作 / 自己说的话」上。
///
/// - 页底：#EDEDED 微信灰。列表是白面浮在灰底上，靠面/底对比分层，不投影。
/// - 墨：#191919 正文、#7F7F7F 次级、#B2B2B2 弱字。
/// - 墨金：#9E6322 品牌主色（旧「纸上墨金」那一支），选中态、主按钮、
///   发送按钮、自己的气泡。
///
/// 主色刻意不取绿：微信绿很好看，但在 A 股产品里绿 = 跌，主色和涨跌语义
/// 打架的代价远大于审美收益（这条和「纸上墨金」时期一致）。
/// 涨跌语义色独立：positive 永远是红（涨），negative 永远是深绿（跌），
/// 数字场景只在 positive / negative 里取色，不要用 amber 表示涨跌。
///
/// 只有浅色一套。深色模式在 App 里没有入口（AppConfig.themeMode 恒为
/// light），就不再维护第二套取值，免得半残。
class AppColors {
  // ---- 底与面 ----

  /// 页底：微信灰。
  static Color bgBase = const Color(0xFFEDEDED);

  /// 面：列表行、分组卡。
  static Color bgSurface = const Color(0xFFFFFFFF);

  /// 内嵌块：输入框、引用块、代码块。
  static Color bgRaised = const Color(0xFFF7F7F7);

  /// 按压 / 选中反馈。
  static Color bgHover = const Color(0xFFE3E3E3);

  /// 发丝线：分组内分隔、导航栏收边。
  static Color borderDim = const Color(0xFFE5E5E5);

  /// 描边：次级按钮、需要看得见的边框。
  static Color borderMed = const Color(0xFFDCDCDC);

  // ---- 字 ----
  static Color textPrimary = const Color(0xFF191919);
  static Color textSecondary = const Color(0xFF7F7F7F);
  static Color textTertiary = const Color(0xFFB2B2B2);

  // ---- 品牌 ----

  /// 品牌主色：墨金。选中态、主动作、发送按钮、自己的气泡。
  static Color amber = const Color(0xFF9E6322);

  /// 主色深一档：浅金底上的金字、按下态。
  static Color amberDim = const Color(0xFF7A4A16);

  /// 主色浅底：选中 chip、标签底、浅金背景。
  static Color accentSoft = const Color(0xFFF1E6D3);

  /// 主色上的前景色。
  static Color onAccent = const Color(0xFFFFFFFF);

  /// 自己发出去的气泡：主色实心（白字压在上面 5.4:1）。
  static Color bubbleSelf = const Color(0xFF9E6322);

  /// 别人发来的气泡：白面。
  static Color bubbleOther = const Color(0xFFFFFFFF);

  /// 唯一的投影色（浮层、弹层用），别处不要再 hand-roll 阴影。
  static const Color shadow = Color(0x14000000);

  // ---- 语义色 ----
  //
  // 中国市场惯例：涨 = 红、跌 = 绿。positive 永远代表「正向 = 上涨 / 盈利 /
  // 买入」→ 红；negative 永远代表「负向 = 下跌 / 亏损 / 卖出」→ 绿。
  // 调用方按语义使用，不要根据数值正负硬编码颜色。
  static const Color positive = Color(0xFFFA5151); // 红 = 涨/盈利/买入
  static const Color negative = Color(0xFF17864E); // 绿 = 跌/亏损/卖出
  static const Color warning = Color(0xFFFA9D3B);
  static const Color info = Color(0xFF576B95); // 微信蓝：链接、可点文字

  /// 破坏性 / 错误 UI（删除按钮、退出登录等），与涨跌色语义解耦。
  static const Color danger = Color(0xFFFA5151);

  /// 分组标签的轮转配色。
  static const sectorPalette = [
    Color(0xFF9E6322),
    Color(0xFF576B95),
    Color(0xFFFA9D3B),
    Color(0xFF8A6DE9),
    Color(0xFFFA5151),
    Color(0xFF10AEFF),
    Color(0xFF9E6322),
    Color(0xFFA63A5E),
    Color(0xFF17864E),
    Color(0xFF5A4E9C),
  ];
}

/// 间距刻度。全 App 只用这几个值，禁止再写 7 / 11 / 13 这类散数。
class AppSpace {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;

  /// 页面左右安全边距（微信列表行的左右留白）。
  static const double gutter = 16;
}

/// 圆角刻度。微信的克制：卡片 8，行内小控件 4 到 6，胶囊用 pill。
class AppRadius {
  static const double sm = 4;
  static const double md = 6;
  static const double lg = 8;
  static const double pill = 999;
}

/// 字体刻度。
///
/// 微信的正文是 17，行高松；界面全部无衬线（PingFang SC / 微软雅黑 /
/// Noto Sans SC）。开屏题字是唯一还用衬线的地方，见
/// lib/screens/splash/splash_screen.dart。
class AppType {
  /// 界面用无衬线，跟随系统。
  static const sansFallback = <String>[
    'PingFang SC',
    'Microsoft YaHei',
    'Noto Sans SC',
    'Noto Sans CJK SC',
    'sans-serif',
  ];

  /// 衬线：只在开屏题字这一处用。
  static const readFallback = <String>[
    'Songti SC',
    'Noto Serif CJK SC',
    'Noto Serif SC',
    'SimSun',
    'serif',
  ];

  /// 大数 / 结论字。
  static const TextStyle display = TextStyle(
    fontSize: 28,
    height: 1.2,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.3,
    fontFamilyFallback: sansFallback,
  );

  /// 导航标题、页面大标题、聊天标题。
  static const TextStyle title = TextStyle(
    fontSize: 17,
    height: 1.3,
    fontWeight: FontWeight.w600,
    fontFamilyFallback: sansFallback,
  );

  /// 小节名字（分组头）。
  static const TextStyle section = TextStyle(
    fontSize: 14,
    height: 1.3,
    fontWeight: FontWeight.w400,
    fontFamilyFallback: sansFallback,
  );

  /// 列表主行 / 正文。微信正文 17，这里取 16：一行放得下的字更多，
  /// 表格类页面（组合、证伪档案）也不会被撑破。
  static const TextStyle body = TextStyle(
    fontSize: 16,
    height: 1.4,
    fontWeight: FontWeight.w400,
    fontFamilyFallback: sansFallback,
  );

  /// 可读段落（结论、说明、聊天正文）。
  static const TextStyle read = TextStyle(
    fontSize: 16,
    height: 1.6,
    fontWeight: FontWeight.w400,
    fontFamilyFallback: sansFallback,
  );

  /// 次级文字、聊天气泡正文。
  static const TextStyle caption = TextStyle(
    fontSize: 13,
    height: 1.45,
    fontWeight: FontWeight.w400,
    fontFamilyFallback: sansFallback,
  );

  /// 最小号：时间戳、单位、角标。
  static const TextStyle micro = TextStyle(
    fontSize: 11.5,
    height: 1.4,
    fontWeight: FontWeight.w400,
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
  /// 只有浅色一套：微信式界面在浅色下才是「那个样子」。
  static ThemeData build([ThemeMode mode = ThemeMode.light]) => _light();

  static ThemeData _light() {
    final base = ThemeData.light(useMaterial3: true);
    final scheme = ColorScheme.light(
      primary: AppColors.amber,
      secondary: AppColors.amberDim,
      surface: AppColors.bgSurface,
      error: AppColors.danger,
      onPrimary: AppColors.onAccent,
      onSecondary: AppColors.onAccent,
      onSurface: AppColors.textPrimary,
    );
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
        // 微信的导航栏和页面同色（灰），不浮起来、不投影，只有一条发丝线收边。
        backgroundColor: AppColors.bgBase,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: AppColors.textPrimary, size: 22),
        titleTextStyle: AppType.title,
        shape:
            Border(bottom: BorderSide(color: AppColors.borderDim, width: 0.5)),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: AppColors.bgSurface,
        selectedItemColor: AppColors.amber,
        unselectedItemColor: AppColors.textSecondary,
        type: BottomNavigationBarType.fixed,
        showUnselectedLabels: true,
        selectedLabelStyle:
            const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
        unselectedLabelStyle: const TextStyle(fontSize: 11),
      ),
      dividerTheme: DividerThemeData(
        color: AppColors.borderDim,
        thickness: 0.5,
        space: 0.5,
      ),
      dividerColor: AppColors.borderDim,
      cardColor: AppColors.bgSurface,
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
        titleTextStyle: AppType.body,
        subtitleTextStyle: TextStyle(
          fontSize: 13,
          color: AppColors.textSecondary,
          fontFamilyFallback: AppType.sansFallback,
        ),
        iconColor: AppColors.textSecondary,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.bgSurface,
        hintStyle: AppType.body.copyWith(color: AppColors.textTertiary),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: 12),
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
          borderSide: BorderSide(color: AppColors.amber, width: 1.2),
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
          padding:
              const EdgeInsets.symmetric(horizontal: AppSpace.xl, vertical: 12),
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
          padding:
              const EdgeInsets.symmetric(horizontal: AppSpace.xl, vertical: 12),
          textStyle: const TextStyle(
              fontWeight: FontWeight.w500, fontSize: 15, height: 1.2),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.amber,
          textStyle: const TextStyle(
              fontWeight: FontWeight.w500, fontSize: 15, height: 1.2),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.bgRaised,
        selectedColor: AppColors.accentSoft,
        side: BorderSide(color: AppColors.borderDim),
        labelStyle: AppType.micro,
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.bgSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(10)),
        ),
        titleTextStyle: AppType.title,
        contentTextStyle: TextStyle(
          fontSize: 15,
          height: 1.5,
          color: AppColors.textSecondary,
          fontFamilyFallback: AppType.sansFallback,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: AppColors.bgSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
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
          ProgressIndicatorThemeData(color: AppColors.amber),
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
