import 'package:flutter/material.dart';

import '../../models/trade_review.dart';
import '../../services/trade_review_repository.dart';
import '../../theme/app_theme.dart';
import '../../widgets/wk_kit.dart';
import 'trade_report_screen.dart';
import 'trade_review_widgets.dart';

class TradeReviewHistoryScreen extends StatelessWidget {
  const TradeReviewHistoryScreen({super.key});

  void _open(BuildContext context, TradeReviewReport report) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TradeReportScreen(report: report),
      ),
    );
  }

  Future<void> _delete(BuildContext context, TradeReviewReport report) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这份复盘？'),
        content: const Text('只会删除本机保存的分析结果，不会影响原始成交记录。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await TradeReviewStore.instance.delete(report.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已删除这份本机复盘。')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: AppBar(title: const Text('我的交易记录')),
      body: AnimatedBuilder(
        animation: TradeReviewStore.instance,
        builder: (context, _) {
          final reports = TradeReviewStore.instance.reports;
          if (reports.isEmpty) {
            return const WkEmpty(
              icon: Icons.manage_search_rounded,
              title: '还没有保存过交易复盘',
              hint: '去「嘻，AI」上传一张成交记录截图，核对后生成第一份复盘。',
            );
          }
          return ListView(
            padding: const EdgeInsets.only(top: AppSpace.md),
            children: [
              WkGroup(
                children: [
                  for (final report in reports)
                    _HistoryRow(
                      report: report,
                      onTap: () => _open(context, report),
                      onDelete: () => _delete(context, report),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.lg,
                  AppSpace.xs,
                  AppSpace.lg,
                  AppSpace.xl,
                ),
                child: Text(
                  '最多保留 20 份，只保存分析结果，不保存上传的截图。',
                  textAlign: TextAlign.center,
                  style: AppType.micro.copyWith(
                    color: AppColors.textTertiary,
                    height: 1.6,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.report,
    required this.onTap,
    required this.onDelete,
  });

  final TradeReviewReport report;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final pnl = report.metrics.realizedPnl;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.lg,
            AppSpace.md,
            AppSpace.xs,
            AppSpace.md,
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.accentSoft,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(
                  Icons.auto_graph_rounded,
                  color: AppColors.amber,
                  size: 21,
                ),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      report.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.body.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: AppSpace.xs),
                    Text(
                      '${report.brokerHint.isEmpty ? '成交记录' : report.brokerHint}'
                      ' · ${formatTradeDate(report.createdAt)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.micro.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpace.sm),
              Text(
                formatTradeMoney(pnl, currency: report.currency),
                style: AppType.caption.copyWith(
                  color: tradeResultColor(pnl),
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              IconButton(
                key: ValueKey('delete-review-${report.id}'),
                tooltip: '删除复盘',
                onPressed: onDelete,
                color: AppColors.textTertiary,
                constraints: const BoxConstraints.tightFor(
                  width: 44,
                  height: 44,
                ),
                icon: const Icon(Icons.delete_outline_rounded, size: 19),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: AppColors.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
