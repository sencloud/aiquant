import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/storage/hive_setup.dart';
import '../models/chat.dart';
import '../services/deepseek_service.dart';

class ChatState extends ChangeNotifier {
  ChatState({DeepSeekService? service}) : _svc = service ?? DeepSeekService();

  final DeepSeekService _svc;
  StreamSubscription<DeepSeekChunk>? _activeStream;

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

  Future<ChatSession> newSession({String title = '新对话'}) async {
    final s = ChatSession(title: title);
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

  Future<void> abort() async {
    await _activeStream?.cancel();
    _activeStream = null;
    _streaming = false;
    notifyListeners();
  }

  Future<void> sendMessage(String text) async {
    final session = active ?? await newSession();
    if (text.trim().isEmpty || _streaming) return;

    final user = ChatMessage(role: 'user', content: text.trim());
    final assistant = ChatMessage(
      role: 'assistant',
      content: '',
      reasoning: '',
      streaming: true,
    );
    session.messages
      ..add(user)
      ..add(assistant);
    if (session.title == '新对话' || session.title.isEmpty) {
      session.title = _summarizeForTitle(text);
    }
    session.updatedAt = DateTime.now();
    await session.save();
    _streaming = true;
    notifyListeners();

    final history = [
      for (final m in session.messages.where((m) => !m.streaming))
        ChatTurn(m.role, m.content),
    ];

    final completer = Completer<void>();
    _activeStream = _svc
        .chatStream(
          history: history,
          systemPrompt: _buildSystemPrompt(),
        )
        .listen((chunk) async {
      if (chunk.delta != null) {
        assistant.content += chunk.delta!;
      }
      if (chunk.reasoning != null) {
        assistant.reasoning = (assistant.reasoning ?? '') + chunk.reasoning!;
      }
      if (chunk.totalTokens != null) {
        _totalTokens = chunk.totalTokens!;
      }
      if (chunk.done) {
        assistant.streaming = false;
        session.updatedAt = DateTime.now();
        await session.save();
        _streaming = false;
        if (!completer.isCompleted) completer.complete();
      }
      notifyListeners();
    }, onError: (Object e, StackTrace st) async {
      assistant.content +=
          '${assistant.content.isEmpty ? '' : '\n'}⚠️ 调用失败：$e';
      assistant.streaming = false;
      _streaming = false;
      await session.save();
      if (!completer.isCompleted) completer.complete();
      notifyListeners();
    }, onDone: () async {
      if (assistant.streaming) {
        assistant.streaming = false;
        await session.save();
        _streaming = false;
        if (!completer.isCompleted) completer.complete();
        notifyListeners();
      }
    });

    await completer.future;
  }

  String _buildSystemPrompt() {
    return '你是 Fincept 终端内置的金融研究助理。你可以引用 Tushare 行情'
        '、A 股 / 港股 / 期货 / ETF / 指数等数据回答用户问题。'
        '请使用简洁、结构化、面向投资者的中文回答，必要时给出关键数字、'
        '数据来源与风险提示，避免泛泛而谈。';
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
