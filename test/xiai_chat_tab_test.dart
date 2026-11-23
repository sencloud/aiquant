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
/// 曾经整页空白：对话页在伴侣会话下会读 CompanionState，而 App 根部只挂了
/// Auth / Billing / Chat 三个 Provider，`watch<CompanionState>()` 直接抛
/// ProviderNotFoundException —— release 包里就是一个没有任何内容的页签。
/// 这里用真实 XiaiApp + 真实 Hive 会话，确认点进对话页能看到内容、能发消息。
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

  testWidgets('伴侣会话下对话页不是空白，且能正常打字', (tester) async {
    final session = ChatSession(
      id: 'companion-1',
      title: '喜爱',
      topic: 'companion',
      personaId: 'xiai',
    )
      ..messages.add(ChatMessage(role: 'assistant', content: '我在。'))
      ..updatedAt = DateTime.now();
    // Hive 落盘是真实 I/O，必须放在 runAsync 里；testWidgets 默认的假时钟
    // 不会推进文件系统 future，直接 await 会一直挂着。
    await tester.runAsync(() => chatSessionsBox.put(session.id, session));

    await pumpApp(tester);

    expect(find.text('对话'), findsWidgets, reason: '底部页签要在');
    await tester.tap(find.text('对话'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(tester.takeException(), isNull);
    // 伴侣会话的标题就是她的名字，正文里能看到她说过的话。
    expect(find.text('我在。'), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-send')), findsOneWidget);

    // 输入框可用：打字后发送按钮变成可点状态。
    await tester.enterText(find.byType(TextField).first, '今天怎么样');
    await tester.pump();
    expect(find.text('今天怎么样'), findsOneWidget);
  });

  testWidgets('普通会话下对话页显示欢迎语与快捷提问', (tester) async {
    await tester.runAsync(
      () => chatSessionsBox.put(
        'money-1',
        ChatSession(id: 'money-1', title: '新对话')
          ..updatedAt = DateTime.now(),
      ),
    );

    await pumpApp(tester);
    await tester.tap(find.text('对话'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Hi，'), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-send')), findsOneWidget);
  });
}
