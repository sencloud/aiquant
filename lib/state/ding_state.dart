import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/ding.dart';
import '../services/ding_service.dart';
import '../services/push_registration_service.dart';

/// DingState — 服务端为唯一真源 + 唯一 LLM 执行路径。
///
/// 客户端只做：
///  - 拉取 / 缓存 tasks 与 notifications；
///  - 前台 60s ticker 与"从后台回到前台"的 catchUp，把到期但因离线没跑的任务
///    通过 [DingService.runNow] 触发服务端立即执行（POST /v1/ding/tasks/{uuid}/run-now）。
///
/// 客户端不再持有任何 LLM key、不再本地驱动 tool calling loop。
class DingState extends ChangeNotifier {
  DingState({DingService? service})
      : _service = service ?? DingService();

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

  Future<void> bootstrap() async {
    if (_bootstrapped) return;
    _bootstrapped = true;
    await refreshAll(catchUp: true);
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 60), (_) => _tick());
  }

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

  Future<void> refreshAll({bool catchUp = false}) async {
    await Future.wait([
      _refreshTasks(),
      _refreshFirstPage(),
    ]);
    if (catchUp) {
      await _tick(catchUp: true);
    }
    await _syncBadgeWithUnread();
  }

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
    return _execute(t);
  }

  // ── Messages ─────────────────────────────────────────────────────────

  Future<void> markRead(DingMessage m, {bool read = true}) async {
    if (m.read == read) return;
    if (read) {
      await _service.markRead(m.id);
    }
    m.read = read;
    notifyListeners();
    await _syncBadgeWithUnread();
  }

  Future<void> markAllRead() async {
    if (_messages.every((m) => m.read)) return;
    await _service.markAllRead();
    for (final m in _messages) {
      m.read = true;
    }
    notifyListeners();
    await _syncBadgeWithUnread();
  }

  /// 把当前未读数同步到 iOS 桌面图标的红点角标。
  /// 调用时机：refresh / markRead / markAllRead / delete 等 unreadCount 可能变化处。
  Future<void> _syncBadgeWithUnread() async {
    await PushRegistrationService.instance.setBadge(unreadCount);
  }

  Future<void> deleteMessage(DingMessage m) async {
    await _service.deleteNotification(m.id);
    _messages.removeWhere((x) => x.id == m.id);
    notifyListeners();
    await _syncBadgeWithUnread();
  }

  /// 批量删除一组消息（收件箱里折叠历史条用）。
  ///
  /// 服务端目前没有 batch API，这里按单条顺序删；失败的条会从入参集合中被跳过，
  /// 整体不抛错，避免删了一半之后 UI 卡死。
  Future<int> deleteMessages(Iterable<DingMessage> msgs) async {
    final ids = <String>{};
    for (final m in msgs) {
      try {
        await _service.deleteNotification(m.id);
        ids.add(m.id);
      } catch (_) {
        // 单条失败不阻断其它删除
      }
    }
    if (ids.isEmpty) return 0;
    _messages.removeWhere((x) => ids.contains(x.id));
    notifyListeners();
    await _syncBadgeWithUnread();
    return ids.length;
  }

  Future<void> clearAllMessages() async {
    for (final m in List<DingMessage>.from(_messages)) {
      await _service.deleteNotification(m.id);
    }
    _messages.clear();
    notifyListeners();
    await _syncBadgeWithUnread();
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
            // 错过 > 5 分钟：留给服务端 scheduler 跑，避免雪崩
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

  Future<DingMessage?> _execute(DingTask t) async {
    _running.add(t.id);
    notifyListeners();

    DingMessage? msg;
    try {
      final r = await _service.runNow(t.id);
      msg = r.notification;
      if (msg != null) {
        _messages.insert(0, msg);
      }
    } catch (e) {
      _lastError = '执行失败：$e';
    }

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
