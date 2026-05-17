import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/ding.dart';
import '../../../models/persona.dart';
import '../../../state/ding_state.dart';
import '../../../theme/app_theme.dart';

/// 创建 / 编辑 DING 定时任务的弹窗。
class DingTaskEditor extends StatefulWidget {
  const DingTaskEditor({
    super.key,
    this.existing,
    this.initialPrompt,
    this.initialTitle,
    this.initialPersonaId,
  });

  final DingTask? existing;
  final String? initialPrompt;
  final String? initialTitle;
  final String? initialPersonaId;

  static Future<void> show(
    BuildContext context, {
    DingTask? existing,
    String? initialPrompt,
    String? initialTitle,
    String? initialPersonaId,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => DingTaskEditor(
        existing: existing,
        initialPrompt: initialPrompt,
        initialTitle: initialTitle,
        initialPersonaId: initialPersonaId,
      ),
    );
  }

  @override
  State<DingTaskEditor> createState() => _DingTaskEditorState();
}

enum _Freq { daily, weekly, interval }

class _DingTaskEditorState extends State<DingTaskEditor> {
  late final TextEditingController _title;
  late final TextEditingController _prompt;
  late String _personaId;
  late _Freq _freq;
  TimeOfDay _time = const TimeOfDay(hour: 9, minute: 30);
  int _weekday = 1; // 1=周一
  int _intervalMinutes = 60;
  late bool _enabled;

  @override
  void initState() {
    super.initState();
    final ex = widget.existing;
    _title = TextEditingController(
        text: ex?.title ?? widget.initialTitle ?? '今日行情总结');
    _prompt = TextEditingController(
        text: ex?.prompt ??
            widget.initialPrompt ??
            '基于今天 A 股 / ETF / 期货市场，给我一份结构化的行情总结：'
                '主要指数表现、领涨/领跌行业、北向资金/两融、大事件以及对后市的关注点。');
    _personaId = ex?.personaId ?? widget.initialPersonaId ?? Personas.defaultId;
    _enabled = ex?.enabled ?? true;

    final sched = ex?.schedule ?? DingScheduleCodec.daily(9, 30);
    final parts = sched.split(':');
    switch (parts[0]) {
      case 'weekly':
        _freq = _Freq.weekly;
        if (parts.length >= 4) {
          _weekday = int.tryParse(parts[1]) ?? 1;
          _time = TimeOfDay(
              hour: int.tryParse(parts[2]) ?? 9,
              minute: int.tryParse(parts[3]) ?? 30);
        }
        break;
      case 'interval':
        _freq = _Freq.interval;
        if (parts.length >= 2) {
          _intervalMinutes = int.tryParse(parts[1]) ?? 60;
        }
        break;
      default:
        _freq = _Freq.daily;
        if (parts.length >= 3) {
          _time = TimeOfDay(
              hour: int.tryParse(parts[1]) ?? 9,
              minute: int.tryParse(parts[2]) ?? 30);
        }
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _prompt.dispose();
    super.dispose();
  }

  String _composeSchedule() {
    switch (_freq) {
      case _Freq.daily:
        return DingScheduleCodec.daily(_time.hour, _time.minute);
      case _Freq.weekly:
        return DingScheduleCodec.weekly(_weekday, _time.hour, _time.minute);
      case _Freq.interval:
        return DingScheduleCodec.interval(_intervalMinutes);
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time,
    );
    if (picked != null && mounted) {
      setState(() => _time = picked);
    }
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    final prompt = _prompt.text.trim();
    if (title.isEmpty || prompt.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('任务标题与执行 Prompt 都不能为空'),
      ));
      return;
    }
    final st = context.read<DingState>();
    final navigator = Navigator.of(context);
    final schedule = _composeSchedule();
    if (widget.existing == null) {
      await st.createTask(
        title: title,
        prompt: prompt,
        schedule: schedule,
        personaId: _personaId,
        enabled: _enabled,
      );
    } else {
      await st.updateTask(
        widget.existing!,
        title: title,
        prompt: prompt,
        schedule: schedule,
        personaId: _personaId,
        enabled: _enabled,
      );
    }
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return Dialog(
      backgroundColor: AppColors.bgSurface,
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 720),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(isEdit ? '编辑 DING 任务' : '新建 DING 任务',
                        style: const TextStyle(
                            color: AppColors.amber,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _title,
                decoration: const InputDecoration(
                  labelText: '任务标题',
                  hintText: '如：今日行情总结 / 北向资金日报 …',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _prompt,
                minLines: 4,
                maxLines: 8,
                decoration: const InputDecoration(
                  labelText: '执行 Prompt（每次任务发送给 AI 的指令）',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 16),
              _label('AI 角色'),
              const SizedBox(height: 6),
              _personaPicker(),
              const SizedBox(height: 16),
              _label('调度规则'),
              const SizedBox(height: 6),
              _freqPicker(),
              const SizedBox(height: 8),
              _scheduleDetail(),
              const SizedBox(height: 16),
              Row(
                children: [
                  Switch(
                    value: _enabled,
                    activeColor: AppColors.amber,
                    onChanged: (v) => setState(() => _enabled = v),
                  ),
                  const SizedBox(width: 6),
                  Text(_enabled ? '已启用，到点自动执行' : '已暂停（不自动执行）',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 12)),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    icon: Icon(isEdit ? Icons.save : Icons.add_alarm,
                        size: 14),
                    label: Text(isEdit ? '保存' : '创建任务'),
                    onPressed: _save,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Text(text,
      style: TextStyle(
          color: AppColors.textTertiary,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6));

  Widget _personaPicker() {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final p in Personas.all)
          GestureDetector(
            onTap: () => setState(() => _personaId = p.id),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: _personaId == p.id
                    ? p.color.withValues(alpha: 0.18)
                    : AppColors.bgRaised,
                border: Border.all(
                    color: _personaId == p.id ? p.color : AppColors.borderDim),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(p.icon, size: 12, color: p.color),
                  const SizedBox(width: 4),
                  Text(p.displayName,
                      style: TextStyle(
                          color: _personaId == p.id
                              ? p.color
                              : AppColors.textPrimary,
                          fontSize: 11,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _freqPicker() {
    return Row(
      children: [
        for (final entry in [
          (_Freq.daily, '每天'),
          (_Freq.weekly, '每周'),
          (_Freq.interval, '间隔'),
        ])
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              label: Text(entry.$2,
                  style: TextStyle(
                      color: _freq == entry.$1
                          ? Colors.black
                          : AppColors.textPrimary,
                      fontSize: 11,
                      fontWeight: FontWeight.w800)),
              selected: _freq == entry.$1,
              selectedColor: AppColors.amber,
              backgroundColor: AppColors.bgRaised,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(3),
                side: BorderSide(color: AppColors.borderDim),
              ),
              onSelected: (_) => setState(() => _freq = entry.$1),
            ),
          ),
      ],
    );
  }

  Widget _scheduleDetail() {
    switch (_freq) {
      case _Freq.daily:
        return _timeRow();
      case _Freq.weekly:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 4,
              children: [
                for (var i = 1; i <= 7; i++)
                  ChoiceChip(
                    label: Text(_wdShort(i),
                        style: TextStyle(
                            color: _weekday == i
                                ? Colors.black
                                : AppColors.textPrimary,
                            fontSize: 11)),
                    selected: _weekday == i,
                    selectedColor: AppColors.amber,
                    backgroundColor: AppColors.bgRaised,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(3),
                      side: BorderSide(color: AppColors.borderDim),
                    ),
                    onSelected: (_) => setState(() => _weekday = i),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            _timeRow(),
          ],
        );
      case _Freq.interval:
        return Row(
          children: [
            Text('每 ',
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 12)),
            DropdownButton<int>(
              value: _intervalMinutes,
              dropdownColor: AppColors.bgRaised,
              items: const [15, 30, 60, 120, 180, 360, 720]
                  .map((m) => DropdownMenuItem(
                        value: m,
                        child: Text(m % 60 == 0
                            ? '${m ~/ 60} 小时'
                            : '$m 分钟'),
                      ))
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _intervalMinutes = v);
              },
            ),
            const SizedBox(width: 8),
            Text('运行一次',
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 12)),
          ],
        );
    }
  }

  Widget _timeRow() {
    final t = _time.format(context);
    return Row(
      children: [
        Text('时间：',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        OutlinedButton.icon(
          icon: const Icon(Icons.access_time, size: 14),
          label: Text(t),
          onPressed: _pickTime,
        ),
      ],
    );
  }

  String _wdShort(int d) {
    const names = ['一', '二', '三', '四', '五', '六', '日'];
    return '周${names[d - 1]}';
  }
}
