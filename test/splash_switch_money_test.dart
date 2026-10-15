import 'dart:io';

import 'package:fincept_app/core/storage/hive_setup.dart';
import 'package:fincept_app/core/topic/topic_pack.dart';
import 'package:fincept_app/core/topic/topic_picker_screen.dart';
import 'package:fincept_app/core/topic/topic_registry.dart';
import 'package:fincept_app/core/topic/topic_state.dart';
import 'package:fincept_app/screens/discover/discover_screen.dart';
import 'package:fincept_app/screens/hub/hub_state.dart';
import 'package:fincept_app/screens/settings/settings_screen.dart';
import 'package:fincept_app/screens/splash/splash_backdrop.dart';
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
      // 首屏改成兴趣圈之后，「我的」等页面会读它（是否在圈内）。
      ChangeNotifierProvider(create: (_) => HubState()),
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
    SplashBackdropPainter painter(WidgetTester tester) => tester
        .widget<CustomPaint>(find.byKey(const Key('splash-backdrop')))
        .painter! as SplashBackdropPainter;
    double opacityOf(WidgetTester tester, Finder f) => tester
        .widget<Opacity>(
            find.ancestor(of: f, matching: find.byType(Opacity)).first)
        .opacity;
    Widget splash({
        int minMs = 1200,
        int maxMs = 3000,
        VoidCallback? onDone,
      }) =>
        SplashScreen(
          onDone: onDone ?? () {},
          minDuration: Duration(milliseconds: minMs),
          maxWait: Duration(milliseconds: maxMs),
        );

    testWidgets('无图标：第一帧只有中性渐变（= 原生启动屏），随后题字 + 口号入场，停够时间后收工',
        (tester) async {
      _phone(tester);
      final topics = TopicState(packs: builtInTopicPacks(fishing: true));
      var done = 0;
      await tester.pumpWidget(_host(topics, splash(onDone: () => done++)));

      // 没有任何图片 / 品牌标。
      expect(find.byType(Image), findsNothing);
      expect(find.byKey(const Key('splash-mark')), findsNothing);
      // 第一帧：中性渐变，星光 / 细线 / 辉光都还没出现，题字透明。
      final first = painter(tester);
      expect(first.palette.stops, SplashPalette.neutral.stops);
      expect(first.stars, 0);
      expect(first.lines, 0);
      expect(first.ambient, 0);
      expect(opacityOf(tester, find.text('喜爱')), lessThan(0.01));
      expect(opacityOf(tester, find.text('喜爱，并不是一定要得到')), lessThan(0.01));
      // 加载文字已换成发丝线。
      expect(find.textContaining('正在'), findsNothing);
      expect(find.byKey(const Key('splash-progress')), findsOneWidget);
      expect(find.textContaining('证伪'), findsNothing);

      await tester.pump(const Duration(milliseconds: 1500));
      final end = painter(tester);
      expect(end.palette.stops, SplashPalette.money.stops);
      expect(end.stars, 1);
      expect(end.lines, 1);
      expect(opacityOf(tester, find.text('喜爱')), closeTo(1, 0.001));
      expect(opacityOf(tester, find.text('喜爱，并不是一定要得到')), closeTo(1, 0.001));
      // 题字落在屏高 43% 附近（略高于正中）。
      expect(tester.getCenter(find.text('喜爱')).dy, closeTo(844 * 0.43, 24));
      // 星光在闪：时钟还在走。
      await tester.pump(const Duration(milliseconds: 200));
      expect(painter(tester).clock, greaterThan(end.clock));

      expect(done, 0);
      await tester.pump(const Duration(seconds: 3));
      expect(done, 1);
    });

    testWidgets('色组随主题：喜爱钓鱼 = 湖青到黎明；还没选主题 = 中性夜色', (tester) async {
      _phone(tester);
      final fishing = TopicState(packs: builtInTopicPacks(fishing: true))
        ..debugSet('fishing');
      await tester.pumpWidget(_host(fishing, splash()));
      await tester.pump(const Duration(milliseconds: 1500));
      expect(painter(tester).palette.stops, SplashPalette.fishing.stops);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 4));

      final fresh = TopicState(packs: builtInTopicPacks(fishing: true))
        ..debugSet('money', needsPick: true);
      await tester.pumpWidget(_host(fresh, splash()));
      await tester.pump(const Duration(milliseconds: 1500));
      expect(painter(tester).palette.stops, SplashPalette.neutral.stops);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('最短停留很短时动效按比例压缩，仍能放完', (tester) async {
      _phone(tester);
      final topics = TopicState(packs: builtInTopicPacks(fishing: true));
      await tester.pumpWidget(_host(topics, splash(minMs: 100, maxMs: 500)));
      await tester.pump(const Duration(milliseconds: 90));
      expect(opacityOf(tester, find.text('喜爱，并不是一定要得到')), closeTo(1, 0.001));
      expect(painter(tester).lines, 1);
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('系统减少动态效果：直接最终静帧，不跑动画', (tester) async {
      _phone(tester);
      final topics = TopicState(packs: builtInTopicPacks(fishing: true));
      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(size: Size(390, 844), disableAnimations: true),
        child: _host(topics, splash()),
      ));
      expect(opacityOf(tester, find.text('喜爱')), 1);
      final p = painter(tester);
      expect(p.stars, 1);
      expect(p.palette.stops, SplashPalette.money.stops);
      expect(tester.hasRunningAnimations, isFalse);
      await tester.pump(const Duration(milliseconds: 500));
      expect(painter(tester).clock, p.clock);
      await tester.pump(const Duration(seconds: 4));
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
      expect(find.text('喜爱，并不是一定要得到'), findsOneWidget);
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
      expect(find.text('喜爱 · 喜爱，并不是一定要得到'), findsOneWidget);
      expect(find.textContaining('证伪'), findsNothing);
    });
  });
}
