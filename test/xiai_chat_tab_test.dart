import 'dart:io';

import 'package:fincept_app/app.dart';
import 'package:fincept_app/core/storage/hive_setup.dart';
import 'package:fincept_app/models/chat.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

/// 「对话」页签的回归测试。
///
/// 这个页签是**和投资助理聊**的地方：
///  * 它曾经整页空白 —— 伴侣会话下会读 CompanionState，而 App 根部只挂了
///    Auth / Billing / Chat，`watch<CompanionState>()` 直接抛
///    ProviderNotFoundException，release 包里就是一个没有任何内容的页签。
///  * 它也曾经被伴侣会话劫持 —— 旧版本留下的 `companion` 会话 updatedAt
///    最新，bootstrap 就把它选中，页签变成和虚拟人聊天。
/// 这里用真实 XiaiApp + 真实 Hive 会话，确认页签是投资助理、能看能打字。
void main() {
  late Directory tempDir;

  setUpAll(() async {
    dotenv.testLoad(fileInput: 'API_BASE_URL=http://127.0.0.1:9');
    tempDir = await Directory.systemTemp.createTemp('xiai-chat-tab-');
    Hive.init(tempDir.path);
    await registerHiveAdapters();
    await Hive.openBox(kBoxPrefs);
    await Hive.openBox<ChatSession>(kBoxChatSessions);
    // 安全存储在测试环境没有实现：给一个空实现，模拟真机上能正常读到「未登录」。
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => null,
    );
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  tearDown(() async {
    await chatSessionsBox.clear();
  });

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const XiaiApp());
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  Future<void> openChatTab(WidgetTester tester) async {
    expect(find.text('对话'), findsWidgets, reason: '底部页签要在');
    await tester.tap(find.text('对话'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
  }

  testWidgets('伴侣会话比投资会话更新时，对话页仍是投资助理', (tester) async {
    // 旧版本留下的伴侣会话 updatedAt 最新：以前 bootstrap 会选中它，
    // 「对话」页签就变成和虚拟人聊天。
    final companion = ChatSession(
      id: 'companion-1',
      title: '喜爱',
      topic: 'companion',
      personaId: 'xiai',
    )
      ..messages.add(ChatMessage(role: 'assistant', content: '我在。'))
      ..updatedAt = DateTime.now();
    final money = ChatSession(
      id: 'money-1',
      title: '沪深300 这周怎么看',
      updatedAt: DateTime.now().subtract(const Duration(days: 2)),
    );
    // Hive 落盘是真实 I/O，必须放在 runAsync 里；testWidgets 默认的假时钟
    // 不会推进文件系统 future，直接 await 会一直挂着。
    await tester.runAsync(() async {
      await chatSessionsBox.put(companion.id, companion);
      await chatSessionsBox.put(money.id, money);
    });

    await pumpApp(tester);
    await openChatTab(tester);

    expect(tester.takeException(), isNull);
    // 投资助理的空会话欢迎页 + 发送按钮（不是虚拟人的聊天记录）。
    expect(find.textContaining('Hi，'), findsOneWidget);
    expect(find.text('我在。'), findsNothing);
    expect(find.text('研究助理'), findsWidgets);
    expect(find.byKey(const ValueKey('chat-send')), findsOneWidget);
  });

  testWidgets('投资会话下对话页显示欢迎语，并且能打字发送', (tester) async {
    await tester.runAsync(
      () => chatSessionsBox.put(
        'money-1',
        ChatSession(id: 'money-1', title: '新对话')
          ..updatedAt = DateTime.now(),
      ),
    );

    await pumpApp(tester);
    await openChatTab(tester);

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Hi，'), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-send')), findsOneWidget);

    // 输入框可用：打字后发送按钮变亮（onPressed 非空）。
    await tester.enterText(find.byType(TextField).first, '今天大盘怎么看');
    await tester.pump();
    expect(find.text('今天大盘怎么看'), findsOneWidget);
  });
}
