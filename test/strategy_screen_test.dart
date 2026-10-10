import 'dart:convert';
import 'dart:io';

import 'package:fincept_app/models/falsification.dart';
import 'package:fincept_app/screens/strategy/strategy_screen.dart';
import 'package:fincept_app/state/auth_state.dart';
import 'package:fincept_app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

FalsificationData _asset() => FalsificationData.fromJson(
    json.decode(File('assets/strategy/falsification.json').readAsStringSync())
        as Map<String, dynamic>);

Widget _app(FalsificationData data, {String? fontFamily}) {
  var theme = AppTheme.build(ThemeMode.light);
  if (fontFamily != null) {
    theme = theme.copyWith(
      textTheme: theme.textTheme.apply(fontFamily: fontFamily),
      primaryTextTheme: theme.primaryTextTheme.apply(fontFamily: fontFamily),
    );
  }
  return ChangeNotifierProvider(
    create: (_) => AuthState(),
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: Scaffold(
        body: StrategyScreen(initialData: data, now: DateTime(2026, 10, 10)),
      ),
    ),
  );
}

/// 给截图加载真实字体：STRATEGY_FONT_DIR 下的 *.otf / *.ttf（单字体文件，
/// 不支持 .ttc）注册到默认字体与中文回落字体名下；没有就用测试默认字体。
Future<void> _loadFonts() async {
  final dir = Platform.environment['STRATEGY_FONT_DIR'];
  final files = dir == null
      ? const <File>[]
      : Directory(dir)
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.otf') || f.path.endsWith('.ttf'))
          .toList();
  if (files.isNotEmpty) {
    for (final family in [
      'ScreenshotSans',
      'Roboto',
      ...AppType.sansFallback,
      ...AppType.readFallback,
      ...AppType.numericFallback,
    ]) {
      final loader = FontLoader(family);
      for (final f in files) {
        loader.addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
      }
      await loader.load();
    }
  }
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot != null) {
    final icons = File(
        '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (icons.existsSync()) {
      final loader = FontLoader('MaterialIcons')
        ..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())));
      await loader.load();
    }
  }
}

void main() {
  setUpAll(() => dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost'));

  testWidgets('通讯录式档案：固定入口、精选、家族分组、索引', (tester) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(_asset()));
    await tester.pump();

    expect(find.text('证伪档案'), findsOneWidget);
    expect(find.text('方法'), findsOneWidget);
    for (final t in ['可交易', '仍在验证', '本周新证伪', '跑一次证伪', '精选档案']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    expect(find.textContaining('趋势跟随 ·'), findsOneWidget);
    expect(find.textContaining('突破 ·'), findsOneWidget);
    // 右侧索引：★ + 各家族首字。
    expect(find.text('★'), findsOneWidget);
    // 样本不足只在搜索里：主列表底部有提示。
    expect(find.textContaining('样本不足，可搜索查看'), findsOneWidget);

    // 可交易为空：说明为什么是空的。
    await tester.tap(find.text('可交易'));
    await tester.pumpAndSettle();
    expect(find.text('暂无可交易策略'), findsOneWidget);
    expect(find.textContaining('这正是证伪的意义'), findsOneWidget);
  });

  testWidgets('搜索能搜到样本不足的条目', (tester) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final data = _asset();
    final insufficient =
        data.archive.firstWhere((e) => e.verdict == 'insufficient');
    await tester.pumpWidget(_app(data));
    await tester.pump();

    await tester.enterText(find.byType(TextField), insufficient.id);
    await tester.pump();
    expect(find.text('搜索结果 · 1 条'), findsOneWidget);
    expect(find.text('样本不足'), findsWidgets);
    expect(find.text('精选档案'), findsNothing);
  });

  // 只在显式要求时生成截图（字体渲染因平台而异，不做回归比对）：
  //   STRATEGY_SCREENSHOT=1 STRATEGY_FONT_DIR=/path/to/fonts flutter test --update-goldens test/strategy_screen_test.dart
  testWidgets('策略页截图', (tester) async {
    await _loadFonts();
    // 390pt 宽的手机，拉长到能一屏看完整个通讯录。
    tester.view.physicalSize = const Size(780, 3400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(_asset(), fontFamily: 'ScreenshotSans'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/strategy_list.png'),
    );
  }, skip: !Platform.environment.containsKey('STRATEGY_SCREENSHOT'));
}
