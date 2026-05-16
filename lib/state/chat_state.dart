import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/storage/hive_setup.dart';
import '../models/chat.dart';
import '../models/persona.dart';
import '../services/ai_tools.dart';
import '../services/ai_tools/tushare_tools.dart';
import '../services/deepseek_service.dart';

/// Tool execution loop 最大迭代次数 — 防止 LLM 自循环耗尽 token
const int _kMaxToolIterations = 5;

class ChatState extends ChangeNotifier {
  ChatState({
    DeepSeekService? service,
    ToolRegistry? registry,
  })  : _svc = service ?? DeepSeekService(),
        _registry = registry ?? buildTushareToolRegistry();

  final DeepSeekService _svc;
  final ToolRegistry _registry;
  StreamSubscription<DeepSeekChunk>? _activeStream;
  bool _aborted = false;

  List<ChatSession> _sessions = const [];
  String? _activeId;
  bool _streaming = false;
  int _totalTokens = 0;

  List<ChatSession> get sessions => _sessions;
  String? get activeId => _activeId;
  bool get streaming => _streaming;
  int get totalTokens => _totalTokens;
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
    _aborted = true;
    await _activeStream?.cancel();
    _activeStream = null;
    _streaming = false;
    notifyListeners();
  }

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
    _aborted = false;
    _streaming = true;
    notifyListeners();

    try {
      await _runToolLoop(session);
    } finally {
      _streaming = false;
      _activeStream = null;
      session.updatedAt = DateTime.now();
      await session.save();
      notifyListeners();
    }
  }

  /// 多轮工具调用 loop — 直到模型 finish_reason=stop 或达到上限。
  Future<void> _runToolLoop(ChatSession session) async {
    for (var iter = 0; iter < _kMaxToolIterations; iter++) {
      if (_aborted) return;

      final assistant = ChatMessage(
        role: 'assistant',
        content: '',
        reasoning: '',
        streaming: true,
      );
      session.messages.add(assistant);
      notifyListeners();

      // 构建 OpenAI 协议 messages
      final history = <Map<String, dynamic>>[
        {'role': 'system', 'content': _systemPrompt(session)},
        for (final m in session.messages.where((m) => !m.streaming))
          chatMessageToOpenAi(m),
      ];

      final tools = session.toolsEnabled ? _registry.toOpenAiList() : null;

      final pendingTools = <int, _PendingToolCall>{};
      String? finishReason;

      final completer = Completer<void>();
      _activeStream = _svc
          .chatStreamRaw(messages: history, tools: tools)
          .listen((chunk) {
        if (chunk.delta != null) {
          assistant.content += chunk.delta!;
        }
        if (chunk.reasoning != null) {
          assistant.reasoning =
              (assistant.reasoning ?? '') + chunk.reasoning!;
        }
        if (chunk.toolCalls != null) {
          for (final tc in chunk.toolCalls!) {
            final p =
                pendingTools.putIfAbsent(tc.index, () => _PendingToolCall());
            if (tc.id != null && tc.id!.isNotEmpty) p.id = tc.id;
            if (tc.name != null && tc.name!.isNotEmpty) p.name = tc.name;
            if (tc.argumentsDelta != null) p.arguments += tc.argumentsDelta!;
          }
        }
        if (chunk.totalTokens != null) {
          _totalTokens = chunk.totalTokens!;
        }
        if (chunk.done) {
          finishReason = chunk.finishReason;
          if (!completer.isCompleted) completer.complete();
        }
        notifyListeners();
      }, onError: (Object e, StackTrace st) {
        assistant.content +=
            '${assistant.content.isEmpty ? '' : '\n'}⚠️ 调用失败：$e';
        if (!completer.isCompleted) completer.complete();
      }, onDone: () {
        if (!completer.isCompleted) completer.complete();
      });

      await completer.future;
      _activeStream = null;
      if (_aborted) {
        assistant.streaming = false;
        return;
      }

      // 整理本轮 assistant 消息
      if (pendingTools.isNotEmpty) {
        assistant.toolCalls = [
          for (final entry in (pendingTools.entries.toList()
                ..sort((a, b) => a.key.compareTo(b.key))))
            ToolCall(
              id: entry.value.id ?? 'call_${iter}_${entry.key}',
              name: entry.value.name ?? '',
              argumentsJson: entry.value.arguments,
            ),
        ];
      }
      assistant.streaming = false;
      await session.save();
      notifyListeners();

      // 没有 tool_calls 或 finish_reason=stop → 一轮搞定，退出
      if (finishReason != 'tool_calls' ||
          assistant.toolCalls == null ||
          assistant.toolCalls!.isEmpty) {
        return;
      }

      // 执行每个 tool_call，把结果当 role=tool 消息追加
      for (final tc in assistant.toolCalls!) {
        if (_aborted) return;
        // UI 占位：先建一个 streaming=true 的 tool 消息
        final placeholder = ChatMessage(
          role: 'tool',
          content: '',
          streaming: true,
          toolCallId: tc.id,
          name: tc.name,
        );
        session.messages.add(placeholder);
        notifyListeners();

        final resultJson = await _registry.dispatch(tc.name, tc.argumentsJson);
        placeholder.content = _trimToolResult(resultJson);
        placeholder.streaming = false;
        await session.save();
        notifyListeners();
      }
      // 进入下一轮 LLM 调用
    }
    // 超过最大迭代——不再继续，避免死循环
  }

  /// 工具结果可能很长（行情序列）；上限 8KB 避免上下文爆炸。
  String _trimToolResult(String raw) {
    const maxLen = 8000;
    if (raw.length <= maxLen) return raw;
    return '${raw.substring(0, maxLen)}…<truncated by app: original ${raw.length} chars>';
  }

  String _systemPrompt(ChatSession session) {
    final persona = Personas.byId(session.personaId);
    final base = persona.systemPrompt.trim();
    if (!session.toolsEnabled) return base;
    return '''$base

——

你拥有以下工具用于查询真实市场数据（Tushare）。当回答需要具体行情、个股代码、指数走势、ETF 列表时，**优先调用工具**而不是凭记忆作答。
- 用户给的"代码"可能是 6 位数字（如 600519）；调用工具时直接传入即可，工具会自动归一化到 ts_code（如 600519.SH）。
- 多个标的对比时使用 compare_quotes 一次调用，避免分多次。
- 工具调用结果是 JSON；总结时把数字转成易读形式（如 +3.21%、收盘价 ¥1830.00）并标注交易日范围。
- 调用工具失败时（结果含 error 字段），向用户解释原因并尝试合理替代方案。''';
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

class _PendingToolCall {
  String? id;
  String? name;
  String arguments = '';
}

// ignore: unused_element
String _debugFmt(Object? o) => const JsonEncoder.withIndent('  ').convert(o);
