import 'dart:io';

import 'package:fincept_app/core/storage/hive_setup.dart';
import 'package:fincept_app/miniapp/miniapp_store.dart';
import 'package:fincept_app/screens/home/home_screen.dart';
import 'package:fincept_app/state/auth_state.dart';
import 'package:fincept_app/state/billing_state.dart';
import 'package:fincept_app/state/chat_state.dart';
import 'package:fincept_app/state/settings_state.dart';
import 'package:fincept_app/core/topic/topic_pack.dart';
import 'package:fincept_app/core/topic/topic_registry.dart';
import 'package:fincept_app/core/topic/topic_state.dart';
import 'package:fincept_app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:fincept_app/screens/settings/settings_screen.dart';
import 'package:provider/provider.dart';

import 'miniapp_fakes.dart';

Future<void> _loadFonts() async {
  final dir = Platform.environment['STRATEGY_FONT_DIR'];
  final files = dir == null
      ? const <File>[]
      : Directory(dir)
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.otf') || f.path.endsWith('.ttf'))
          .toList();
  for (final family in [
    'Roboto',
    ...AppType.sansFallback,
    ...AppType.readFallback,
    ...AppType.numericFallback,
  ]) {
    if (files.isEmpty) break;
    final loader = FontLoader(family);
    for (final f in files) {
      loader.addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
    }
    await loader.load();
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

/// 与 app.dart 同构：共享状态在外层，主题包私有状态挂在 MaterialApp 之上。
/// 基线图最初来自主题化之前的 main；2026-10 喜爱钱下线「策略」页签、「组合管理」
/// 与「我的自选」后有意更新过一次（页签变 3 个、「我的」少一行、页脚文案）；
/// 同月「发现」加入小应用（卡片墙 + ＋新建 + 官方模板）后再更新一次。
Widget _app({Widget home = const HomeScreen()}) {
  final topics = TopicState(packs: builtInTopicPacks(fishing: false));
  final TopicPack pack = topics.current;
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => SettingsState()),
      ChangeNotifierProvider(create: (_) => AuthState()),
      ChangeNotifierProvider(create: (_) => BillingState()),
      ChangeNotifierProvider.value(value: topics),
      ChangeNotifierProvider(create: (_) => ChatState()),
    ],
    child: MultiProvider(
      providers: [
        Provider<TopicPack>.value(value: pack),
        ...pack.providers(),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.build(ThemeMode.light, palette: pack.palette),
        home: home,
      ),
    ),
  );
}

void main() {
  setUpAll(() async {
    FlutterSecureStorage.setMockInitialValues({});
    PackageInfo.setMockInitialValues(appName: 'x', packageName: 'x', version: '1.0.0', buildNumber: '1', buildSignature: '');
    dotenv.testLoad(fileInput: 'API_BASE_URL=http://127.0.0.1:9');
    final dir = await Directory.systemTemp.createTemp('hive_golden');
    Hive.init(dir.path);
    await registerHiveAdapters();
    await openAppBoxes();
    // 发现页的小应用区：未登录，只有官方模板（与服务端同一份 JSON）。
    MiniAppStore.api = FakeMiniAppApi();
  });

  testWidgets('喜爱钱主页逐页基线', (tester) async {
    await tester.runAsync(_loadFonts);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app());
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('goldens/money_home_chat.png'));

    // 「策略」页签已下线：底栏只剩 对话 / 发现 / 我的。
    expect(find.text('策略'), findsNothing);
    for (final (label, name) in [
      ('发现', 'discover'),
    ]) {
      await tester.tap(find.text(label).last);
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 2));
      await expectLater(find.byType(MaterialApp),
          matchesGoldenFile('goldens/money_home_$name.png'));
    }
  });

  testWidgets('喜爱钱我的页基线', (tester) async {
    await tester.runAsync(_loadFonts);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(home: const SettingsScreen()));
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('goldens/money_home_settings.png'));
  });
}
