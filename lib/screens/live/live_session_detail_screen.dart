import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/live.dart';
import '../../state/live_state.dart';
import '../../theme/app_theme.dart';
import 'live_report_detail_screen.dart';

/// 单场直播详情：按 symbol 分组，展示 6 位分析师各自的评级 + 一句话。
class LiveSessionDetailScreen extends StatefulWidget {
  const LiveSessionDetailScreen({super.key, required this.sessionUUID});
  final String sessionUUID;

  @override
  State<LiveSessionDetailScreen> createState() =>
      _LiveSessionDetailScreenState();
}

class _LiveSessionDetailScreenState extends State<LiveSessionDetailScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<LiveState>().loadSessionDetail(widget.sessionUUID);
    });
  }

  @override
  Widget build(BuildContext context) {
    final live = context.watch<LiveState>();
    final session = live.sessionByUUID(widget.sessionUUID);

    return Scaffold(
      appBar: AppBar(
        title: const Text('直播详情'),
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh, size: 18),
            onPressed: () => live.loadSessionDetail(widget.sessionUUID,
                force: true),
          ),
        ],
      ),
      body: session == null
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : _body(context, session),
    );
  }

  Widget _body(BuildContext context, LiveSession s) {
    if (s.reports.isEmpty) {
      return _emptyHint(s);
    }
    final groups = _groupBySymbol(s.reports);
    final dt = DateTime.fromMillisecondsSinceEpoch(s.scheduledAt);
    return RefreshIndicator(
      onRefresh: () =>
          context.read<LiveState>().loadSessionDetail(s.uuid, force: true),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          _header(s, dt),
          const SizedBox(height: 14),
          for (final g in groups) _symbolBlock(g),
        ],
      ),
    );
  }

  Widget _header(LiveSession s, DateTime dt) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.bgRaised,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.amber.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  s.phaseLabel,
                  style: const TextStyle(
                    color: AppColors.amber,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                DateFormat('yyyy-MM-dd HH:mm').format(dt),
                style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700),
              ),
            ],
          ),
          if (s.selectionReason.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '选股来源：${s.selectionReason}',
              style:
                  TextStyle(color: AppColors.textSecondary, fontSize: 11),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            '共 ${s.pickedSymbols.length} 只标的 · ${s.reportCount} 份分析师报告',
            style: TextStyle(color: AppColors.textTertiary, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _symbolBlock(_SymbolGroup g) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: AppColors.bgRaised,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              children: [
                Text(
                  g.name.isEmpty ? g.symbol : g.name,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  g.symbol,
                  style: TextStyle(
                      color: AppColors.textTertiary, fontSize: 11),
                ),
                const Spacer(),
                Text(
                  '${g.reports.length} 位分析师',
                  style: TextStyle(
                      color: AppColors.textTertiary, fontSize: 11),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.borderDim),
          for (final r in g.reports) _reportRow(r),
        ],
      ),
    );
  }

  Widget _reportRow(LiveReportBrief r) {
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => LiveReportDetailScreen(reportId: r.id),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 14,
              backgroundColor: AppColors.amber,
              child: Text(
                _initial(r.personaName),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        r.personaName,
                        style: TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 13),
                      ),
                      const SizedBox(width: 6),
                      _ratingBadge(r),
                    ],
                  ),
                  if (r.summary.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      r.summary,
                      style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          height: 1.4),
                    ),
                  ],
                  if (_hasNumbers(r)) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        if (r.targetPrice != null)
                          _kvChip('目标', r.targetPrice!),
                        if (r.takeProfit != null)
                          _kvChip('止盈', r.takeProfit!),
                        if (r.stopLoss != null)
                          _kvChip('止损', r.stopLoss!),
                        if (r.positionHint.isNotEmpty)
                          _txtChip('仓位', r.positionHint),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right,
                color: AppColors.textTertiary, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _ratingBadge(LiveReportBrief r) {
    if (r.rating.isEmpty) return const SizedBox.shrink();
    Color c;
    switch (r.view) {
      case 'bullish':
        c = const Color(0xFF16a34a);
        break;
      case 'bearish':
        c = const Color(0xFFef4444);
        break;
      default:
        c = AppColors.textSecondary;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        border: Border.all(color: c.withValues(alpha: 0.55)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        r.rating,
        style: TextStyle(
            color: c, fontSize: 10, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _kvChip(String k, double v) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$k ${v.toStringAsFixed(2)}',
        style: TextStyle(color: AppColors.textSecondary, fontSize: 10.5),
      ),
    );
  }

  Widget _txtChip(String k, String v) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$k $v',
        style: TextStyle(color: AppColors.textSecondary, fontSize: 10.5),
      ),
    );
  }

  Widget _emptyHint(LiveSession s) {
    final running = s.isRunning;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              running ? Icons.podcasts : Icons.history_toggle_off,
              color: AppColors.amber,
              size: 56,
            ),
            const SizedBox(height: 12),
            Text(
              running ? '直播中…' : '本场暂无报告',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              running
                  ? 'AI 正在调用工具拉数据并撰写报告，6 位分析师 × ${s.pickedSymbols.length} 只标的，预计需要几分钟。'
                  : '可下拉刷新查看；本场可能未生成任何报告。',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textTertiary, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  bool _hasNumbers(LiveReportBrief r) =>
      r.targetPrice != null ||
      r.takeProfit != null ||
      r.stopLoss != null ||
      r.positionHint.isNotEmpty;

  String _initial(String n) {
    if (n.isEmpty) return '?';
    return n.substring(0, 1);
  }

  List<_SymbolGroup> _groupBySymbol(List<LiveReportBrief> reports) {
    final map = <String, _SymbolGroup>{};
    for (final r in reports) {
      map.putIfAbsent(
        r.symbol,
        () => _SymbolGroup(symbol: r.symbol, name: r.symbolName),
      ).reports.add(r);
    }
    return map.values.toList();
  }
}

class _SymbolGroup {
  _SymbolGroup({required this.symbol, required this.name});
  final String symbol;
  final String name;
  final List<LiveReportBrief> reports = [];
}
