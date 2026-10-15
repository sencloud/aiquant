import 'dart:io';

import 'package:fincept_app/core/storage/hive_setup.dart';
import 'package:fincept_app/core/topic/topic_registry.dart';
import 'package:fincept_app/core/topic/topic_state.dart';
import 'package:fincept_app/screens/hub/hub_shell.dart';
import 'package:fincept_app/screens/hub/hub_state.dart';
import 'package:fincept_app/social/social_state.dart';
import 'package:fincept_app/state/auth_state.dart';
import 'package:fincept_app/state/billing_state.dart';
import 'package:fincept_app/state/chat_state.dart';
import 'package:fincept_app/state/settings_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

/// 新社交外壳：四个页签 + 「今天」照实写空 + 七条规矩能打开。
void main() {
  late TopicState topics;
  late SocialState social;

  setUpAll(() async {
    FlutterSecureStorage.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
        appName: 'x',
        packageName: 'x',
        version: '1.0.0',
        buildNumber: '1',
        buildSignature: '');
    dotenv.testLoad(fileInput: 'API_BASE_URL=http://127.0.0.1:9');
    final dir = await Directory.systemTemp.createTemp('hive_social');
    Hive.init(dir.path);
    await registerHiveAdapters();
    await openAppBoxes();
  });

  setUp(() async {
    await prefsBox.clear();
    await chatSessionsBox.clear();
    topics = TopicState(packs: builtInTopicPacks(fishing: true));
    await topics.bootstrap(hasLocalAccount: () async => true);
    social = SocialState(store: MemorySocialStore());
  });

  Widget host() => MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SettingsState()),
          ChangeNotifierProvider(create: (_) => AuthState()),
          ChangeNotifierProvider(create: (_) => BillingState()),
          ChangeNotifierProvider.value(value: topics),
          ChangeNotifierProvider(create: (_) => ChatState()),
          ChangeNotifierProvider(create: (_) => HubState()),
          ChangeNotifierProvider.value(value: social),
        ],
        child: const MaterialApp(home: HubShell()),
      );

  testWidgets('首屏是「今天」，四个页签都在', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host());
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('今天'), findsWidgets);
    expect(find.text('圈子'), findsWidgets);
    expect(find.text('信箱'), findsWidgets);
    expect(find.text('我的'), findsWidgets);
  });

  testWidgets('今天没有事：照实写空，并给一个三秒能做完的入口', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host());
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('今天还没有事'), findsOneWidget);
    expect(find.byKey(const ValueKey('today-empty')), findsOneWidget);
    expect(find.text('记一件今天的事'), findsOneWidget);
  });

  testWidgets('记一件事之后：事出现在今天，话就有地方落', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host());
    await tester.pump(const Duration(milliseconds: 300));

    social.recordEvent(
      circleId: topics.currentId,
      circleName: topics.current.name,
      circleMark: topics.current.mark,
      title: '登记了一条渔获：翘嘴 42cm',
      facts: ['水温 24℃'],
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('今天，圈里有一件事'), findsOneWidget);
    expect(find.text('登记了一条渔获：翘嘴 42cm'), findsWidgets);
    expect(find.text('说一句'), findsWidgets);
    expect(find.text('今天还没有事'), findsNothing);
  });

  testWidgets('说一句：没有由头就没有入口，页面会解释为什么', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host());
    await tester.pump(const Duration(milliseconds: 300));

    social.recordEvent(
      circleId: topics.currentId,
      circleName: topics.current.name,
      circleMark: topics.current.mark,
      title: '登记了一条渔获：翘嘴 42cm',
    );
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('说一句').first);
    await tester.pumpAndSettle();

    expect(find.text('这句话挂在什么上？'), findsOneWidget);
    // 没有由头的那张卡是禁用并解释的。
    expect(find.text('没有由头'), findsOneWidget);
    expect(find.textContaining('这里没有「在吗」'), findsOneWidget);
    // 有由头就能发。
    await tester.enterText(find.byKey(const ValueKey('speak-text')), '你用多重的铅？');
    await tester.tap(find.text('投出去'));
    await tester.pumpAndSettle();
    expect(social.posts.length, 1);
    expect(social.posts.single.target.kind.name, 'event');
  });

  testWidgets('这里的规矩：七条都在', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host());
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byKey(const ValueKey('today-rules')));
    await tester.pumpAndSettle();

    expect(find.text('这里的规矩'), findsWidgets);
    expect(find.text('今晚不在'), findsOneWidget);
    expect(find.textContaining('不读你的通讯录'), findsOneWidget);
    expect(find.textContaining('这里没有「在吗」'), findsOneWidget);
    expect(find.textContaining('他也得先送东西'), findsWidgets);
  });
}
