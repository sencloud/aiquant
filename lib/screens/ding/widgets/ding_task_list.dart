import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../models/ding.dart';
import '../../../models/persona.dart';
import '../../../state/ding_state.dart';
import '../../../theme/app_theme.dart';
import 'ding_task_editor.dart';

class DingTaskList extends StatelessWidget {
  const DingTaskList({super.key});

  @override
  Widget build(BuildContext context) {
    final st = context.watch<DingState>();
    final tasks = st.tasks;
    if (tasks.isEmpty) return const _Empty();

    final df = DateFormat('MM-dd HH:mm');

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
      itemCount: tasks.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final t = tasks[i];
        final persona = Personas.byId(t.personaId);
        final running = st.isRunning(t.id);
        return Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: persona.color.withValues(alpha: 0.18),
                      child: Icon(persona.icon, size: 16, color: persona.color),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800)),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(Icons.schedule,
                                  size: 11, color: AppColors.textTertiary),
                              const SizedBox(width: 3),
                              Text(t.describeSchedule(),
                                  style: TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 11)),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: persona.color.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                                child: Text(persona.displayName,
                                    style: TextStyle(
                                        color: persona.color,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: t.enabled,
                      activeColor: AppColors.amber,
                      onChanged: (v) =>
                          context.read<DingState>().setEnabled(t, v),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  t.prompt,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                      height: 1.5),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          if (t.lastRunAt != null)
                            _stamp('上次 ${df.format(t.lastRunAt!)}'),
                          if (t.enabled && t.nextRunAt != null)
                            _stamp('下次 ${df.format(t.nextRunAt!)}',
                                color: AppColors.amber),
                          if (running) _stamp('执行中…', color: AppColors.info),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: '立即执行',
                      icon: running
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: AppColors.amber))
                          : const Icon(Icons.play_arrow, size: 18),
                      onPressed:
                          running ? null : () => _runNow(context, t),
                    ),
                    IconButton(
                      tooltip: '编辑',
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      onPressed: () =>
                          DingTaskEditor.show(context, existing: t),
                    ),
                    IconButton(
                      tooltip: '删除',
                      icon: const Icon(Icons.delete_outline,
                          size: 16, color: AppColors.danger),
                      onPressed: () => _confirmDelete(context, t),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _stamp(String text, {Color? color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: color ?? AppColors.borderDim),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Text(text,
          style: TextStyle(
              color: color ?? AppColors.textTertiary,
              fontSize: 10,
              fontWeight: FontWeight.w700)),
    );
  }

  void _runNow(BuildContext context, DingTask t) async {
    final st = context.read<DingState>();
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(content: Text('已开始执行：${t.title}')),
    );
    await st.runNow(t);
    if (!context.mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text('已生成新消息，可在收件箱查看：${t.title}')),
    );
  }

  void _confirmDelete(BuildContext context, DingTask t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除任务'),
        content: Text('确定删除 "${t.title}" 吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await context.read<DingState>().deleteTask(t);
    }
  }
}

class _Empty extends StatelessWidget {
  const _Empty();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.alarm_off,
                size: 56, color: AppColors.textTertiary),
            const SizedBox(height: 12),
            Text('还没有定时任务',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(
              '点击右下角"新建任务"，让 AI 在每天固定时间为你跑一次行情总结、'
              '资金面追踪、或自定义研究任务。',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: AppColors.textTertiary, fontSize: 11, height: 1.6),
            ),
          ],
        ),
      ),
    );
  }
}
