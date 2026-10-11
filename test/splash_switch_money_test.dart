import 'dart:io';

import 'package:fincept_app/core/storage/hive_setup.dart';
import 'package:fincept_app/core/topic/topic_pack.dart';
import 'package:fincept_app/core/topic/topic_picker_screen.dart';
import 'package:fincept_app/core/topic/topic_registry.dart';
import 'package:fincept_app/core/topic/topic_state.dart';
import 'package:fincept_app/screens/discover/discover_screen.dart';
import 'package:fincept_app/screens/settings/settings_screen.dart';
import 'package:fincept_app/screens/splash/splash_screen.dart';
import 'package:fincept_app/state/auth_state.dart';
import 'package:fincept_app/state/billing_state.dart';
import 'package:fincept_app/state/chat_state.dart';
import 'package:fincept_app/state/settings_state.dart';
import 'package:fincept_app/theme/app_theme.dart';
import 'package:fincept_app/topics/money/money_pack.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

Widget _host(TopicState topics, Widget home) {
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
        theme: AppTheme.build(ThemeMode.light, palette: pack.palette),
        home: home,
      ),
    ),
  );
}

/// 点「切换主题」/ 主题卡会写 Hive（dismissBanner / switchTo）。Hive 写入
/// 必须在真实 zone 里发起：在假时钟 zone 里发起的写入，测试结束后永远等不到
/// 完成，Hive 的写队列会卡死下一个测试。
Future<void> _tapReal(WidgetTester tester, Finder f) =>
    tester.runAsync(() async {
      await tester.tap(f);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });

/// 「我的」页有常驻动画（余额加载圈），不能 pumpAndSettle。
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  setUpAll(() async {
    FlutterSecureStorage.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
        appName: 'x',
        packageName: 'x',
        version: '1.0.0',
        buildNumber: '1',
        buildSignature: '');
    dotenv.testLoad(fileInput: 'API_BASE_URL=http://127.0.0.1:9');
    final dir = await Directory.systemTemp.createTemp('hive_splash');
    Hive.init(dir.path);
    await registerHiveAdapters();
    await openAppBoxes();
  });
  setUp(() async => prefsBox.clear());
  tearDown(() => AppColors.applyTopic(TopicPalette.money));

  group('开屏', () {
    testWidgets('品牌标居中（与原生启动屏同位）+ 喜爱 + 口号，停够时间后收工', (tester) async {
      _phone(tester);
      final topics = TopicState(packs: builtInTopicPacks(fishing: true));
      var done = 0;
      await tester.pumpWidget(_host(
        topics,
        SplashScreen(
          onDone: () => done++,
          minDuration: const Duration(milliseconds: 1200),
          maxWait: const Duration(milliseconds: 3000),
        ),
      ));

      // 第一帧：品牌标已经在整屏正中、尺寸 152（= 原生 LaunchImage 152pt）。
      final mark = find.byKey(const Key('splash-mark'));
      expect(mark, findsOneWidget);
      expect(tester.getSize(mark), const Size(152, 152));
      expect(tester.getCenter(mark), const Offset(195, 422));
      expect(find.text('喜爱'), findsOneWidget);
      expect(find.text('喜爱什么，就有什么'), findsOneWidget);
      // 旧文案不再出现。
      expect(find.textContaining('证伪'), findsNothing);

      // 题字从透明淡入。
      double opacityOf(Finder f) => tester
          .widget<FadeTransition>(
              find.ancestor(of: f, matching: find.byType(FadeTransition)).first)
          .opacity
          .value;
      expect(opacityOf(find.text('喜爱什么，就有什么')), lessThan(0.05));
      await tester.pump(const Duration(milliseconds: 800));
      expect(opacityOf(find.text('喜爱什么，就有什么')), closeTo(1, 0.001));
      // 动效期间品牌标不动。
      expect(tester.getCenter(mark), const Offset(195, 422));

      expect(done, 0);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 3000));
      expect(done, 1);
    });

    testWidgets('最短停留很短时动效按比例压缩，仍能放完', (tester) async {
      _phone(tester);
      final topics = TopicState(packs: builtInTopicPacks(fishing: true));
      await tester.pumpWidget(_host(
        topics,
        SplashScreen(
          onDone: () {},
          minDuration: const Duration(milliseconds: 100),
          maxWait: const Duration(milliseconds: 500),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 90));
      final fade = tester.widget<FadeTransition>(find
          .ancestor(
              of: find.text('喜爱什么，就有什么'), matching: find.byType(FadeTransition))
          .first);
      expect(fade.opacity.value, closeTo(1, 0.001));
      await tester.pump(const Duration(seconds: 1));
    });
  });

  group('我的 → 切换主题', () {
    Future<TopicState> boot(WidgetTester tester) async {
      final topics = TopicState(packs: builtInTopicPacks(fishing: true));
      await tester
          .runAsync(() => topics.bootstrap(hasLocalAccount: () async => true));
      return topics;
    }

    testWidgets('打开的是首启同一个选主题页：当前主题打勾、可关闭', (tester) async {
      _phone(tester);
      final topics = await boot(tester);
      expect(topics.currentId, 'money');
      await tester.pumpWidget(_host(topics, const SettingsScreen()));
      await tester.pump(const Duration(milliseconds: 300));

      await _tapReal(
          tester, find.byKey(const ValueKey('settings-switch-topic')));
      await _settle(tester);
      expect(find.byType(TopicPickerScreen), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      final picker =
          tester.widget<TopicPickerScreen>(find.byType(TopicPickerScreen));
      expect(picker.switching, isTrue);
      // 与首启同一套版式：喜爱 + 口号 + 两张主题卡。
      expect(find.text('喜爱什么，就有什么'), findsOneWidget);
      expect(find.byKey(const ValueKey('topic-card-money')), findsOneWidget);
      expect(find.byKey(const ValueKey('topic-card-fishing')), findsOneWidget);
      final money = tester.widget<TopicCard>(find.ancestor(
          of: find.byKey(const ValueKey('topic-card-money')),
          matching: find.byType(TopicCard)));
      final fishing = tester.widget<TopicCard>(find.ancestor(
          of: find.byKey(const ValueKey('topic-card-fishing')),
          matching: find.byType(TopicCard)));
      expect(money.selected, isTrue);
      expect(fishing.selected, isFalse);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);

      // 关闭：不切换。
      await tester.tap(find.byKey(const Key('topic-picker-close')));
      await _settle(tester);
      expect(find.byType(TopicPickerScreen), findsNothing);
      expect(topics.currentId, 'money');
    });

    testWidgets('点另一个主题：关掉选择页并切换', (tester) async {
      _phone(tester);
      final topics = await boot(tester);
      await tester.pumpWidget(_host(topics, const SettingsScreen()));
      await tester.pump(const Duration(milliseconds: 300));
      await _tapReal(
          tester, find.byKey(const ValueKey('settings-switch-topic')));
      await _settle(tester);
      await _tapReal(tester, find.byKey(const ValueKey('topic-card-fishing')));
      await _settle(tester);
      expect(find.byType(TopicPickerScreen), findsNothing);
      expect(topics.currentId, 'fishing');
    });

    testWidgets('首启选择页没有关闭按钮、不打勾', (tester) async {
      _phone(tester);
      final topics = TopicState(packs: builtInTopicPacks(fishing: true));
      await tester.pumpWidget(_host(topics, const TopicPickerScreen()));
      expect(find.byKey(const Key('topic-picker-close')), findsNothing);
      expect(find.byIcon(Icons.check_circle_rounded), findsNothing);
      expect(find.text('先选一个你喜爱的'), findsOneWidget);
    });
  });

  group('喜爱钱下线项', () {
    test('页签只剩 对话 / 发现 / 我的', () {
      expect(const MoneyPack().tabs.map((t) => t.key).toList(),
          ['chat', 'discover', 'me']);
    });

    testWidgets('发现里没有组合管理；我的里没有我的自选；文案不再提证伪台', (tester) async {
      _phone(tester);
      final topics = TopicState(packs: builtInTopicPacks(fishing: false));
      await tester.pumpWidget(_host(topics, const DiscoverScreen()));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('定时提醒'), findsOneWidget);
      expect(find.text('组合管理'), findsNothing);
      expect(find.textContaining('证伪'), findsNothing);

      await tester.pumpWidget(_host(topics, const SettingsScreen()));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('我的自选'), findsNothing);
      expect(find.text('喜点明细'), findsOneWidget);
      await tester.scrollUntilVisible(find.textContaining('喜爱 · '), 200,
          scrollable: find.byType(Scrollable).first);
      expect(find.text('喜爱 · 喜爱什么，就有什么'), findsOneWidget);
      expect(find.textContaining('证伪'), findsNothing);
    });
  });
}
