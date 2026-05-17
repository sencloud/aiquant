import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// DING 定时任务定义。
///
/// 调度规则用字符串编码，简单、易持久化、易扩展：
/// - "daily:HH:mm"          — 每天 HH:mm 跑一次
/// - "weekly:N:HH:mm"        — 每周第 N 天 (1=周一 ... 7=周日)
/// - "interval:M"            — 每 M 分钟跑一次（M >= 5）
class DingTask extends HiveObject {
  String id;
  String title;
  String prompt;
  String personaId;
  String schedule;
  bool enabled;
  DateTime createdAt;
  DateTime? lastRunAt;
  DateTime? nextRunAt;

  DingTask({
    String? id,
    required this.title,
    required this.prompt,
    this.personaId = 'default',
    required this.schedule,
    this.enabled = true,
    DateTime? createdAt,
    this.lastRunAt,
    this.nextRunAt,
  })  : id = id ?? _uuid.v4(),
        createdAt = createdAt ?? DateTime.now();

  /// 友好展示文案，例如 "每天 09:30"。
  String describeSchedule() => DingScheduleCodec.describe(schedule);

  /// 计算下一次触发时间。基准时间 [from] 默认是当前时间。
  DateTime? computeNextFireTime({DateTime? from}) {
    return DingScheduleCodec.nextFireTime(schedule, from: from ?? DateTime.now());
  }
}

class DingTaskAdapter extends TypeAdapter<DingTask> {
  @override
  final int typeId = 10;

  @override
  DingTask read(BinaryReader reader) {
    final n = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < n; i++) reader.readByte(): reader.read(),
    };
    return DingTask(
      id: fields[0] as String,
      title: fields[1] as String,
      prompt: fields[2] as String,
      personaId: fields[3] as String? ?? 'default',
      schedule: fields[4] as String,
      enabled: fields[5] as bool? ?? true,
      createdAt: fields[6] as DateTime,
      lastRunAt: fields[7] as DateTime?,
      nextRunAt: fields[8] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, DingTask obj) {
    writer
      ..writeByte(9)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.prompt)
      ..writeByte(3)
      ..write(obj.personaId)
      ..writeByte(4)
      ..write(obj.schedule)
      ..writeByte(5)
      ..write(obj.enabled)
      ..writeByte(6)
      ..write(obj.createdAt)
      ..writeByte(7)
      ..write(obj.lastRunAt)
      ..writeByte(8)
      ..write(obj.nextRunAt);
  }
}

/// DING 消息：定时任务执行后产出的"邮件"。
class DingMessage extends HiveObject {
  String id;
  String taskId;
  String taskTitle;
  String content; // markdown
  String? error;
  DateTime createdAt;
  bool read;

  DingMessage({
    String? id,
    required this.taskId,
    required this.taskTitle,
    required this.content,
    this.error,
    DateTime? createdAt,
    this.read = false,
  })  : id = id ?? _uuid.v4(),
        createdAt = createdAt ?? DateTime.now();

  bool get hasError => error != null && error!.isNotEmpty;
}

class DingMessageAdapter extends TypeAdapter<DingMessage> {
  @override
  final int typeId = 11;

  @override
  DingMessage read(BinaryReader reader) {
    final n = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < n; i++) reader.readByte(): reader.read(),
    };
    return DingMessage(
      id: fields[0] as String,
      taskId: fields[1] as String,
      taskTitle: fields[2] as String,
      content: fields[3] as String,
      error: fields[4] as String?,
      createdAt: fields[5] as DateTime,
      read: fields[6] as bool? ?? false,
    );
  }

  @override
  void write(BinaryWriter writer, DingMessage obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.taskId)
      ..writeByte(2)
      ..write(obj.taskTitle)
      ..writeByte(3)
      ..write(obj.content)
      ..writeByte(4)
      ..write(obj.error)
      ..writeByte(5)
      ..write(obj.createdAt)
      ..writeByte(6)
      ..write(obj.read);
  }
}

/// 调度字符串的解析、描述与下次触发时间计算。
class DingScheduleCodec {
  /// 编码 "daily:HH:mm"。
  static String daily(int hour, int minute) =>
      'daily:${_two(hour)}:${_two(minute)}';

  /// 编码 "weekly:N:HH:mm"，N=1..7（1=周一）。
  static String weekly(int weekday, int hour, int minute) =>
      'weekly:$weekday:${_two(hour)}:${_two(minute)}';

  /// 编码 "interval:M" 分钟。
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

  /// 计算 [schedule] 在 [from] 之后的下一次触发时间。
  /// 严格大于 [from] —— "现在" 不视为 "下次"。
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
        // Dart: 1=Mon ... 7=Sun
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
