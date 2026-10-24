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
/// - 客户端不再持有任何第三方 API key / token；工具调用全部由服务端派发。
/// - 会话上下文以服务端 ai_chat_sessions 为准；本地仅缓存 UI 渲染所需的消息列表。
///
/// 客户端 ChatSession 与服务端 session 的映射：
/// - 本地 ChatSession.id 是客户端 UUID（继续作为 Hive box key）。
/// - 服务端首次 emit `session` 事件返回 server session_id，写入 [_serverIdMap]
///   并落地到 prefsBox（key 形如 `ai_chat_server_id:<localId>`）。
/// - 后续发送沿用 server id 让服务端拼齐历史；丢失映射只会让"上下文记忆"重置，
///   不影响本地展示的旧消息。
class ChatState extends ChangeNotifier {
  ChatState({AiChatService? service, ChatSessionStore? store})
      : _svc = service ?? AiChatService(),
        _store = store ?? HiveChatSessionStore();

  final AiChatService _svc;
  final ChatSessionStore _store;

  StreamSubscription<AiChatEvent>? _activeStream;

  /// 每次发送递增；旧流的收尾逻辑据此判断自己是否已被新一轮取代。
  /// （回答 done 之后流还会多开几秒等推荐追问，期间用户可以直接发下一条。）
  int _sendSeq = 0;

  /// 当前流对应的完成信号：取消订阅不会触发 onDone，主动取消时要手动结束它，
  /// 否则 sendMessage 的 Future 永远不返回。
  Completer<void>? _activeCompleter;

  void _completeActive() {
    final c = _activeCompleter;
    _activeCompleter = null;
    if (c != null && !c.isCompleted) c.complete();
  }

  /// 全部会话（Hive 里一个盒子）。多主题下线后不再按主题过滤：老版本留下的
  /// 会话（钓鱼、咖啡那些）也照常显示在列表里，不会被悄悄藏起来。
  List<ChatSession> _sessions = const [];
  String? _activeId;

  bool _streaming = false;
  int _totalToolCalls = 0;
  int? _lastBalance;

  final Map<String, String> _serverIdMap = {};

  static const _kServerIdPrefix = 'ai_chat_server_id:';

  /// 会话（按最近更新排序）。
  List<ChatSession> get sessions => List.unmodifiable(_sessions);
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
  Persona get currentPersona =>
      Personas.byId(active?.personaId, topic: active?.topic ?? 'money');

  ChatSession? _mostRecent() => _sessions.isEmpty ? null : _sessions.first;

  /// 本机往当前会话里插一条 assistant 消息（伴侣主动开口用）。
  ///
  /// 不走 /v1/ai/chat、不扣喜点；只是把她说的话放进本地会话。
  Future<void> addLocalMessage(String text) async {
    final session = active ?? await newSession();
    session.messages.add(ChatMessage(role: 'assistant', content: text));
    session.updatedAt = DateTime.now();
    _store.save(session);
    notifyListeners();
  }

  Future<void> bootstrap() async {
    _sessions = _store.load()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final first = _mostRecent();
    if (first == null) {
      await newSession();
    } else {
      _activeId = first.id;
    }
    for (final s in _sessions) {
      try {
        final v = prefsBox.get('$_kServerIdPrefix${s.id}');
        if (v is String && v.isNotEmpty) _serverIdMap[s.id] = v;
      } catch (_) {
        // 盒子没打开（单测）时跳过服务端会话映射，不影响本地会话。
      }
    }
    notifyListeners();
  }

  Future<ChatSession> newSession({
    String title = '新对话',
    String? personaId,
    String? topic,
  }) async {
    final t = topic ?? active?.topic ?? 'money';
    final s = ChatSession(
      title: title,
      personaId:
          personaId ?? (topic == null ? active?.personaId : null) ??
              Personas.defaultIdFor(t),
      toolsEnabled: active?.toolsEnabled ?? true,
      topic: t,
    );
    _sessions = [s, ..._sessions];
    _activeId = s.id;
    notifyListeners();
    // 落盘不挡调用方：内存里的会话列表就是界面的真相，写盘排队进行。
    // （UI 上新开一段对话要立刻换页，不能等文件写完。）
    _store.save(s);
    return s;
  }

  Future<void> deleteSession(String id) async {
    _store.remove(id);
    await prefsBox.delete('$_kServerIdPrefix$id');
    _serverIdMap.remove(id);
    _sessions = _sessions.where((s) => s.id != id).toList();
    if (_activeId == id) {
      _activeId = _mostRecent()?.id;
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
    _sendSeq++;
    await _activeStream?.cancel();
    _completeActive();
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

    _store.clear();

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
  ///
  /// [portfolioContext] 非空时本次请求附带"组合快照"：
  /// 服务端会把它拼到 system prompt，让 LLM 理解"我的持仓 / 解套 / 止盈"等
  /// 自然语言指代。客户端层面在用户主动 @组合 / 进入解套止盈/诊断报告
  /// 入口时由调用方自行构造（来自 PortfolioSummary.toAiContext()）。
  Future<void> sendMessage(
    String text, {
    Map<String, dynamic>? portfolioContext,
    List<String>? imageDataUrls,
    List<String>? preferences,
  }) async {
    final session = active ?? await newSession();
    final images = imageDataUrls ?? const <String>[];
    // 允许「只发图不发文」。
    if ((text.trim().isEmpty && images.isEmpty) || _streaming) return;

    // 上一轮回答已 done、流还在等推荐追问：直接放弃那条追问，开始新一轮。
    final lingering = _activeStream;
    if (lingering != null) {
      _activeStream = null;
      await lingering.cancel();
      _completeActive();
    }
    final seq = ++_sendSeq;

    final hasPortfolio =
        portfolioContext != null && portfolioContext.isNotEmpty;
    final userMsg = ChatMessage(
      role: 'user',
      content: text.trim(),
      portfolioAttached: hasPortfolio,
      portfolioName: hasPortfolio ? portfolioContext['name'] as String? : null,
      imageDataUrls: images.isEmpty ? null : List<String>.from(images),
    );
    session.messages.add(userMsg);
    if (session.title == '新对话' || session.title.isEmpty) {
      session.title = text.trim().isEmpty ? '图片提问' : _summarizeForTitle(text);
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

    // 人设 prompt 由服务端按 (topic, persona) 维护，客户端只传 id。
    final completer = Completer<void>();
    _activeCompleter = completer;
    _activeStream = _svc
        .stream(
      serverSessionId: _serverIdMap[session.id],
      message: text.trim(),
      persona: session.personaId,
      topic: session.topic,
      // 产品策略：喜爱钱深度推理始终开启（+5 喜点），不暴露给用户切换；
      // 其它圈按 1 喜点 / 轮的普通对话（服务端也会强制）。
      deepMode: session.topic == 'money',
      preferences: preferences,
      portfolioContext: portfolioContext,
      images: images.isEmpty ? null : images,
      wantSuggestions: true,
    )
        .listen((ev) async {
      // 已被新一轮发送 / 中止取代的旧流：丢弃后续事件。
      if (seq != _sendSeq) return;
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
          // 回答已经完整：立刻结束「输出中」状态（操作栏出现、可以继续发），
          // 流本身再多开几秒等可选的 suggestions 事件。
          _finishTurn(session, assistant);
          _streaming = false;
          // ignore: unawaited_futures
          session.save();
          break;
        case AiChatEventKind.suggestions:
          final qs = ev.suggestions ?? const <String>[];
          if (qs.isNotEmpty) {
            assistant.suggestions = qs.take(3).toList();
            // ignore: unawaited_futures
            session.save();
          }
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
      _finishTurn(session, assistant);
      // 只有仍是当前这一轮时才清理全局状态；已被新一轮取代则不动。
      if (seq == _sendSeq) {
        _streaming = false;
        _activeStream = null;
      }
      session.updatedAt = DateTime.now();
      await session.save();
      notifyListeners();
    }
  }

  /// 收尾一轮回答：结束 assistant 的 streaming、关闭仍在等待的 tool 占位。
  void _finishTurn(ChatSession session, ChatMessage assistant) {
    assistant.streaming = false;
    for (final m in session.messages) {
      if (m.role == 'tool' && m.streaming) {
        m.streaming = false;
        if (m.content.isEmpty) m.content = '(无返回)';
      }
    }
  }

  /// 当前会话里最后一条 assistant 回答（推荐追问 / 重新生成只作用于它）。
  ChatMessage? get latestAssistant {
    final list = active?.messages ?? const <ChatMessage>[];
    for (final m in list.reversed) {
      if (m.role == 'assistant') return m;
      if (m.role == 'user') return null;
    }
    return null;
  }

  /// 重新生成最新一条回答：撤掉这轮的 user / assistant / tool 消息，
  /// 用同样的提问（含图片）再问一次。会按正常对话扣费。
  Future<void> regenerate(ChatMessage assistant) async {
    final session = active;
    if (session == null || _streaming) return;
    final idx = session.messages.indexOf(assistant);
    if (idx < 0) return;
    var userIdx = -1;
    for (var i = idx - 1; i >= 0; i--) {
      if (session.messages[i].role == 'user') {
        userIdx = i;
        break;
      }
    }
    if (userIdx < 0) return;
    final user = session.messages[userIdx];
    final text = user.content;
    final images = user.imageDataUrls;
    session.messages.removeRange(userIdx, session.messages.length);
    notifyListeners();
    await sendMessage(text, imageDataUrls: images);
  }

  /// 点赞 / 点踩（再点一次同样的取消）。本地立即生效，服务端尽力记录。
  Future<void> setFeedback(ChatMessage assistant, int rating) async {
    final session = active;
    final next = assistant.feedback == rating ? 0 : rating;
    assistant.feedback = next;
    notifyListeners();
    if (session != null) await session.save();
    String? question;
    if (session != null) {
      final idx = session.messages.indexOf(assistant);
      for (var i = idx - 1; i >= 0; i--) {
        final m = session.messages[i];
        if (m.role == 'user') {
          question = m.content;
          break;
        }
      }
    }
    try {
      await _svc.sendFeedback(
        serverSessionId: session == null ? null : _serverIdMap[session.id],
        messageId: assistant.id,
        rating: next,
        question: question,
        answer: assistant.content,
      );
    } catch (_) {
      // 反馈只是参考数据：网络失败不打扰用户，本地状态保留。
    }
  }

  /// 仅供测试 / 截图：直接注入会话，不经过 Hive。
  @visibleForTesting
  void debugSeed(List<ChatSession> sessions, {String? activeId}) {
    _sessions = sessions;
    _activeId = activeId ?? (sessions.isEmpty ? null : sessions.first.id);
    notifyListeners();
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

/// 会话落盘的落点。
///
/// 抽出来是为了测试能注入内存实现：Hive 的写在 widget 测试的假时钟下不会
/// 完成，会把写锁一直握着，后面的 setUp 就永远等下去。
/// 生产实现见 [HiveChatSessionStore]。
abstract class ChatSessionStore {
  /// 读出全部会话。
  List<ChatSession> load();

  /// 写一条。**不返回 Future**：界面不等落盘。
  void save(ChatSession session);

  void remove(String id);

  void clear();
}

/// Hive 实现：一个盒子装全部主题的会话。
class HiveChatSessionStore implements ChatSessionStore {
  @override
  List<ChatSession> load() {
    try {
      return chatSessionsBox.values.toList();
    } catch (_) {
      // 盒子没打开（单元测试）时当作空，不抛。
      return const [];
    }
  }

  @override
  void save(ChatSession session) {
    try {
      // ignore: unawaited_futures
      chatSessionsBox.put(session.id, session);
    } catch (_) {
      // 存不进去也不能让会话从眼前消失：内存里还有一份。
    }
  }

  @override
  void remove(String id) {
    try {
      // ignore: unawaited_futures
      chatSessionsBox.delete(id);
    } catch (_) {}
  }

  @override
  void clear() {
    try {
      // ignore: unawaited_futures
      chatSessionsBox.clear();
    } catch (_) {}
  }
}

/// 测试用。
class MemoryChatSessionStore implements ChatSessionStore {
  final Map<String, ChatSession> _data = {};

  @override
  List<ChatSession> load() => _data.values.toList();

  @override
  void save(ChatSession session) => _data[session.id] = session;

  @override
  void remove(String id) => _data.remove(id);

  @override
  void clear() => _data.clear();
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
