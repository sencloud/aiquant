import 'dart:io';

import 'package:fincept_app/models/chat.dart';
import 'package:fincept_app/screens/assistant/assistant_screen.dart';
import 'package:fincept_app/services/market_briefing.dart';
import 'package:fincept_app/state/auth_state.dart';
import 'package:fincept_app/state/chat_state.dart';
import 'package:fincept_app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// 不走网络的快捷提问源。
class _FakeBriefing extends MarketBriefingService {
  @override
  Future<List<String>> loadSuggestions() async => const [];
}

const _answer = '''先说结论：**棕榈油短期偏强震荡，产地减产预期仍在，但高库存压着上方空间。**

### 一、基本面
- **产量**：马来西亚 9 月产量环比下降约 4%，季节性减产开始兑现。
- **出口**：船调机构数据显示 10 月上旬出口环比增加，印度补库需求回暖。
- **库存**：马棕库存仍处于近三年同期高位，限制上涨弹性。

### 二、盘面
P2601 主力合约近 5 个交易日上涨 2.3%，持仓增加，资金偏多；
但 9000 元/吨上方有明显压力，追高性价比一般。

### 三、天气
ENSO 指数目前处于中性区间，短期内没有强厄尔尼诺信号，对明年产量的扰动有限。

### 四、操作思路
回调到 8600–8700 一带再考虑偏多，止损放在前低下方；
如果放量突破 9000，可以小仓位跟随。以上仅供参考，不构成投资建议。

需要我把豆油、菜油和棕榈油的价差也一起整理给你吗？''';

ChatSession _fixtureSession() {
  final s = ChatSession(id: 'fixture', title: '棕榈油短期怎么看');
  s.messages.addAll([
    ChatMessage(role: 'user', content: '棕榈油短期怎么看？顺便看下产区天气'),
    ChatMessage(
      role: 'assistant',
      content: _answer,
      toolCalls: [
        ToolCall(id: 'c1', name: 'get_dominant_contract', argumentsJson: '{}'),
        ToolCall(id: 'c2', name: 'get_cn_news', argumentsJson: '{}'),
      ],
      suggestions: const [
        '豆油、菜油和棕榈油的价差现在处于什么水平？',
        '马来西亚棕榈油库存什么时候可能见顶？',
        '如果拉尼娜出现，对棕榈油有什么影响？',
      ],
      feedback: 1,
    ),
    ChatMessage(
      role: 'tool',
      toolCallId: 'c1',
      name: 'get_dominant_contract',
      content: '{"ts_code":"P2601.DCE"}',
    ),
    ChatMessage(
      role: 'tool',
      toolCallId: 'c2',
      name: 'get_cn_news',
      content: '{"items":['
          '{"title":"马棕9月产量环比下降","url":"https://example.com/a","source":"财联社"},'
          '{"title":"印度10月棕榈油进口预期回升","url":"https://example.com/b","source":"东方财富"},'
          '{"title":"ENSO 指数维持中性","url":"https://example.com/c","source":"华尔街见闻"}'
          ']}',
    ),
  ]);
  return s;
}

Widget _app(ChatState chat, {String? fontFamily}) {
  var theme = AppTheme.build(ThemeMode.light);
  if (fontFamily != null) {
    theme = theme.copyWith(
      textTheme: theme.textTheme.apply(fontFamily: fontFamily),
      primaryTextTheme: theme.primaryTextTheme.apply(fontFamily: fontFamily),
    );
  }
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => AuthState()),
      ChangeNotifierProvider.value(value: chat),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      // 外层再套一层 Scaffold，模拟 HomeScreen：以前「对话记录」按钮正是
      // 因为 Scaffold.of 找到了这一层（没有 drawer）而点了没反应。
      home: Scaffold(body: AssistantScreen(briefing: _FakeBriefing())),
    ),
  );
}

ChatState _seeded() => ChatState()
  ..debugSeed([
    _fixtureSession(),
    ChatSession(id: 'older', title: '沪深300 下周走势'),
  ], activeId: 'fixture');

/// 截图字体：STRATEGY_FONT_DIR 下的 *.otf / *.ttf（与策略页截图同一约定）。
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

/// 进入会话时有两次延迟贴底（180ms / 420ms 的 Future.delayed），
/// pumpAndSettle 不会推进没有帧的定时器，这里手动走完。
Future<void> _settle(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost'));

  testWidgets('对话页：去掉定时任务 / 带上我的组合，回答下有操作栏和推荐追问',
      (tester) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(_seeded()));
    await _settle(tester);

    expect(find.text('定时任务'), findsNothing);
    expect(find.text('带上我的组合'), findsNothing);
    expect(find.byTooltip('加入定时任务'), findsNothing);
    expect(find.byTooltip('新建对话'), findsOneWidget);

    for (final t in ['重新生成', '复制', '有帮助', '没帮助', '分享']) {
      expect(find.byTooltip(t), findsOneWidget, reason: t);
    }
    expect(find.text('3 个来源'), findsOneWidget);
    expect(find.text('马来西亚棕榈油库存什么时候可能见顶？'), findsOneWidget);

    await tester.tap(find.text('3 个来源'));
    await tester.pumpAndSettle();
    expect(find.text('印度10月棕榈油进口预期回升'), findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(BottomSheet), matching: find.text('get_cn_news')),
        findsOneWidget);
  });

  testWidgets('左上角「对话记录」能打开抽屉并切换会话', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final chat = _seeded();
    await tester.pumpWidget(_app(chat));
    await _settle(tester);

    await tester.tap(find.byTooltip('对话记录'));
    await tester.pumpAndSettle();
    expect(find.text('对话记录'), findsOneWidget);
    expect(find.text('沪深300 下周走势'), findsOneWidget);

    await tester.tap(find.text('沪深300 下周走势'));
    await tester.pumpAndSettle();
    expect(chat.activeId, 'older');
  });

  testWidgets('推荐追问只跟着最新一条回答', (tester) async {
    tester.view.physicalSize = const Size(390, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final s = _fixtureSession();
    s.messages.addAll([
      ChatMessage(role: 'user', content: '再说说豆油'),
      ChatMessage(role: 'assistant', content: '豆油跟随美豆偏弱。'),
    ]);
    final chat = ChatState()..debugSeed([s]);
    await tester.pumpWidget(_app(chat));
    await _settle(tester);

    // 旧回答的追问不再展示；重新生成只在最新回答上。
    expect(find.text('马来西亚棕榈油库存什么时候可能见顶？'), findsNothing);
    expect(find.byTooltip('重新生成'), findsOneWidget);
    expect(find.byTooltip('复制'), findsNWidgets(2));
  });

  // 只在显式要求时生成截图（字体渲染因平台而异，不做回归比对）：
  //   CHAT_SCREENSHOT=1 STRATEGY_FONT_DIR=/path/to/fonts flutter test --update-goldens test/assistant_screen_test.dart
  testWidgets('对话页截图', (tester) async {
    await _loadFonts();
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(_seeded(), fontFamily: 'ScreenshotSans'));
    await tester.pumpAndSettle();
    // 回答较长，进入会话自动贴底：此时正文已滚到顶栏下面，顶栏是毛玻璃。
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/chat_screen.png'),
    );
  }, skip: !Platform.environment.containsKey('CHAT_SCREENSHOT'));
}
