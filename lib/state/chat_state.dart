import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/storage/hive_setup.dart';
import '../models/chat.dart';
import '../models/persona.dart';
import '../services/ai_chat_service.dart';

/// AI 助理客户端状态。
///
/// 与服务端契约：
/// - 唯一 LLM / 工具执行路径：`POST /v1/ai/chat` SSE。
/// - 客户端不再持有 DeepSeek key、Tushare token、FIRMS key；不再本地派发工具。
/// - 会话上下文以服务端 ai_chat_sessions 为准；本地仅缓存 UI 渲染所需的消息列表。
///
/// 客户端 ChatSession 与服务端 session 的映射：
/// - 本地 ChatSession.id 是客户端 UUID（继续作为 Hive box key）。
/// - 服务端首次 emit `session` 事件返回 server session_id，写入 [_serverIdMap]
///   并落地到 prefsBox（key 形如 `ai_chat_server_id:<localId>`）。
/// - 后续发送沿用 server id 让服务端拼齐历史；丢失映射只会让"上下文记忆"重置，
///   不影响本地展示的旧消息。
class ChatState extends ChangeNotifier {
  ChatState({AiChatService? service})
      : _svc = service ?? AiChatService();

  final AiChatService _svc;

  StreamSubscription<AiChatEvent>? _activeStream;

  List<ChatSession> _sessions = const [];
  String? _activeId;
  bool _streaming = false;
  int _totalToolCalls = 0;
  int? _lastBalance;

  final Map<String, String> _serverIdMap = {};

  static const _kServerIdPrefix = 'ai_chat_server_id:';

  List<ChatSession> get sessions => _sessions;
  String? get activeId => _activeId;
  bool get streaming => _streaming;

  /// 累计本轮工具调用次数（顶部 badge 显示用）。仅当前会话有效。
  int get totalTokens => _totalToolCalls;
  int? get lastBalance => _lastBalance;

  /// 最近一次"喜点不足 / 扣费失败"提示。UI 监听后弹一次 dialog 跳充值，
  /// 弹完调 [consumeChargeIssue] 清掉，避免来回弹。
  ChargeIssue? _chargeIssue;
  ChargeIssue? get chargeIssue => _chargeIssue;
  void consumeChargeIssue() {
    if (_chargeIssue == null) return;
    _chargeIssue = null;
    notifyListeners();
  }

  ChatSession? get active =>
      _activeId == null ? null : _byId(_activeId!);
  List<ChatMessage> get messages => active?.messages ?? const [];
  Persona get currentPersona => Personas.byId(active?.personaId);

  Future<void> bootstrap() async {
    _sessions = chatSessionsBox.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    if (_sessions.isEmpty) {
      await newSession();
    } else {
      _activeId = _sessions.first.id;
    }
    for (final s in _sessions) {
      final v = prefsBox.get('$_kServerIdPrefix${s.id}');
      if (v is String && v.isNotEmpty) _serverIdMap[s.id] = v;
    }
    notifyListeners();
  }

  Future<ChatSession> newSession({
    String title = '新对话',
    String? personaId,
  }) async {
    final s = ChatSession(
      title: title,
      personaId: personaId ?? active?.personaId ?? Personas.defaultId,
      toolsEnabled: active?.toolsEnabled ?? true,
    );
    await chatSessionsBox.put(s.id, s);
    _sessions = [s, ..._sessions];
    _activeId = s.id;
    notifyListeners();
    return s;
  }

  Future<void> deleteSession(String id) async {
    await chatSessionsBox.delete(id);
    await prefsBox.delete('$_kServerIdPrefix$id');
    _serverIdMap.remove(id);
    _sessions = _sessions.where((s) => s.id != id).toList();
    if (_activeId == id) {
      _activeId = _sessions.isEmpty ? null : _sessions.first.id;
      if (_activeId == null) await newSession();
    }
    notifyListeners();
  }

  Future<void> renameSession(String id, String title) async {
    final s = _byId(id);
    if (s == null) return;
    s.title = title;
    s.updatedAt = DateTime.now();
    await s.save();
    notifyListeners();
  }

  void selectSession(String id) {
    _activeId = id;
    notifyListeners();
  }

  Future<void> setPersona(String personaId) async {
    final s = active;
    if (s == null) return;
    s.personaId = personaId;
    s.updatedAt = DateTime.now();
    await s.save();
    notifyListeners();
  }

  Future<void> setToolsEnabled(bool on) async {
    final s = active;
    if (s == null) return;
    s.toolsEnabled = on;
    s.updatedAt = DateTime.now();
    await s.save();
    notifyListeners();
  }

  Future<void> abort() async {
    await _activeStream?.cancel();
    _activeStream = null;
    _streaming = false;
    notifyListeners();
  }

  /// 登出 / 切换账号时清空本地缓存的 chat 会话。
  ///
  /// 包含：
  ///  - 取消正在进行的 SSE；
  ///  - 清空 chatSessionsBox（hive）；
  ///  - 清掉 prefsBox 里 `ai_chat_server_id:` 前缀的 server 映射；
  ///  - 清掉内存中 _sessions / _serverIdMap / _activeId / 余额缓存。
  Future<void> reset() async {
    await _activeStream?.cancel();
    _activeStream = null;
    _streaming = false;

    await chatSessionsBox.clear();

    final keys = prefsBox.keys
        .whereType<String>()
        .where((k) => k.startsWith(_kServerIdPrefix))
        .toList();
    for (final k in keys) {
      await prefsBox.delete(k);
    }

    _sessions = const [];
    _serverIdMap.clear();
    _activeId = null;
    _totalToolCalls = 0;
    _lastBalance = null;
    notifyListeners();
  }

  /// 发送一条用户消息并消费服务端 SSE 事件。
  Future<void> sendMessage(String text) async {
    final session = active ?? await newSession();
    if (text.trim().isEmpty || _streaming) return;

    final userMsg = ChatMessage(role: 'user', content: text.trim());
    session.messages.add(userMsg);
    if (session.title == '新对话' || session.title.isEmpty) {
      session.title = _summarizeForTitle(text);
    }
    session.updatedAt = DateTime.now();
    await session.save();

    final assistant = ChatMessage(
      role: 'assistant',
      content: '',
      streaming: true,
    );
    session.messages.add(assistant);

    _streaming = true;
    _totalToolCalls = 0;
    notifyListeners();

    // Persona 的中文人设 prompt 由客户端提供（服务端不感知 persona 库）；
    // chat.Service 会把它拼到默认 system 之后作为"额外指令"。
    final persona = Personas.byId(session.personaId);
    final completer = Completer<void>();
    _activeStream = _svc
        .stream(
      serverSessionId: _serverIdMap[session.id],
      message: text.trim(),
      persona: session.personaId,
      deepMode: session.deepMode,
      systemHint: persona.systemPrompt,
    )
        .listen((ev) async {
      switch (ev.kind) {
        case AiChatEventKind.session:
          if (ev.sessionId != null) {
            _serverIdMap[session.id] = ev.sessionId!;
            await prefsBox.put(
                '$_kServerIdPrefix${session.id}', ev.sessionId);
          }
          if (ev.balance != null) _lastBalance = ev.balance;
          break;
        case AiChatEventKind.textDelta:
          assistant.content += ev.delta ?? '';
          break;
        case AiChatEventKind.toolCall:
          _totalToolCalls++;
          assistant.toolCalls ??= [];
          assistant.toolCalls!.add(ToolCall(
            id: ev.toolCallId ?? 'call_${assistant.toolCalls!.length}',
            name: ev.toolName ?? '',
            argumentsJson: ev.toolArguments ?? '{}',
          ));
          // 占位 tool 消息，等 tool_result 事件填回
          session.messages.add(ChatMessage(
            role: 'tool',
            content: '',
            streaming: true,
            toolCallId: ev.toolCallId,
            name: ev.toolName,
          ));
          break;
        case AiChatEventKind.toolResult:
          for (final m in session.messages.reversed) {
            if (m.role == 'tool' &&
                m.toolCallId == ev.toolCallId &&
                m.streaming) {
              m.content = ev.toolResult ?? '';
              m.streaming = false;
              break;
            }
          }
          break;
        case AiChatEventKind.done:
          if (ev.balanceAfter != null) _lastBalance = ev.balanceAfter;
          break;
        case AiChatEventKind.error:
          final code = ev.errorCode ?? '';
          if (code == 'AI.INSUFFICIENT_BALANCE' || code == 'AI.CHARGE') {
            // 余额相关错误：UI 层负责弹「前往充值」对话框，正文不再叠加。
            _chargeIssue = ChargeIssue(
              code: code,
              message: ev.errorMessage ?? '喜点不足，请先充值。',
              balance: ev.balanceAfter,
            );
          } else {
            assistant.content +=
                '${assistant.content.isEmpty ? '' : '\n\n'}⚠️ ${ev.errorCode}：${ev.errorMessage}';
          }
          break;
      }
      notifyListeners();
    }, onError: (Object e, StackTrace st) {
      assistant.content +=
          '${assistant.content.isEmpty ? '' : '\n\n'}⚠️ 调用失败：$e';
      if (!completer.isCompleted) completer.complete();
    }, onDone: () {
      if (!completer.isCompleted) completer.complete();
    });

    try {
      await completer.future;
    } finally {
      assistant.streaming = false;
      // 关闭仍 streaming 的 tool 占位
      for (final m in session.messages) {
        if (m.role == 'tool' && m.streaming) {
          m.streaming = false;
          if (m.content.isEmpty) m.content = '(无返回)';
        }
      }
      _streaming = false;
      _activeStream = null;
      session.updatedAt = DateTime.now();
      await session.save();
      notifyListeners();
    }
  }

  String _summarizeForTitle(String text) {
    final t = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    return t.length > 20 ? '${t.substring(0, 20)}…' : t;
  }

  ChatSession? _byId(String id) {
    for (final s in _sessions) {
      if (s.id == id) return s;
    }
    return null;
  }

  @override
  void dispose() {
    _activeStream?.cancel();
    super.dispose();
  }
}

/// ChatState 暴露给 UI 的「需要充值」事件载荷。
class ChargeIssue {
  ChargeIssue({required this.code, required this.message, this.balance});

  /// 'AI.INSUFFICIENT_BALANCE' 或 'AI.CHARGE'.
  final String code;

  /// 来自后端的详细消息（含当前余额、预估开销）。
  final String message;

  /// 后端 SSE 事件里若提供就一并保留。
  final int? balance;
}
