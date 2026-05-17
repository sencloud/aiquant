import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/storage/hive_setup.dart';
import '../models/chat.dart';
import '../models/persona.dart';
import '../services/ai_tools.dart';
import '../services/ai_tools/registry.dart';
import '../services/deepseek_service.dart';

/// Tool execution loop 最大迭代次数 — 防止 LLM 自循环耗尽 token。
/// 设置得相对宽松，确保模型在多轮工具调用后仍有空间给出最终总结。
const int _kMaxToolIterations = 12;

class ChatState extends ChangeNotifier {
  ChatState({
    DeepSeekService? service,
    ToolRegistry? registry,
  })  : _svc = service ?? DeepSeekService(),
        _registry = registry ?? buildAllTools();

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
      // 关键：每个 assistant.tool_calls 必须紧跟着完整的 role=tool 应答；
      // 若上一轮中断/失败导致某个 tool_call 没有对应结果，OpenAI 会 400
      // 整个 history → 模型表现为"失忆"。这里把孤儿 tool_calls 剥掉。
      final completedToolIds = <String>{
        for (final m in session.messages)
          if (m.role == 'tool' && !m.streaming && m.toolCallId != null)
            m.toolCallId!,
      };
      final history = <Map<String, dynamic>>[
        {'role': 'system', 'content': _systemPrompt(session)},
      ];
      for (final m in session.messages) {
        if (m.streaming) continue;
        if (m.role == 'tool' &&
            (m.toolCallId == null ||
                !completedToolIds.contains(m.toolCallId))) {
          continue;
        }
        if (m.role == 'assistant' &&
            m.toolCalls != null &&
            m.toolCalls!.isNotEmpty) {
          final allDone =
              m.toolCalls!.every((c) => completedToolIds.contains(c.id));
          if (!allDone) {
            // 剥掉 tool_calls，仅保留正文（可能为空，会被 service 转成 null）
            history.add(chatMessageToOpenAi(
                ChatMessage(role: 'assistant', content: m.content)));
            continue;
          }
        }
        history.add(chatMessageToOpenAi(m));
      }

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
        finishReason = 'error';
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

你拥有以下五类工具，可以查询真实数据后再作答；当回答需要具体行情/财务/资金/事件信息时，**优先调用工具，不要凭记忆**：

A. 行情与基础（Tushare）：search_instrument / get_quote / compare_quotes / list_industry_stocks / get_market_snapshot / list_etfs_by_theme
B. 量化指标（本地计算）：calc_returns / calc_sharpe / calc_max_drawdown / calc_correlation / calc_beta / calc_moving_average / calc_rsi / calc_macd
C. 基本面（财报）：get_valuation / get_income_statement / get_balance_sheet / get_cash_flow / get_top_holders / get_dividend_history
D. 宏观资金面：get_index_components / get_margin_trading / get_northbound_flow / get_industry_money_flow
E. 全球事件流：search_global_events（GDELT 全球新闻+事件）/ search_chinese_news（中文媒体）/ search_shipping_events（航运/海运中断）/ search_geopolitics_events（地缘冲突/制裁）/ get_satellite_fire_hotspots（NASA 卫星火点）

调用规范：
- 用户给的"代码"可能是 6 位数字（如 600519）；工具会自动归一化到 ts_code。
- 多个标的横向比较时使用 compare_quotes / calc_correlation 等批量工具，避免分次调用。
- 工具结果是 JSON；总结时把数字翻译成易读形式（+3.21%、¥1830.00、近 252 个交易日…）并标注时间范围与样本数。
- 工具返回 {error:...} 时，向用户解释原因并尝试合理替代或备选数据源。

事件流分析方法（重要）：
- 当用户关注的标的可能受外部事件影响时（如航运板块 / 大宗商品 / 军工 / 能源 / 跨境电商），主动调用 E 类工具拉取最近事件，再结合 A/B 类行情/指标做"事件 → 标的"的影响分析。
- 分析时按"事件摘要 → 传导链条 → 受益/受损标的 → 验证（行情/资金面）→ 风险与不确定性"的结构。
- GDELT 返回的 tone 字段为新闻情绪基调（正值正面、负值负面、典型范围 -10~+10），可作为情绪指标参考。
- 注意：事件影响是概率性叙事，不是确定性预测；务必给出对立观点和风险提示。''';
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

  /// 一次性后台执行：用指定 [personaId] 跑一段 prompt，等完整结果（含工具
  /// 调用 loop）后返回 markdown 字符串。供 DING 定时任务使用，不会写入
  /// 任何会话历史。
  ///
  /// [withTools]=true 时启用全部工具（默认）；模型若选择调用工具会自动跑
  /// 完一整轮 tool loop 再返回最终答复。
  Future<DingExecutionResult> executeOneShot({
    required String prompt,
    String? personaId,
    bool withTools = true,
    int maxIterations = _kMaxToolIterations,
  }) async {
    final persona = Personas.byId(personaId);
    final history = <Map<String, dynamic>>[
      {'role': 'system', 'content': _composedSystemPrompt(persona, withTools)},
      {'role': 'user', 'content': prompt},
    ];

    final tools = withTools ? _registry.toOpenAiList() : null;
    var totalTokens = 0;
    final toolTrace = <Map<String, String>>[];

    for (var iter = 0; iter < maxIterations; iter++) {
      final pendingTools = <int, _PendingToolCall>{};
      final contentBuf = StringBuffer();
      String? finishReason;
      final completer = Completer<void>();

      late StreamSubscription<DeepSeekChunk> sub;
      sub = _svc
          .chatStreamRaw(messages: history, tools: tools)
          .listen((chunk) {
        if (chunk.delta != null) contentBuf.write(chunk.delta);
        if (chunk.toolCalls != null) {
          for (final tc in chunk.toolCalls!) {
            final p =
                pendingTools.putIfAbsent(tc.index, () => _PendingToolCall());
            if (tc.id != null && tc.id!.isNotEmpty) p.id = tc.id;
            if (tc.name != null && tc.name!.isNotEmpty) p.name = tc.name;
            if (tc.argumentsDelta != null) p.arguments += tc.argumentsDelta!;
          }
        }
        if (chunk.totalTokens != null) totalTokens = chunk.totalTokens!;
        if (chunk.done) {
          finishReason = chunk.finishReason;
          if (!completer.isCompleted) completer.complete();
        }
      }, onError: (Object e, StackTrace st) {
        if (!completer.isCompleted) completer.completeError(e);
      }, onDone: () {
        if (!completer.isCompleted) completer.complete();
      });

      try {
        await completer.future;
      } finally {
        await sub.cancel();
      }

      final calls = pendingTools.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      final toolCalls = [
        for (final entry in calls)
          ToolCall(
            id: entry.value.id ?? 'call_${iter}_${entry.key}',
            name: entry.value.name ?? '',
            argumentsJson: entry.value.arguments,
          ),
      ];
      final assistantMsg = ChatMessage(
        role: 'assistant',
        content: contentBuf.toString(),
        toolCalls: toolCalls.isEmpty ? null : toolCalls,
      );
      history.add(chatMessageToOpenAi(assistantMsg));

      if (finishReason != 'tool_calls' || toolCalls.isEmpty) {
        return DingExecutionResult(
          content: contentBuf.toString(),
          totalTokens: totalTokens,
          toolTrace: toolTrace,
        );
      }

      for (final tc in toolCalls) {
        final result =
            _trimToolResult(await _registry.dispatch(tc.name, tc.argumentsJson));
        toolTrace.add({'name': tc.name, 'result_brief': _briefForTrace(result)});
        history.add(chatMessageToOpenAi(ChatMessage(
          role: 'tool',
          content: result,
          toolCallId: tc.id,
          name: tc.name,
        )));
      }
    }
    return DingExecutionResult(
      content: '执行超过最大迭代次数，未生成完整结果。',
      totalTokens: totalTokens,
      toolTrace: toolTrace,
    );
  }

  String _composedSystemPrompt(Persona persona, bool withTools) {
    final base = persona.systemPrompt.trim();
    if (!withTools) return base;
    return '''$base

——

你拥有以下五类工具，可以查询真实数据后再作答；当回答需要具体行情/财务/资金/事件信息时，**优先调用工具，不要凭记忆**：

A. 行情与基础（Tushare）：search_instrument / get_quote / compare_quotes / list_industry_stocks / get_market_snapshot / list_etfs_by_theme
B. 量化指标（本地计算）：calc_returns / calc_sharpe / calc_max_drawdown / calc_correlation / calc_beta / calc_moving_average / calc_rsi / calc_macd
C. 基本面（财报）：get_valuation / get_income_statement / get_balance_sheet / get_cash_flow / get_top_holders / get_dividend_history
D. 宏观资金面：get_index_components / get_margin_trading / get_northbound_flow / get_industry_money_flow
E. 全球事件流：search_global_events / search_chinese_news / search_shipping_events / search_geopolitics_events / get_satellite_fire_hotspots

输出格式：用中文 Markdown，结构化（要点 / 表格 / 数字 / 数据来源），最后给出关键风险提示。''';
  }

  String _briefForTrace(String raw) {
    final s = raw.replaceAll(RegExp(r'\s+'), ' ');
    return s.length > 120 ? '${s.substring(0, 120)}…' : s;
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

/// DING 一次性执行的产物。
class DingExecutionResult {
  final String content;
  final int totalTokens;
  final List<Map<String, String>> toolTrace;
  DingExecutionResult({
    required this.content,
    required this.totalTokens,
    required this.toolTrace,
  });
}

// ignore: unused_element
String _debugFmt(Object? o) => const JsonEncoder.withIndent('  ').convert(o);
