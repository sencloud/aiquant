import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/ding_state.dart';
import '../../theme/app_theme.dart';
import 'widgets/ding_inbox.dart';
import 'widgets/ding_task_list.dart';
import 'widgets/ding_task_editor.dart';

/// DING tab：定时任务 + 信息聚合 + 消息推送展示。
class DingScreen extends StatefulWidget {
  const DingScreen({super.key});

  @override
  State<DingScreen> createState() => _DingScreenState();
}

class _DingScreenState extends State<DingScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _ctl = TabController(length: 2, vsync: this)
    ..addListener(_onTabChanged);

  void _onTabChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _ctl.removeListener(_onTabChanged);
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<DingState>();

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('DING'),
            const SizedBox(width: 6),
            if (st.unreadCount > 0)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: AppColors.danger,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${st.unreadCount}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w800),
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh, size: 18),
            onPressed: () => context.read<DingState>().resumeFromBackground(),
          ),
          IconButton(
            tooltip: '全部标记已读',
            icon: const Icon(Icons.mark_email_read_outlined, size: 18),
            onPressed:
                st.unreadCount == 0 ? null : () => st.markAllRead(),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(40),
          child: Container(
            color: AppColors.bgSurface,
            child: TabBar(
              controller: _ctl,
              indicatorColor: AppColors.amber,
              labelColor: AppColors.amber,
              unselectedLabelColor: AppColors.textSecondary,
              labelStyle:
                  const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
              unselectedLabelStyle: const TextStyle(fontSize: 12),
              tabs: [
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.markunread_mailbox_outlined,
                          size: 14),
                      const SizedBox(width: 4),
                      const Text('收件箱'),
                      if (st.unreadCount > 0) ...[
                        const SizedBox(width: 4),
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: AppColors.danger,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.alarm, size: 14),
                      SizedBox(width: 4),
                      Text('任务'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _ctl,
        children: const [DingInbox(), DingTaskList()],
      ),
      floatingActionButton: _ctl.index == 1
          ? FloatingActionButton.extended(
              backgroundColor: AppColors.amber,
              foregroundColor: Colors.black,
              icon: const Icon(Icons.add_alarm),
              label: const Text('新建任务'),
              onPressed: () => DingTaskEditor.show(context),
            )
          : null,
    );
  }
}
