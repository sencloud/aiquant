/// DING 数据模型 — 服务端是唯一真源，本地仅作内存缓存。
library;

/// DingTask：定时任务定义。
///
/// schedule 字符串约定（与 backend `internal/ding/schedule.go` 完全一致）：
/// - "daily:HH:mm"          每天 HH:mm 跑一次
/// - "weekly:N:HH:mm"        每周第 N 天 (1=周一 ... 7=周日)
/// - "interval:M"            每 M 分钟跑一次（M >= 5）
class DingTask {
  DingTask({
    required this.id,
    required this.title,
    required this.prompt,
    required this.personaId,
    required this.schedule,
    required this.enabled,
    required this.createdAt,
    this.lastRunAt,
    this.nextRunAt,
    this.costCreditsPerRun = 5,
  });

  /// 服务端 uuid（`ding_tasks.uuid`），与之前的本地 id 保持同名以兼容 UI 代码。
  String id;
  String title;
  String prompt;
  String personaId;
  String schedule;
  bool enabled;
  DateTime createdAt;
  DateTime? lastRunAt;
  DateTime? nextRunAt;
  int costCreditsPerRun;

  String describeSchedule() => DingScheduleCodec.describe(schedule);

  factory DingTask.fromJson(Map<String, dynamic> j) {
    DateTime? msToTime(Object? v) {
      if (v is num) return DateTime.fromMillisecondsSinceEpoch(v.toInt());
      return null;
    }

    return DingTask(
      id: j['uuid'] as String,
      title: j['title'] as String,
      prompt: j['prompt'] as String,
      personaId: (j['persona_id'] as String?) ?? 'default',
      schedule: j['schedule'] as String,
      enabled: (j['enabled'] as bool?) ?? true,
      createdAt:
          DateTime.fromMillisecondsSinceEpoch((j['created_at'] as num).toInt()),
      lastRunAt: msToTime(j['last_run_at']),
      nextRunAt: msToTime(j['next_run_at']),
      costCreditsPerRun:
          (j['cost_credits_per_run'] as num?)?.toInt() ?? 5,
    );
  }

  /// 本地预测下次触发时间，用于在 server 还没返回 next_run_at 之前给 UI 展示。
  DateTime? computeNextFireTime({DateTime? from}) {
    return DingScheduleCodec.nextFireTime(schedule, from: from ?? DateTime.now());
  }
}

/// DingMessage：通知收件箱里的一条"邮件"。对应 backend `notifications` 表。
class DingMessage {
  DingMessage({
    required this.id,
    required this.taskId,
    required this.taskTitle,
    required this.content,
    this.error,
    required this.createdAt,
    this.read = false,
  });

  /// 服务端 uuid。
  final String id;
  final String taskId;
  final String taskTitle;
  final String content;
  final String? error;
  final DateTime createdAt;
  bool read;

  bool get hasError => error != null && error!.isNotEmpty;

  factory DingMessage.fromJson(Map<String, dynamic> j) {
    final body = (j['payload'] as String?) ?? '';
    final brief = (j['body_brief'] as String?) ?? '';
    final isError = (j['title'] as String? ?? '').contains('（失败）');
    return DingMessage(
      id: j['uuid'] as String,
      taskId: (j['ref_id'] as String?) ?? '',
      taskTitle: (j['title'] as String?) ?? '',
      content: body.isNotEmpty ? body : brief,
      error: isError ? body : null,
      createdAt:
          DateTime.fromMillisecondsSinceEpoch((j['created_at'] as num).toInt()),
      read: (j['read'] as bool?) ?? false,
    );
  }
}

/// schedule 字符串的解析、描述与下次触发时间计算（与 backend 对齐）。
class DingScheduleCodec {
  static String daily(int hour, int minute) =>
      'daily:${_two(hour)}:${_two(minute)}';

  static String weekly(int weekday, int hour, int minute) =>
      'weekly:$weekday:${_two(hour)}:${_two(minute)}';

  static String interval(int minutes) => 'interval:$minutes';

  static String describe(String schedule) {
    final parts = schedule.split(':');
    if (parts.isEmpty) return schedule;
    switch (parts[0]) {
      case 'daily':
        if (parts.length >= 3) return '每天 ${parts[1]}:${parts[2]}';
        return '每天';
      case 'weekly':
        if (parts.length >= 4) {
          return '每${_weekdayCn(int.tryParse(parts[1]) ?? 1)} ${parts[2]}:${parts[3]}';
        }
        return '每周';
      case 'interval':
        if (parts.length >= 2) {
          final m = int.tryParse(parts[1]) ?? 60;
          if (m % 60 == 0) return '每 ${m ~/ 60} 小时';
          return '每 $m 分钟';
        }
        return '间隔';
      default:
        return schedule;
    }
  }

  static DateTime? nextFireTime(String schedule, {required DateTime from}) {
    final parts = schedule.split(':');
    if (parts.isEmpty) return null;
    switch (parts[0]) {
      case 'daily':
        if (parts.length < 3) return null;
        final h = int.tryParse(parts[1]) ?? 0;
        final m = int.tryParse(parts[2]) ?? 0;
        var t = DateTime(from.year, from.month, from.day, h, m);
        if (!t.isAfter(from)) t = t.add(const Duration(days: 1));
        return t;
      case 'weekly':
        if (parts.length < 4) return null;
        final wd = int.tryParse(parts[1]) ?? 1;
        final h = int.tryParse(parts[2]) ?? 0;
        final m = int.tryParse(parts[3]) ?? 0;
        var t = DateTime(from.year, from.month, from.day, h, m);
        var diff = (wd - t.weekday) % 7;
        if (diff < 0) diff += 7;
        t = t.add(Duration(days: diff));
        if (!t.isAfter(from)) t = t.add(const Duration(days: 7));
        return t;
      case 'interval':
        if (parts.length < 2) return null;
        final mins = int.tryParse(parts[1]) ?? 60;
        return from.add(Duration(minutes: mins));
      default:
        return null;
    }
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  static String _weekdayCn(int d) {
    const names = ['一', '二', '三', '四', '五', '六', '日'];
    if (d < 1 || d > 7) return '日';
    return '周${names[d - 1]}';
  }
}
