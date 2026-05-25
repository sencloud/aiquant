import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/live.dart';
import '../../state/live_state.dart';
import '../../theme/app_theme.dart';
import 'live_session_detail_screen.dart';
import 'widgets/live_watch_add_sheet.dart';

/// AI 直播主页：[直播大厅] + [我的关注] 两个 tab。
///
/// 直播大厅 = 最近场次列表（按 scheduled_at desc）。
/// 我的关注 = 用户加过关注的股票；其将在下一场直播被自动纳入选股池。
class LiveScreen extends StatefulWidget {
  const LiveScreen({super.key});

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final s = context.read<LiveState>();
      s.refreshSessions();
      s.refreshWatch();
    });
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.live_tv, color: AppColors.amber, size: 18),
            SizedBox(width: 6),
            Text('AI 直播'),
          ],
        ),
        bottom: TabBar(
          controller: _tab,
          labelColor: AppColors.amber,
          indicatorColor: AppColors.amber,
          unselectedLabelColor: AppColors.textTertiary,
          tabs: const [
            Tab(text: '直播大厅'),
            Tab(text: '我的关注'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh, size: 18),
            onPressed: () {
              final s = context.read<LiveState>();
              s.refreshSessions();
              s.refreshWatch();
            },
          ),
        ],
      ),
      body: TabBarView(
        controller: _tab,
        children: const [
          _SessionsTab(),
          _WatchTab(),
        ],
      ),
      floatingActionButton: AnimatedBuilder(
        animation: _tab,
        builder: (context, _) {
          if (_tab.index != 1) return const SizedBox.shrink();
          return FloatingActionButton.extended(
            backgroundColor: AppColors.amber,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.add),
            label: const Text('加关注'),
            onPressed: () => LiveWatchAddSheet.show(context),
          );
        },
      ),
    );
  }
}

// ── 直播大厅 ──────────────────────────────────────────────────────────

class _SessionsTab extends StatelessWidget {
  const _SessionsTab();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LiveState>();
    if (s.loadingSessions && s.sessions.isEmpty) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (s.sessions.isEmpty) {
      return _emptyHint(
        '还没有直播场次',
        '今天 9:30/10:30/11:30/13:30/14:30/15:00 各一场，敬请等待。',
      );
    }
    return RefreshIndicator(
      onRefresh: () => context.read<LiveState>().refreshSessions(),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        itemCount: s.sessions.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) => _SessionCard(session: s.sessions[i]),
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({required this.session});
  final LiveSession session;

  @override
  Widget build(BuildContext context) {
    final dt = DateTime.fromMillisecondsSinceEpoch(session.scheduledAt);
    final hhmm = DateFormat('HH:mm').format(dt);
    final dateLabel = DateFormat('MM-dd').format(dt);

    Color statusColor;
    String statusLabel;
    IconData statusIcon;
    switch (session.status) {
      case 'done':
        statusColor = const Color(0xFF16a34a);
        statusLabel = '已生成';
        statusIcon = Icons.check_circle;
        break;
      case 'running':
        statusColor = AppColors.amber;
        statusLabel = '直播中';
        statusIcon = Icons.podcasts;
        break;
      case 'failed':
        statusColor = const Color(0xFFef4444);
        statusLabel = '失败';
        statusIcon = Icons.error;
        break;
      default:
        statusColor = AppColors.textTertiary;
        statusLabel = '待开始';
        statusIcon = Icons.schedule;
    }

    return Material(
      color: AppColors.bgRaised,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => LiveSessionDetailScreen(sessionUUID: session.uuid),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _phaseChip(session.phaseLabel),
                  const SizedBox(width: 8),
                  Text(
                    '$dateLabel · $hhmm',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      Icon(statusIcon, color: statusColor, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        statusLabel,
                        style: TextStyle(
                            color: statusColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ],
              ),
              if (session.selectionReason.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  session.selectionReason,
                  style: TextStyle(
                      color: AppColors.textSecondary, fontSize: 11),
                ),
              ],
              if (session.pickedSymbols.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final p in session.pickedSymbols.take(6))
                      _symbolChip(p),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.assignment,
                      color: AppColors.amber, size: 13),
                  const SizedBox(width: 4),
                  Text(
                    '${session.reportCount} 份分析师报告',
                    style: TextStyle(
                        color: AppColors.textTertiary, fontSize: 11),
                  ),
                  const Spacer(),
                  Icon(Icons.chevron_right,
                      color: AppColors.textTertiary, size: 18),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _phaseChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.amber.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(label,
          style: const TextStyle(
              color: AppColors.amber,
              fontWeight: FontWeight.w700,
              fontSize: 11)),
    );
  }

  Widget _symbolChip(LivePickedSymbol p) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderDim),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            p.name.isEmpty ? p.symbol : p.name,
            style: TextStyle(color: AppColors.textPrimary, fontSize: 11),
          ),
          const SizedBox(width: 4),
          Text(
            p.symbol,
            style: TextStyle(color: AppColors.textTertiary, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

// ── 我的关注 ──────────────────────────────────────────────────────────

class _WatchTab extends StatelessWidget {
  const _WatchTab();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LiveState>();
    if (s.loadingWatch && s.watchlist.isEmpty) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (s.watchlist.isEmpty) {
      return _emptyHint(
        '还没添加关注',
        '点右下角"+加关注"添加你关心的股票；下场直播会优先纳入选股。',
      );
    }
    return RefreshIndicator(
      onRefresh: () => context.read<LiveState>().refreshWatch(),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
        itemCount: s.watchlist.length,
        separatorBuilder: (_, __) =>
            Divider(height: 1, color: AppColors.borderDim),
        itemBuilder: (context, i) {
          final w = s.watchlist[i];
          return ListTile(
            dense: true,
            title: Text(
              w.symbolName.isEmpty ? w.symbol : w.symbolName,
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 14),
            ),
            subtitle: Text(
              w.symbol,
              style: TextStyle(color: AppColors.textTertiary, fontSize: 11),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline,
                  color: AppColors.amber, size: 18),
              tooltip: '取消关注',
              onPressed: () async {
                try {
                  await context.read<LiveState>().removeWatch(w.symbol);
                } catch (_) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('取消关注失败，请稍后再试')),
                    );
                  }
                }
              },
            ),
          );
        },
      ),
    );
  }
}

Widget _emptyHint(String title, String subtitle) {
  return ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 80),
    children: [
      const Icon(Icons.live_tv,
          color: AppColors.amber, size: 56),
      const SizedBox(height: 14),
      Text(
        title,
        textAlign: TextAlign.center,
        style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 6),
      Text(
        subtitle,
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.textTertiary, fontSize: 12),
      ),
    ],
  );
}
