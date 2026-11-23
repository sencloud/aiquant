import 'package:fincept_app/models/chat.dart';
import 'package:fincept_app/services/ai_chat_service.dart';
import 'package:fincept_app/state/chat_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bootstrap 可读取不可变会话列表并按更新时间排序', () async {
    final older = ChatSession(
      id: 'older',
      title: '较早',
      updatedAt: DateTime(2026, 11, 20),
      messages: [ChatMessage(role: 'user', content: '旧消息')],
    );
    final newer = ChatSession(
      id: 'newer',
      title: '较新',
      updatedAt: DateTime(2026, 11, 22),
      messages: [ChatMessage(role: 'user', content: '新消息')],
    );
    final store = _UnmodifiableSessionStore([older, newer]);
    final state = ChatState(service: _SuccessfulChatService(), store: store);

    await state.bootstrap();

    expect(state.sessions.map((session) => session.id), ['newer', 'older']);
    expect(state.activeId, 'newer');
  });

  test('会话不在 Hive 盒中时仍能完成取数、流式回复和落盘', () async {
    final store = _UnmodifiableSessionStore([
      ChatSession(
        id: 'chat-1',
        title: '旧标题',
        messages: [ChatMessage(role: 'user', content: '你好')],
      ),
    ]);
    final service = _SuccessfulChatService();
    final state = ChatState(service: service, store: store);
    await state.bootstrap();

    await state.sendMessage('分析一下今天的行情');

    expect(service.lastMessage, '分析一下今天的行情');
    expect(state.streaming, isFalse);
    expect(state.active?.messages.last.role, 'assistant');
    expect(state.active?.messages.last.content, contains('行情正在震荡'));
    expect(store.saveCount, greaterThanOrEqualTo(2));
  });
  test('bootstrap 优先投资会话：伴侣会话再新也不会被选中', () async {
    final money = ChatSession(
      id: 'money-1',
      title: '沪深300 这周怎么看',
      updatedAt: DateTime(2026, 11, 20),
    );
    final companion = ChatSession(
      id: 'companion-1',
      title: '喜爱',
      topic: 'companion',
      updatedAt: DateTime(2026, 11, 23),
    );
    final state = ChatState(
      service: _SuccessfulChatService(),
      store: _UnmodifiableSessionStore([companion, money]),
    );

    await state.bootstrap();

    expect(state.activeId, 'money-1');
    expect(state.active?.topic, 'money');
    // 历史不删：伴侣会话仍留在列表里，只是不进「对话」页签。
    expect(state.sessions.map((s) => s.id), contains('companion-1'));
  });

  test('只有伴侣会话时 bootstrap 会新建一段投资对话', () async {
    final state = ChatState(
      service: _SuccessfulChatService(),
      store: _UnmodifiableSessionStore([
        ChatSession(id: 'companion-1', title: '喜爱', topic: 'companion'),
      ]),
    );

    await state.bootstrap();

    expect(state.active?.topic, 'money');
    expect(state.sessions.map((s) => s.id), contains('companion-1'));
  });

  test('ensureInvestmentSession 把伴侣会话切回投资会话', () async {
    final state = ChatState(
      service: _SuccessfulChatService(),
      store: _UnmodifiableSessionStore([
        ChatSession(id: 'money-1', title: '投资对话'),
        ChatSession(id: 'companion-1', title: '喜爱', topic: 'companion'),
      ]),
    );
    await state.bootstrap();
    state.selectSession('companion-1');
    expect(state.active?.topic, 'companion');

    final session = await state.ensureInvestmentSession();

    expect(session.id, 'money-1');
    expect(state.activeId, 'money-1');
    expect(state.active?.topic, 'money');
  });
}

class _UnmodifiableSessionStore implements ChatSessionStore {
  _UnmodifiableSessionStore(this._sessions);

  final List<ChatSession> _sessions;
  var saveCount = 0;

  @override
  List<ChatSession> load() => List<ChatSession>.unmodifiable(_sessions);

  @override
  void save(ChatSession session) {
    saveCount++;
  }

  @override
  void remove(String id) {}

  @override
  void clear() {}
}

class _SuccessfulChatService extends AiChatService {
  String? lastMessage;

  @override
  Stream<AiChatEvent> stream({
    String? serverSessionId,
    required String message,
    String? persona,
    String? topic,
    bool deepMode = false,
    String? systemHint,
    List<String>? preferences,
    String? companionName,
    String? companionStyle,
    List<String>? memories,
    Map<String, dynamic>? portfolioContext,
    List<String>? images,
    bool wantSuggestions = false,
  }) async* {
    lastMessage = message;
    yield AiChatEvent(
      kind: AiChatEventKind.session,
      sessionId: 'server-chat-1',
      balance: 100,
    );
    yield AiChatEvent(
      kind: AiChatEventKind.textDelta,
      delta: '行情正在震荡，',
    );
    yield AiChatEvent(
      kind: AiChatEventKind.done,
      sessionId: 'server-chat-1',
      finalText: '行情正在震荡，建议控制节奏。',
      balanceAfter: 95,
    );
  }
}
