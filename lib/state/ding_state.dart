import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/ding.dart';
import '../services/ding_service.dart';
import 'chat_state.dart';

/// DingState — 服务端为唯一真源，客户端仅缓存与本地驱动调度。
///
/// 调度策略（移动端没有真后台 cron）：
/// - 前台时每 60s 扫一次 [_tasks] 中 enabled 的任务；
/// - 启动 / 从后台回到前台时 catchUp = true，把 nextRunAt < now 的任务"补跑一次"；
/// - 实际跑由 [ChatState.executeOneShot] 完成；结果通过 DingService.reportRun
///   上传到服务端（生成 notification + 更新 last/next_run_at）。
class DingState extends ChangeNotifier {
  DingState({
    required ChatState chat,
    DingService? service,
  })  : _chat = chat,
        _service = service ?? DingService();

  final ChatState _chat;
  final DingService _service;

  Timer? _ticker;
  bool _ticking = false;
  bool _bootstrapped = false;
  // 正在执行的任务 uuid（防止 tick 重叠）
  final Set<String> _running = {};

  // ── 状态 ──────────────────────────────────────────────────────────────
  final List<DingTask> _tasks = [];
  final List<DingMessage> _messages = [];
  int _nextCursor = 0;
  bool _hasMoreMessages = true;
  bool _loadingMessages = false;
  String? _lastError;

  List<DingTask> get tasks => List.unmodifiable(_tasks);
  List<DingMessage> get messages => List.unmodifiable(_messages);
  int get unreadCount => _messages.where((m) => !m.read).length;
  bool get loadingMessages => _loadingMessages;
  bool get hasMoreMessages => _hasMoreMessages;
  String? get lastError => _lastError;

  Set<String> get runningTaskIds => Set.unmodifiable(_running);
  bool isRunning(String taskId) => _running.contains(taskId);

  // ── 生命周期 ──────────────────────────────────────────────────────────

  /// 登录后调用，从服务端拉一次 tasks + 第一页 inbox，并启动 60s ticker。
  Future<void> bootstrap() async {
    if (_bootstrapped) return;
    _bootstrapped = true;
    await refreshAll(catchUp: true);
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 60), (_) => _tick());
  }

  /// 用户登出：停 ticker 并清空。
  void reset() {
    _ticker?.cancel();
    _ticker = null;
    _tasks.clear();
    _messages.clear();
    _nextCursor = 0;
    _hasMoreMessages = true;
    _running.clear();
    _bootstrapped = false;
    _lastError = null;
    notifyListeners();
  }

  /// 重新拉服务端数据 + 可选立刻补跑。
  Future<void> refreshAll({bool catchUp = false}) async {
    await Future.wait([
      _refreshTasks(),
      _refreshFirstPage(),
    ]);
    if (catchUp) {
      await _tick(catchUp: true);
    }
  }

  /// 由 HomeScreen lifecycle / 手动刷新触发。
  void resumeFromBackground() {
    Future.microtask(() => refreshAll(catchUp: true));
  }

  Future<void> _refreshTasks() async {
    try {
      final list = await _service.listTasks();
      _tasks
        ..clear()
        ..addAll(list);
      _lastError = null;
      notifyListeners();
    } catch (e) {
      _lastError = e.toString();
      notifyListeners();
    }
  }

  Future<void> _refreshFirstPage() async {
    if (_loadingMessages) return;
    _loadingMessages = true;
    notifyListeners();
    try {
      final r = await _service.listNotifications();
      _messages
        ..clear()
        ..addAll(r.items);
      _nextCursor = r.nextCursor;
      _hasMoreMessages = r.nextCursor > 0;
      _lastError = null;
    } catch (e) {
      _lastError = e.toString();
    } finally {
      _loadingMessages = false;
      notifyListeners();
    }
  }

  /// 列表下拉到底加载更多。
  Future<void> loadMoreMessages() async {
    if (_loadingMessages || !_hasMoreMessages) return;
    _loadingMessages = true;
    notifyListeners();
    try {
      final r = await _service.listNotifications(cursor: _nextCursor);
      _messages.addAll(r.items);
      _nextCursor = r.nextCursor;
      _hasMoreMessages = r.nextCursor > 0;
    } catch (e) {
      _lastError = e.toString();
    } finally {
      _loadingMessages = false;
      notifyListeners();
    }
  }

  // ── Tasks CRUD（服务端为真源） ───────────────────────────────────────

  Future<DingTask> createTask({
    required String title,
    required String prompt,
    required String schedule,
    String personaId = 'default',
    bool enabled = true,
  }) async {
    final t = await _service.createTask(
      title: title,
      prompt: prompt,
      schedule: schedule,
      personaId: personaId,
      enabled: enabled,
    );
    _tasks.add(t);
    notifyListeners();
    return t;
  }

  Future<void> updateTask(
    DingTask t, {
    String? title,
    String? prompt,
    String? schedule,
    String? personaId,
    bool? enabled,
  }) async {
    final updated = await _service.updateTask(
      t.id,
      title: title,
      prompt: prompt,
      schedule: schedule,
      personaId: personaId,
      enabled: enabled,
    );
    final i = _tasks.indexWhere((x) => x.id == t.id);
    if (i >= 0) _tasks[i] = updated;
    notifyListeners();
  }

  Future<void> setEnabled(DingTask t, bool enabled) async {
    await updateTask(t, enabled: enabled);
  }

  Future<void> deleteTask(DingTask t) async {
    await _service.deleteTask(t.id);
    _tasks.removeWhere((x) => x.id == t.id);
    notifyListeners();
  }

  Future<DingMessage?> runNow(DingTask t) async {
    return _execute(t, manual: true);
  }

  // ── Messages ─────────────────────────────────────────────────────────

  Future<void> markRead(DingMessage m, {bool read = true}) async {
    if (m.read == read) return;
    if (read) {
      await _service.markRead(m.id);
    }
    m.read = read;
    notifyListeners();
  }

  Future<void> markAllRead() async {
    if (_messages.every((m) => m.read)) return;
    await _service.markAllRead();
    for (final m in _messages) {
      m.read = true;
    }
    notifyListeners();
  }

  Future<void> deleteMessage(DingMessage m) async {
    await _service.deleteNotification(m.id);
    _messages.removeWhere((x) => x.id == m.id);
    notifyListeners();
  }

  Future<void> clearAllMessages() async {
    for (final m in List<DingMessage>.from(_messages)) {
      await _service.deleteNotification(m.id);
    }
    _messages.clear();
    notifyListeners();
  }

  // ── 调度核心 ──────────────────────────────────────────────────────────

  Future<void> _tick({bool catchUp = false}) async {
    if (_ticking) return;
    _ticking = true;
    try {
      final now = DateTime.now();
      for (final t in List<DingTask>.from(_tasks)) {
        if (!t.enabled) continue;
        if (_running.contains(t.id)) continue;
        final next = t.nextRunAt;
        if (next == null) continue;
        if (next.isAfter(now)) continue;
        if (!catchUp) {
          if (now.difference(next).inMinutes > 5) {
            // 错过 > 5 分钟视为 stale，让服务端的 next_run_at 在下次 reportRun 后自动滚动；
            // 客户端这里跳过，避免雪崩。
            continue;
          }
        }
        // ignore: unawaited_futures
        _execute(t);
      }
    } finally {
      _ticking = false;
    }
  }

  Future<DingMessage?> _execute(DingTask t, {bool manual = false}) async {
    _running.add(t.id);
    notifyListeners();

    final startedAt = DateTime.now();
    String content = '';
    String error = '';
    String status = 'success';
    try {
      final result = await _chat.executeOneShot(
        prompt: t.prompt,
        personaId: t.personaId,
        withTools: true,
      );
      content = result.content;
      if (content.isEmpty) {
        content = '（模型返回为空）';
      }
    } catch (e) {
      status = 'failed';
      error = e.toString();
      content = '执行失败：$e';
    }

    final durationMs = DateTime.now().difference(startedAt).inMilliseconds;

    DingMessage? msg;
    try {
      final r = await _service.reportRun(
        t.id,
        status: status,
        title: t.title + (status == 'failed' ? '（失败）' : ''),
        content: status == 'success' ? content : '',
        error: status == 'failed' ? error : '',
        durationMs: durationMs,
        startedAt: startedAt,
      );
      msg = r.notification;
      if (msg != null) {
        _messages.insert(0, msg);
      }
    } catch (e) {
      _lastError = '上传执行结果失败：$e';
    }

    // 服务端会更新 last_run_at / next_run_at；本地刷一次 task
    try {
      final fresh = await _service.listTasks();
      _tasks
        ..clear()
        ..addAll(fresh);
    } catch (_) {}

    _running.remove(t.id);
    notifyListeners();
    return msg;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}
