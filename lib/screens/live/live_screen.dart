import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/live.dart';
import '../../state/live_state.dart';
import '../../theme/app_theme.dart';
import 'live_room_screen.dart';

/// AI 直播大厅:仅展示「房间列表」。
///
/// v2 形态:废弃了「我的关注」「分析师独立报告」概念,直播是真聊天直播间,
/// 入口只是个房间列表 — 点进去看主持人 + 嘉宾实时对话。
class LiveScreen extends StatefulWidget {
  const LiveScreen({super.key});

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<LiveState>().refreshRooms();
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LiveState>();
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.live_tv, color: AppColors.amber, size: 18),
            SizedBox(width: 6),
            Text('AI 直播间'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh, size: 18),
            onPressed: () => context.read<LiveState>().refreshRooms(),
          ),
        ],
      ),
      body: _buildBody(context, s),
    );
  }

  Widget _buildBody(BuildContext context, LiveState s) {
    if (s.loadingRooms && s.rooms.isEmpty) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (s.rooms.isEmpty) {
      return _emptyHint(
        '还没有直播间',
        '工作日 9:30/11:30/14:30/15:30 各开一场,主持人会带嘉宾实时聊大盘和热点票。',
      );
    }
    return RefreshIndicator(
      onRefresh: () => context.read<LiveState>().refreshRooms(),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        itemCount: s.rooms.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) => _RoomCard(room: s.rooms[i]),
      ),
    );
  }
}

class _RoomCard extends StatelessWidget {
  const _RoomCard({required this.room});
  final LiveRoom room;

  @override
  Widget build(BuildContext context) {
    final dt = DateTime.fromMillisecondsSinceEpoch(room.startedAt);
    final hhmm = DateFormat('HH:mm').format(dt);
    final dateLabel = DateFormat('MM-dd').format(dt);

    Color statusColor;
    String statusLabel;
    IconData statusIcon;
    switch (room.status) {
      case 'live':
        statusColor = const Color(0xFFef4444);
        statusLabel = '直播中';
        statusIcon = Icons.podcasts;
        break;
      case 'ended':
        statusColor = const Color(0xFF16a34a);
        statusLabel = '已结束';
        statusIcon = Icons.check_circle;
        break;
      case 'ended_abnormal':
        statusColor = AppColors.textTertiary;
        statusLabel = '异常中断';
        statusIcon = Icons.error_outline;
        break;
      default:
        statusColor = AppColors.textTertiary;
        statusLabel = room.status;
        statusIcon = Icons.help_outline;
    }

    return Material(
      color: AppColors.bgRaised,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => LiveRoomScreen(roomUUID: room.uuid),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _phaseChip(room.phaseLabel),
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
                      if (room.isLive)
                        Container(
                          width: 6,
                          height: 6,
                          margin: const EdgeInsets.only(right: 4),
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                          ),
                        )
                      else
                        Icon(statusIcon, color: statusColor, size: 14),
                      if (!room.isLive) const SizedBox(width: 4),
                      Text(
                        statusLabel,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                room.title,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _personaChip(room.hostPersonaName, isHost: true),
                  for (final g in room.guestPersonas)
                    _personaChip(g.name, isHost: false),
                ],
              ),
              if (room.currentFocusSymbol.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.center_focus_strong,
                        color: AppColors.amber, size: 13),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        '正在聊:${room.currentFocusName.isEmpty ? room.currentFocusSymbol : "${room.currentFocusName} (${room.currentFocusSymbol})"}',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.chat_bubble_outline,
                      color: AppColors.amber, size: 13),
                  const SizedBox(width: 4),
                  Text(
                    '${room.messageCount} 条消息',
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
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.amber,
          fontWeight: FontWeight.w700,
          fontSize: 11,
        ),
      ),
    );
  }

  Widget _personaChip(String name, {required bool isHost}) {
    final color = isHost ? AppColors.amber : AppColors.textSecondary;
    final bg = isHost
        ? AppColors.amber.withValues(alpha: 0.12)
        : AppColors.bgSurface;
    final prefix = isHost ? '🎙 ' : '';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderDim),
      ),
      child: Text(
        '$prefix$name',
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}

Widget _emptyHint(String title, String subtitle) {
  return ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 80),
    children: [
      const Icon(Icons.live_tv, color: AppColors.amber, size: 56),
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
