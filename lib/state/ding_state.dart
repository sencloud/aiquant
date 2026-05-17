import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/storage/hive_setup.dart';
import '../models/ding.dart';
import 'chat_state.dart';

/// DING：定时任务 + 消息聚合。
///
/// 移动端没有真后台 cron，因此本调度器走"前台 + 启动追赶"的策略：
/// - App 在前台时每 60s 扫一次任务列表，到点的任务立即执行；
/// - App 启动 / 从后台回到前台时，对所有 nextRunAt < now 的任务做"补跑"
///   （只补跑一次最近一次窗口，避免久不打开 App 后产生雪崩）；
/// - 任务跑完后调用 ChatState.executeOneShot 拿到 markdown 结果，写入
///   DingMessage 收件箱并 notifyListeners。
class DingState extends ChangeNotifier {
  DingState({required ChatState chat}) : _chat = chat;

  final ChatState _chat;
  Timer? _ticker;
  bool _ticking = false;
  // 正在执行的任务 id（防止 tick 重叠）
  final Set<String> _running = {};

  List<DingTask> get tasks {
    final list = dingTasksBox.values.toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return list;
  }

  List<DingMessage> get messages {
    final list = dingMessagesBox.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  int get unreadCount => dingMessagesBox.values.where((m) => !m.read).length;

  Set<String> get runningTaskIds => Set.unmodifiable(_running);
  bool isRunning(String taskId) => _running.contains(taskId);

  Future<void> bootstrap() async {
    // 给所有没有 nextRunAt 的任务计算一次（旧任务向前兼容）
    for (final t in dingTasksBox.values) {
      t.nextRunAt ??= t.computeNextFireTime();
      await t.save();
    }
    // 启动后立即跑一次"追赶"，让久违打开 App 的用户能看到当日消息
    _tick(catchUp: true);
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 60), (_) => _tick());
    notifyListeners();
  }

  Future<DingTask> createTask({
    required String title,
    required String prompt,
    required String schedule,
    String personaId = 'default',
    bool enabled = true,
  }) async {
    final t = DingTask(
      title: title,
      prompt: prompt,
      schedule: schedule,
      personaId: personaId,
      enabled: enabled,
    );
    t.nextRunAt = t.computeNextFireTime();
    await dingTasksBox.put(t.id, t);
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
    if (title != null) t.title = title;
    if (prompt != null) t.prompt = prompt;
    if (personaId != null) t.personaId = personaId;
    if (schedule != null) t.schedule = schedule;
    if (enabled != null) t.enabled = enabled;
    t.nextRunAt = t.computeNextFireTime();
    await t.save();
    notifyListeners();
  }

  Future<void> setEnabled(DingTask t, bool enabled) async {
    t.enabled = enabled;
    t.nextRunAt = enabled ? t.computeNextFireTime() : null;
    await t.save();
    notifyListeners();
  }

  Future<void> deleteTask(DingTask t) async {
    await t.delete();
    notifyListeners();
  }

  /// 立即手动执行某个任务（不影响 nextRunAt）。
  Future<DingMessage> runNow(DingTask t) async {
    return _execute(t, manual: true);
  }

  Future<void> markRead(DingMessage m, {bool read = true}) async {
    if (m.read == read) return;
    m.read = read;
    await m.save();
    notifyListeners();
  }

  Future<void> markAllRead() async {
    var changed = false;
    for (final m in dingMessagesBox.values) {
      if (!m.read) {
        m.read = true;
        await m.save();
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  Future<void> deleteMessage(DingMessage m) async {
    await m.delete();
    notifyListeners();
  }

  Future<void> clearAllMessages() async {
    await dingMessagesBox.clear();
    notifyListeners();
  }

  /// 由外部（HomeScreen lifecycle / 手动刷新按钮）触发的"追赶"。
  void resumeFromBackground() => _tick(catchUp: true);

  // ── 调度核心 ─────────────────────────────────────────────────────────

  Future<void> _tick({bool catchUp = false}) async {
    if (_ticking) return;
    _ticking = true;
    try {
      final now = DateTime.now();
      for (final t in tasks) {
        if (!t.enabled) continue;
        if (_running.contains(t.id)) continue;
        final next = t.nextRunAt;
        if (next == null) {
          t.nextRunAt = t.computeNextFireTime(from: now);
          await t.save();
          continue;
        }
        if (next.isAfter(now)) continue;
        if (!catchUp) {
          // 普通 tick：到点严格满足才跑
          if (now.difference(next).inMinutes > 5) {
            // 错过 > 5 分钟视为 stale，下次窗口再跑
            t.nextRunAt = t.computeNextFireTime(from: now);
            await t.save();
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

  Future<DingMessage> _execute(DingTask t, {bool manual = false}) async {
    _running.add(t.id);
    notifyListeners();
    DingMessage msg;
    try {
      final result = await _chat.executeOneShot(
        prompt: t.prompt,
        personaId: t.personaId,
        withTools: true,
      );
      msg = DingMessage(
        taskId: t.id,
        taskTitle: t.title,
        content: result.content.isEmpty ? '（模型返回为空）' : result.content,
      );
    } catch (e) {
      msg = DingMessage(
        taskId: t.id,
        taskTitle: t.title,
        content: '执行失败：$e',
        error: e.toString(),
      );
    }
    await dingMessagesBox.put(msg.id, msg);

    t.lastRunAt = DateTime.now();
    t.nextRunAt = t.computeNextFireTime(from: t.lastRunAt);
    await t.save();

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
