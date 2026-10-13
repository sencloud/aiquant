import 'dart:convert';

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../widgets/wk_kit.dart';
import '../../screens/hub/hub_screen.dart';
import '../storage/hive_setup.dart';
import 'topic_registry.dart';

/// 圈内「记录」：这个圈的第一手数据。
///
/// 「今天」那张卡的依据全部来自这里 —— 没有记录，判断就照实写「还没有判断」。
/// 第一版只存在本机（Hive 的 `app_prefs`，键 `topic_log_v1_<topicId>`）；
/// 服务端同步、以及「档案 → 该升级什么了」的回流留到下一版。
class TopicLogEntry {
  TopicLogEntry({
    required this.title,
    this.note = '',
    required this.at,
    this.start = false,
  });

  final String title;
  final String note;
  final DateTime at;

  /// 起算日记录：这个圈的「今天」用它算天数（咖啡的烘焙日、猫粮的开封日）。
  /// 只有它是**有类型**的，其余记录是自由文本 —— 判断不能从随意写的字里猜。
  final bool start;

  Map<String, dynamic> toJson() => {
        't': title,
        'n': note,
        'a': at.toIso8601String(),
        if (start) 's': true,
      };

  static TopicLogEntry? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final t = raw['t'];
    if (t is! String || t.isEmpty) return null;
    final n = raw['n'];
    return TopicLogEntry(
      title: t,
      note: n is String ? n : '',
      at: DateTime.tryParse('${raw['a']}') ?? DateTime.now(),
      start: raw['s'] == true,
    );
  }
}

String _logKey(String topicId) => 'topic_log_v1_$topicId';

/// 读某个圈的记录（按时间倒序）。存储坏掉时返回空表，不抛。
List<TopicLogEntry> loadTopicLog(String topicId) {
  final raw = prefsBox.get(_logKey(topicId));
  if (raw is! String || raw.isEmpty) return const [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    final out = <TopicLogEntry>[];
    for (final e in decoded) {
      final entry = TopicLogEntry.fromJson(e);
      if (entry != null) out.add(entry);
    }
    out.sort((a, b) => b.at.compareTo(a.at));
    return out;
  } catch (_) {
    return const [];
  }
}

Future<void> saveTopicLog(String topicId, List<TopicLogEntry> entries) =>
    prefsBox.put(
        _logKey(topicId), jsonEncode([for (final e in entries) e.toJson()]));

class TopicLogScreen extends StatefulWidget {
  const TopicLogScreen({super.key});

  @override
  State<TopicLogScreen> createState() => _TopicLogScreenState();
}

class _TopicLogScreenState extends State<TopicLogScreen> {
  late String _topicId;
  List<TopicLogEntry> _entries = const [];

  @override
  void initState() {
    super.initState();
    _topicId = topicOf(context).id;
    _entries = loadTopicLog(_topicId);
  }

  Future<void> _add() async {
    final entry = await showModalBottomSheet<TopicLogEntry>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bgBase,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (_) =>
          _LogEditor(startLabel: topicOf(context).window?.startLabel),
    );
    if (entry == null) return;
    setState(() => _entries = [entry, ..._entries]);
    await saveTopicLog(_topicId, _entries);
  }

  Future<void> _open(TopicLogEntry entry) async {
    final remove = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.bgBase,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpace.lg, AppSpace.lg, AppSpace.lg, AppSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(entry.title, style: AppType.title),
            const SizedBox(height: AppSpace.xs),
            Text(_fmt(entry.at),
                style: AppType.micro.copyWith(color: AppColors.textTertiary)),
            if (entry.note.isNotEmpty) ...[
              const SizedBox(height: AppSpace.sm),
              Text(entry.note, style: AppType.read),
            ],
            const SizedBox(height: AppSpace.lg),
            WkRow(
              icon: Icons.delete_outline_rounded,
              title: '删掉这条',
              destructive: true,
              onTap: () => Navigator.of(ctx).pop(true),
            ),
          ],
        ),
      ),
    );
    if (remove != true) return;
    setState(() => _entries = [..._entries]..remove(entry));
    await saveTopicLog(_topicId, _entries);
  }

  @override
  Widget build(BuildContext context) {
    final pack = topicOf(context, listen: true);
    return WkPage(
      title: '记录',
      actions: [
        const HubEntryAction(),
        IconButton(
          key: const ValueKey('log-add'),
          icon: const Icon(Icons.add_rounded),
          tooltip: '记一条',
          color: AppColors.amber,
          onPressed: _add,
        ),
      ],
      child: _entries.isEmpty
          ? WkEmpty(
              icon: Icons.edit_note_rounded,
              title: '还没有记录',
              hint: '记第一条之后，这个圈的「今天」就开始有依据了。',
              action: WkPrimaryButton(label: '记第一条', onPressed: _add),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                  AppSpace.gutter, AppSpace.sm, AppSpace.gutter, AppSpace.xxl),
              children: [
                WkGroup(
                  header: '${pack.name} · ${_entries.length} 条',
                  children: [
                    for (final e in _entries)
                      WkRow(
                        key: ValueKey('log-${e.at.toIso8601String()}'),
                        title: e.title,
                        subtitle: e.note.isEmpty
                            ? _fmt(e.at)
                            : '${_fmt(e.at)} · ${e.note}',
                        onTap: () => _open(e),
                      ),
                  ],
                ),
                const WkNote(
                  text: '记录只存在这台设备上，也只在这个圈里可见。'
                      '「今天」的判断只读它，不会为了好看替你补一个数。',
                ),
              ],
            ),
    );
  }
}

class _LogEditor extends StatefulWidget {
  const _LogEditor({this.startLabel});

  /// 这个圈的「起算日」叫什么（烘焙日 / 开封日）；null = 这个圈没有起算日。
  final String? startLabel;

  @override
  State<_LogEditor> createState() => _LogEditorState();
}

class _LogEditorState extends State<_LogEditor> {
  final _title = TextEditingController();
  final _note = TextEditingController();
  bool _start = false;

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          AppSpace.lg, AppSpace.lg, AppSpace.lg, AppSpace.xl + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('记一条', style: AppType.title),
          const SizedBox(height: AppSpace.md),
          TextField(
            key: const ValueKey('log-title'),
            controller: _title,
            autofocus: true,
            style: AppType.body,
            decoration: const InputDecoration(
              hintText: '一句话说清这条是什么（例：茉香日晒 200g，烘焙 10-01）',
            ),
          ),
          const SizedBox(height: AppSpace.md),
          TextField(
            key: const ValueKey('log-note'),
            controller: _note,
            style: AppType.body,
            decoration: const InputDecoration(hintText: '补充（可留空）'),
          ),
          if (widget.startLabel != null) ...[
            const SizedBox(height: AppSpace.sm),
            InkWell(
              key: const ValueKey('log-start'),
              onTap: () => setState(() => _start = !_start),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
                child: Row(
                  children: [
                    Icon(
                      _start
                          ? Icons.check_box_rounded
                          : Icons.check_box_outline_blank_rounded,
                      size: 20,
                      color: _start ? AppColors.amber : AppColors.textTertiary,
                    ),
                    const SizedBox(width: AppSpace.sm),
                    Expanded(
                      child: Text(
                        '这条是${widget.startLabel}，「今天」用它算天数',
                        style: AppType.caption
                            .copyWith(color: AppColors.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpace.lg),
          WkPrimaryButton(
            label: '保存',
            onPressed: () {
              final t = _title.text.trim();
              if (t.isEmpty) return;
              Navigator.of(context).pop(TopicLogEntry(
                title: t,
                note: _note.text.trim(),
                at: DateTime.now(),
                start: _start,
              ));
            },
          ),
        ],
      ),
    );
  }
}

String _fmt(DateTime at) {
  String two(int v) => v < 10 ? '0$v' : '$v';
  return '${at.year}-${two(at.month)}-${two(at.day)} ${two(at.hour)}:${two(at.minute)}';
}
