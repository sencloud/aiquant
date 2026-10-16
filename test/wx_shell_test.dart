import 'dart:io';

import 'package:fincept_app/core/api/auth_models.dart';
import 'package:fincept_app/core/storage/hive_setup.dart';
import 'package:fincept_app/models/chat.dart';
import 'package:fincept_app/screens/assistant/assistant_screen.dart';
import 'package:fincept_app/social/social_state.dart';
import 'package:fincept_app/state/auth_state.dart';
import 'package:fincept_app/state/billing_state.dart';
import 'package:fincept_app/state/chat_state.dart';
import 'package:fincept_app/state/ding_state.dart';
import 'package:fincept_app/state/settings_state.dart';
import 'package:fincept_app/wx/wx_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

/// 微信式外壳：消息 / 圈子 / 发现 / 我。
///
/// 钉住这次重构最重要的几条：
///   * 首屏是**会话列表**（聊天是二级页，不是页签）；
///   * 多主题那套没有入口了（选主题页、整屏换色、老的圈子首页都不存在）；
///   * 「圈子」一页装的是六个兴趣圈，进圈是一屋子 AI 助手；
///   * 「今天的事」还照实写空，并能记下第一件事。
class _Authed extends AuthState {
  @override
  bool get isAuthenticated => true;
  @override
  UserPublic? get currentUser => UserPublic(
        uuid: 'u-1',
        nickname: '测试',
        status: 'active',
        creditBalance: 100,
        hasPhone: true,
        hasApple: false,
        createdAt: DateTime(2026),
      );
}

class _QuietBilling extends BillingState {
  @override
  Future<void> refreshBalance() async {}
  @override
  Future<void> refreshAll() async {}
}

class _QuietDing extends DingState {
  @override
  int get unreadCount => 0;
}

void main() {
  late SocialState social;
  late ChatState chat;
  late MemoryChatSessionStore sessionStore;

  setUpAll(() async {
    FlutterSecureStorage.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
        appName: 'x',
        packageName: 'x',
        version: '1.0.0',
        buildNumber: '1',
        buildSignature: '');
    dotenv.testLoad(fileInput: 'API_BASE_URL=http://127.0.0.1:9');
    // prefsBox 会被 ChatState.bootstrap 读一次（服务端会话 id 映射），所以
    // 盒子还是要开；但会话本身走内存实现，测试里不写盘。
    final dir = await Directory.systemTemp.createTemp('hive_wx');
    Hive.init(dir.path);
    await registerHiveAdapters();
    await openAppBoxes();
  });

  setUp(() async {
    social = SocialState(store: MemorySocialStore());
    // 会话落盘走内存实现：不碰 Hive，也就不会在假时钟下把写锁挂住。
    sessionStore = MemoryChatSessionStore();
    chat = ChatState(store: sessionStore);
    final s = ChatSession(id: 's1', title: '棕榈油短期怎么看');
    s.messages.add(ChatMessage(role: 'user', content: '棕榈油短期怎么看？'));
    s.messages.add(ChatMessage(role: 'assistant', content: '短期偏强震荡。'));
    sessionStore.save(s);
    await chat.bootstrap();
  });

  Widget host() => MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SettingsState()),
          ChangeNotifierProvider<AuthState>(create: (_) => _Authed()),
          ChangeNotifierProvider<BillingState>(create: (_) => _QuietBilling()),
          ChangeNotifierProvider<DingState>(create: (_) => _QuietDing()),
          ChangeNotifierProvider.value(value: chat),
          ChangeNotifierProvider<SocialState>.value(value: social),
        ],
        child: const MaterialApp(home: WxShell()),
      );

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  testWidgets('首屏是会话列表，四个页签照微信', (tester) async {
    phone(tester);
    await tester.pumpWidget(host());
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('消息'), findsWidgets);
    expect(find.text('圈子'), findsWidgets);
    expect(find.text('发现'), findsWidgets);
    expect(find.text('我'), findsWidgets);
    // 会话在列表里，预览是最后一条消息。
    expect(find.text('棕榈油短期怎么看'), findsOneWidget);
    expect(find.textContaining('短期偏强震荡'), findsOneWidget);
    // 主题（整屏换色那一套）没有入口了。
    expect(find.text('切换主题'), findsNothing);
    expect(find.text('选一个主题'), findsNothing);
  });

  testWidgets('点会话进聊天页：灰底、气泡、发送按钮都在', (tester) async {
    phone(tester);
    await tester.pumpWidget(host());
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('棕榈油短期怎么看'));
    await tester.pumpAndSettle();

    expect(find.byType(AssistantScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-menu')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-send')), findsOneWidget);
    expect(find.text('短期偏强震荡。'), findsOneWidget);
  });

  testWidgets('圈子：六个圈一行一个，进了圈是一屋助手', (tester) async {
    phone(tester);
    await tester.pumpWidget(host());
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('圈子').last);
    await tester.pumpAndSettle();

    expect(find.text('新的朋友'), findsOneWidget);
    expect(find.text('喜爱钱'), findsOneWidget);
    expect(find.text('喜爱钓鱼'), findsOneWidget);

    await tester.tap(find.text('喜爱钓鱼'));
    await tester.pumpAndSettle();
    expect(find.text('3 位 AI 助手'), findsOneWidget);
    expect(find.text('综合钓友'), findsOneWidget);

    await tester.tap(find.text('综合钓友'));
    await tester.pumpAndSettle();
    expect(find.byType(AssistantScreen), findsOneWidget);
    expect(find.text('综合钓友'), findsWidgets);
    expect(
      sessionStore.load().any((s) => s.topic == 'fishing'),
      isTrue,
      reason: '圈里开的对话带着这个话题',
    );
  });

  testWidgets('发现：今天的事照实写空，记一件就出现', (tester) async {
    phone(tester);
    await tester.pumpWidget(host());
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('发现').last);
    await tester.pumpAndSettle();
    expect(find.text('今天的事'), findsOneWidget);
    expect(find.text('信箱'), findsOneWidget);
    expect(find.text('见面礼'), findsOneWidget);
    expect(find.text('定时提醒'), findsOneWidget);
    expect(find.text('我的小应用'), findsOneWidget);

    await tester.tap(find.text('今天的事'));
    await tester.pumpAndSettle();
    expect(find.text('今天还没有事'), findsOneWidget);
    expect(find.byKey(const ValueKey('today-empty')), findsOneWidget);

    await tester.tap(find.text('记一件今天的事').first);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('event-title')), '今天盘后复盘了一轮');
    await tester.tap(find.text('记下来'));
    await tester.pumpAndSettle();

    expect(find.text('今天记下了一件事'), findsOneWidget);
    expect(find.text('今天盘后复盘了一轮'), findsWidgets);
    expect(find.text('今天还没有事'), findsNothing);
  });

  testWidgets('我：微信式个人页，喜点在账上', (tester) async {
    phone(tester);
    await tester.pumpWidget(host());
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('我').last);
    await tester.pumpAndSettle();

    expect(find.text('测试'), findsWidgets);
    expect(find.text('喜点'), findsOneWidget);
    expect(find.text('喜点明细'), findsOneWidget);
    expect(find.text('邀请好友'), findsOneWidget);
    expect(find.text('退出登录'), findsOneWidget);
  });
}
