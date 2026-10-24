import 'package:fincept_app/core/api/auth_models.dart';
import 'package:fincept_app/models/chat.dart';
import 'package:fincept_app/screens/companion/companion_avatar.dart';
import 'package:fincept_app/screens/companion/companion_home.dart';
import 'package:fincept_app/state/auth_state.dart';
import 'package:fincept_app/state/billing_state.dart';
import 'package:fincept_app/state/chat_state.dart';
import 'package:fincept_app/state/companion_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _Authed extends AuthState {
  @override
  bool get isAuthenticated => true;
  @override
  UserPublic? get currentUser => UserPublic(
        uuid: 'u-1',
        nickname: '老周',
        status: 'active',
        creditBalance: 100,
        hasPhone: true,
        hasApple: false,
        createdAt: DateTime(2026),
      );
}

class _QuietBilling extends BillingState {
  @override
  Future<void> refreshAll() async {}
  @override
  Future<void> refreshBalance() async {}
  @override
  Future<int> restoreUnverifiedPurchases() async => 0;
}

void main() {
  setUpAll(() {
    dotenv.testLoad(fileInput: 'API_BASE_URL=http://127.0.0.1:9');
  });

  group('她开口的那句话', () {
    test('开盘前提到盘', () {
      expect(
        CompanionState.openerFor(
            DateTime(2026, 10, 22, 8, 30), const ['炒股', '钓鱼']),
        '早。今天开盘前，想聊两句吗？',
      );
    });

    test('收盘后问今天', () {
      expect(
        CompanionState.openerFor(
            DateTime(2026, 10, 22, 15, 10), const ['期货']),
        '收盘了。今天怎么样？',
      );
    });

    test('周末把钓鱼 / 爬山带上', () {
      expect(
        CompanionState.openerFor(
            DateTime(2026, 10, 24, 10, 0), const ['钓鱼', '爬山']),
        '周末了。想去水边坐坐，还是上山走走？',
      );
      expect(
        CompanionState.openerFor(
            DateTime(2026, 10, 24, 10, 0), const ['钓鱼']),
        '周末了。水边还是老地方？',
      );
    });
  });

  group('她会先开口', () {
    test('空会话不说，交给欢迎页', () async {
      final chat = ChatState(store: MemoryChatSessionStore());
      await chat.bootstrap();
      await chat.newSession(topic: 'companion', personaId: 'xiai', title: '喜爱');
      final c = CompanionState(clock: () => DateTime(2026, 10, 22, 15, 10));
      await c.load();
      expect(await c.maybeSaySomething(chat), isFalse);
    });

    test('隔了一阵、白天，会补一句', () async {
      final chat = ChatState(store: MemoryChatSessionStore());
      await chat.bootstrap();
      final s = await chat
          .newSession(topic: 'companion', personaId: 'xiai', title: '喜爱');
      s.messages.add(ChatMessage(
        role: 'user',
        content: '今天有点累',
        timestamp: DateTime(2026, 10, 22, 9, 0),
      ));
      final c = CompanionState(clock: () => DateTime(2026, 10, 22, 15, 10));
      await c.load();
      expect(await c.maybeSaySomething(chat), isTrue);
      expect(s.messages.last.role, 'assistant');
      expect(s.messages.last.content, '收盘了。今天怎么样？');
    });

    test('深夜不打扰', () async {
      final chat = ChatState(store: MemoryChatSessionStore());
      await chat.bootstrap();
      final s = await chat
          .newSession(topic: 'companion', personaId: 'xiai', title: '喜爱');
      s.messages.add(ChatMessage(
          role: 'user',
          content: '还没睡',
          timestamp: DateTime(2026, 10, 22, 21, 0)));
      final c = CompanionState(clock: () => DateTime(2026, 10, 22, 23, 40));
      await c.load();
      expect(await c.maybeSaySomething(chat), isFalse);
    });
  });

  testWidgets('打开就是喜爱：欢迎、她记得的喜欢、三个开场', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final chat = ChatState(store: MemoryChatSessionStore());
    final companion =
        CompanionState(clock: () => DateTime(2026, 10, 22, 9, 0));
    await companion.load();
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthState>(create: (_) => _Authed()),
        ChangeNotifierProvider<BillingState>(create: (_) => _QuietBilling()),
        ChangeNotifierProvider.value(value: chat),
        ChangeNotifierProvider.value(value: companion),
      ],
      child: const MaterialApp(home: CompanionHome()),
    ));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.textContaining('我是喜爱'), findsOneWidget);
    expect(find.textContaining('陪着你，是长情的告白'), findsOneWidget);
    // 标题就是名字，没有 AI 标签。
    expect(find.text('喜爱'), findsOneWidget);
    expect(find.text('AI 伴侣'), findsNothing);
  });

  testWidgets('她记得的喜欢：勾一个咖啡，保存后页面跟着变', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final chat = ChatState(store: MemoryChatSessionStore());
    final companion =
        CompanionState(clock: () => DateTime(2026, 10, 22, 9, 0));
    await companion.load();
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthState>(create: (_) => _Authed()),
        ChangeNotifierProvider<BillingState>(create: (_) => _QuietBilling()),
        ChangeNotifierProvider.value(value: chat),
        ChangeNotifierProvider.value(value: companion),
      ],
      child: const MaterialApp(home: CompanionHome()),
    ));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 600));

    await tester.tap(find.byKey(const ValueKey('chat-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('兴趣设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('interest-咖啡')));
    await tester.tap(find.byKey(const ValueKey('interests-save')));
    await tester.pumpAndSettle();

    expect(companion.interests, contains('咖啡'));
  });

  testWidgets('点她的头像：换一个形象，名字跟着换', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final chat = ChatState(store: MemoryChatSessionStore());
    final companion =
        CompanionState(clock: () => DateTime(2026, 10, 22, 9, 0));
    await companion.load();
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthState>(create: (_) => _Authed()),
        ChangeNotifierProvider<BillingState>(create: (_) => _QuietBilling()),
        ChangeNotifierProvider.value(value: chat),
        ChangeNotifierProvider.value(value: companion),
      ],
      child: const MaterialApp(home: CompanionHome()),
    ));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 600));

    await tester.tap(find.byType(CompanionAvatar).first);
    await tester.pumpAndSettle();
    expect(companion.name, '清禾');
    expect(find.text('清禾'), findsWidgets);
  });
}
