import 'dart:io';

import 'package:fincept_app/app.dart';
import 'package:fincept_app/core/storage/hive_setup.dart';
import 'package:fincept_app/core/topic/topic_picker_screen.dart';
import 'package:fincept_app/core/topic/topic_registry.dart';
import 'package:fincept_app/core/topic/topic_state.dart';
import 'package:fincept_app/models/chat.dart';
import 'package:fincept_app/screens/hub/hub_state.dart';
import 'package:fincept_app/social/social_state.dart';
import 'package:fincept_app/state/auth_state.dart';
import 'package:fincept_app/state/billing_state.dart';
import 'package:fincept_app/state/chat_state.dart';
import 'package:fincept_app/state/ding_state.dart';
import 'package:fincept_app/state/settings_state.dart';
import 'package:fincept_app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

/// 主题化之前的 ChatSession 写法（9 个字段，没有 topic）——用来造「老数据」。
class _LegacyChatSessionAdapter extends TypeAdapter<ChatSession> {
  @override
  final int typeId = 4;

  @override
  ChatSession read(BinaryReader reader) => throw UnimplementedError();

  @override
  void write(BinaryWriter writer, ChatSession obj) {
    writer
      ..writeByte(9)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.createdAt)
      ..writeByte(3)
      ..write(obj.updatedAt)
      ..writeByte(4)
      ..write(obj.model)
      ..writeByte(5)
      ..write(obj.deepMode)
      ..writeByte(6)
      ..write(obj.messages)
      ..writeByte(7)
      ..write(obj.personaId)
      ..writeByte(8)
      ..write(obj.toolsEnabled);
  }
}

Future<void> _clearBoxes() async {
  await prefsBox.clear();
  await chatSessionsBox.clear();
  await portfoliosBox.clear();
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
    final dir = await Directory.systemTemp.createTemp('hive_topic');
    Hive.init(dir.path);
    await registerHiveAdapters();
    await openAppBoxes();
  });

  setUp(_clearBoxes);
  tearDown(() => AppColors.applyTopic(TopicPalette.money));

  group('TopicState', () {
    test('全新安装 + 多主题：要求先选主题', () async {
      final t = TopicState(packs: builtInTopicPacks(fishing: true));
      await t.bootstrap(hasLocalAccount: () async => false);
      expect(t.needsPick, isTrue);
      expect(t.currentId, 'money');
      expect(t.showNewTopicBanner, isFalse);
    });

    test('老用户（本地有会话）：默认喜爱钱，不弹选择页，显示一次新主题提示', () async {
      await chatSessionsBox.put('old', ChatSession(id: 'old'));
      final t = TopicState(packs: builtInTopicPacks(fishing: true));
      await t.bootstrap(hasLocalAccount: () async => false);
      expect(t.needsPick, isFalse);
      expect(t.currentId, 'money');
      expect(t.showNewTopicBanner, isTrue);
      t.dismissBanner();
      expect(t.showNewTopicBanner, isFalse);

      // 再启动：仍是喜爱钱，提示条不再出现。
      final t2 = TopicState(packs: builtInTopicPacks(fishing: true));
      await t2.bootstrap();
      expect(t2.needsPick, isFalse);
      expect(t2.showNewTopicBanner, isFalse);
    });

    test('老用户（只有登录 token）也算老用户', () async {
      final t = TopicState(packs: builtInTopicPacks(fishing: true));
      await t.bootstrap(hasLocalAccount: () async => true);
      expect(t.needsPick, isFalse);
    });

    test('只有一个主题（钓鱼与兴趣圈开关都关闭）：永不弹选择页、不能切换', () async {
      final t = TopicState(
          packs: builtInTopicPacks(fishing: false, circles: false));
      await t.bootstrap(hasLocalAccount: () async => false);
      expect(t.needsPick, isFalse);
      expect(t.canSwitch, isFalse);
    });

    test('选择 / 切换主题：持久化、换色、回调同步', () async {
      final synced = <String>[];
      final t = TopicState(
          packs: builtInTopicPacks(fishing: true), onSwitched: synced.add);
      await t.bootstrap(hasLocalAccount: () async => false);
      await t.completePick('fishing');
      expect(t.needsPick, isFalse);
      expect(t.currentId, 'fishing');
      expect(AppColors.amber, TopicPalette.fishing.brand);
      expect(AppColors.bgBase, TopicPalette.fishing.bgBase);
      expect(prefsBox.get(TopicState.kPrefTopicId), 'fishing');
      expect(synced, ['fishing']);

      // 冷启动恢复上次的主题。
      AppColors.applyTopic(TopicPalette.money);
      final t2 = TopicState(packs: builtInTopicPacks(fishing: true));
      await t2.bootstrap();
      expect(t2.currentId, 'fishing');
      expect(t2.needsPick, isFalse);
      expect(AppColors.amber, TopicPalette.fishing.brand);

      await t2.switchTo('money');
      expect(AppColors.amber, TopicPalette.money.brand);
      expect(AppColors.amber, const Color(0xFF9E6322));
    });

    test('登录后与服务端对齐：新登录采用服务端，否则推本机', () async {
      final synced = <String>[];
      final t = TopicState(
          packs: builtInTopicPacks(fishing: true), onSwitched: synced.add);
      await t.bootstrap(hasLocalAccount: () async => true);
      await t.reconcileWithServer(serverTopic: 'fishing', freshLogin: true);
      expect(t.currentId, 'fishing');
      expect(synced, isEmpty, reason: '服务端来的不回推');

      await t.reconcileWithServer(serverTopic: 'money', freshLogin: false);
      expect(t.currentId, 'fishing');
      expect(synced, ['fishing']);

      // 服务端是未知主题（例如新版本加的）：忽略。
      await t.reconcileWithServer(serverTopic: 'golf', freshLogin: true);
      expect(t.currentId, 'fishing');
    });
  });

  group('ChatSession 主题字段', () {
    test('老数据（没有 topic 字段）读出来是 money', () async {
      Hive.registerAdapter(_LegacyChatSessionAdapter(), override: true);
      await chatSessionsBox.put(
          'legacy', ChatSession(id: 'legacy', personaId: 'buffett'));
      await chatSessionsBox.close();
      Hive.registerAdapter(ChatSessionAdapter(), override: true);
      await Hive.openBox<ChatSession>(kBoxChatSessions);
      final s = chatSessionsBox.get('legacy')!;
      expect(s.topic, 'money');
      expect(s.personaId, 'buffett');
    });

    test('新数据往返保留 topic', () async {
      await chatSessionsBox.put(
          'f', ChatSession(id: 'f', topic: 'fishing', personaId: 'lure_coach'));
      await chatSessionsBox.close();
      await Hive.openBox<ChatSession>(kBoxChatSessions);
      expect(chatSessionsBox.get('f')!.topic, 'fishing');
    });
  });

  group('ChatState 按主题过滤', () {
    test('切换主题：会话列表、默认人设跟着换，原主题会话保留', () async {
      await chatSessionsBox.put(
          'm1', ChatSession(id: 'm1', personaId: 'buffett'));
      final chat = ChatState();
      await chat.bootstrap();
      expect(chat.sessions.map((s) => s.id), ['m1']);
      expect(chat.currentPersona.id, 'buffett');

      await chat.setTopic('fishing');
      expect(chat.sessions, hasLength(1));
      expect(chat.active!.topic, 'fishing');
      expect(chat.active!.personaId, 'fishing_buddy');
      expect(chat.currentPersona.id, 'fishing_buddy');

      await chat.setTopic('money');
      expect(chat.sessions.map((s) => s.id), ['m1']);
      expect(chat.active!.id, 'm1');
      expect(chatSessionsBox.length, 2);
    });
  });

  group('主题 UI', () {
    Widget host(TopicState topics, Widget child) => MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => SettingsState()),
            ChangeNotifierProvider(create: (_) => AuthState()),
            ChangeNotifierProvider(create: (_) => BillingState()),
            ChangeNotifierProvider.value(value: topics),
            ChangeNotifierProvider(create: (_) => ChatState()),
            ChangeNotifierProvider(
                create: (_) => SocialState(store: MemorySocialStore())),
          ],
          child: child,
        );

    testWidgets('首启选择页：点喜爱钓鱼即进入钓鱼主题', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final topics = TopicState(packs: builtInTopicPacks(fishing: true));
      await tester.runAsync(
          () => topics.bootstrap(hasLocalAccount: () async => false));
      expect(topics.needsPick, isTrue);
      await tester.pumpWidget(host(
          topics, const MaterialApp(home: TopicPickerScreen())));
      expect(find.text('喜爱钱'), findsOneWidget);
      expect(find.text('喜爱钓鱼'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('topic-card-fishing')));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();
      expect(topics.needsPick, isFalse);
      expect(topics.currentId, 'fishing');
    });

    testWidgets('首屏是「今天」；进圈后页签换掉，喜爱钱私有状态被销毁', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      debugDesktopOverride = false;
      addTearDown(() => debugDesktopOverride = null);
      final topics = TopicState(packs: builtInTopicPacks(fishing: true));
      await tester.runAsync(
          () => topics.bootstrap(hasLocalAccount: () async => true));
      final auth = AuthState()..bootstrap();
      final hub = HubState();
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SettingsState()),
          ChangeNotifierProvider.value(value: auth),
          ChangeNotifierProvider(create: (_) => BillingState()),
          ChangeNotifierProvider.value(value: topics),
          ChangeNotifierProvider(create: (_) => ChatState()),
          ChangeNotifierProvider.value(value: hub),
          ChangeNotifierProvider(
              create: (_) => SocialState(store: MemorySocialStore())),
        ],
        child: const XiaiApp(),
      ));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      // App 首屏 = 「今天」（新社交骨架）：四个页签。
      for (final label in ['今天', '圈子', '信箱', '我的']) {
        expect(find.text(label), findsWidgets, reason: '页签 $label 应该在');
      }
      // 今天没有事 —— 页面照实写空，不生成内容。
      expect(find.text('今天还没有事'), findsOneWidget);
      expect(find.text('发现'), findsNothing);
      // 切到「圈子」页签：一行一个圈，圈内的页签还没出现。
      await tester.tap(find.text('圈子').first);
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(find.text('喜爱钱'), findsOneWidget);
      expect(find.text('喜爱钓鱼'), findsOneWidget);

      // 进喜爱钱。
      hub.enter();
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      // 喜爱钱：对话 / 发现 / 我的（「策略」页签已下线）。
      expect(find.text('发现'), findsWidgets);
      expect(find.text('策略'), findsNothing);
      expect(find.text('出钓'), findsNothing);

      final homeCtx = tester.element(find.text('发现').last);
      final ding = Provider.of<DingState>(homeCtx, listen: false);

      await tester.runAsync(() => topics.switchTo('fishing'));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      // 喜爱钓鱼：对话 / 出钓 / 发现 / 我的（渔获挪进「发现」作为内置小应用）。
      expect(find.text('出钓'), findsOneWidget);
      expect(find.text('发现'), findsOneWidget);
      expect(find.text('渔获'), findsNothing);
      expect(() => ChangeNotifier.debugAssertNotDisposed(ding),
          throwsFlutterError);
      expect(AppColors.amber, TopicPalette.fishing.brand);
      // 钓鱼主题里没有喜爱钱的私有状态。
      final fishCtx = tester.element(find.text('出钓'));
      expect(() => Provider.of<DingState>(fishCtx, listen: false),
          throwsA(isA<ProviderNotFoundException>()));
      expect(topicOf(fishCtx).id, 'fishing');
    });
  });
}
