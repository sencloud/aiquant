import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../models/portfolio.dart';
import '../../../state/portfolio_state.dart';
import '../../../theme/app_theme.dart';

/// "报告" — generates a markdown summary of the active portfolio that the
/// user can copy to clipboard. Mirrors the lightweight ReportsView from Qt
/// (full PDF / PME export lives PC-side).
class ReportsTab extends StatelessWidget {
  const ReportsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final ps = context.watch<PortfolioState>();
    final s = ps.currentSummary;
    if (s == null || s.holdings.isEmpty) {
      return const _Empty('加入品种后这里会生成可分享的组合报告。');
    }

    final markdown = _buildMarkdown(s);
    final json = const JsonEncoder.withIndent('  ').convert({
      'name': s.portfolio.name,
      'currency': s.portfolio.currency,
      'total_market_value': s.totalMarketValue,
      'total_pnl': s.totalUnrealizedPnl,
      'positions': [
        for (final h in s.holdings)
          {
            'symbol': h.symbol,
            'name': h.name,
            'sector': h.sector,
            'asset_class': h.assetClass,
            'quantity': h.quantity,
            'avg_buy_price': h.avgBuyPrice,
            'current_price': h.currentPrice,
            'market_value': h.marketValue,
            'unrealized_pnl': h.unrealizedPnl,
            'unrealized_pnl_pct': h.unrealizedPnlPercent,
          },
      ],
    });

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(child: _Title('Markdown 报告')),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.copy, size: 14),
                      label: const Text('复制'),
                      onPressed: () => _copy(context, markdown),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _CodeBlock(text: markdown),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(child: _Title('JSON 导出')),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.copy, size: 14),
                      label: const Text('复制'),
                      onPressed: () => _copy(context, json),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _CodeBlock(text: json),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _copy(BuildContext context, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已复制到剪贴板')),
      );
    }
  }

  String _buildMarkdown(PortfolioSummary s) {
    final fmt = NumberFormat('#,##0.00');
    final df = DateFormat('yyyy-MM-dd HH:mm');
    final sb = StringBuffer();
    sb.writeln('# ${s.portfolio.name} 组合报告');
    sb.writeln();
    sb.writeln('* 货币：${s.portfolio.currency}');
    sb.writeln('* 持仓数：${s.positions} (涨 ${s.gainers} · 跌 ${s.losers})');
    sb.writeln('* 组合市值：${fmt.format(s.totalMarketValue)}');
    sb.writeln(
        '* 未实现盈亏：${s.totalUnrealizedPnl >= 0 ? '+' : '-'}${fmt.format(s.totalUnrealizedPnl.abs())} '
        '(${s.totalUnrealizedPnlPercent.toStringAsFixed(2)}%)');
    sb.writeln('* 生成时间：${df.format(s.lastUpdated)}');
    sb.writeln();
    sb.writeln('## 持仓明细');
    sb.writeln();
    sb.writeln('| 代码 | 名称 | 行业 | 数量 | 均价 | 最新 | 市值 | 盈亏% |');
    sb.writeln('| --- | --- | --- | ---: | ---: | ---: | ---: | ---: |');
    for (final h in s.holdings) {
      sb.writeln(
          '| ${h.symbol} | ${h.name} | ${h.sector} | ${fmt.format(h.quantity)} '
          '| ${fmt.format(h.avgBuyPrice)} | ${h.currentPrice == null ? "--" : fmt.format(h.currentPrice)} '
          '| ${fmt.format(h.marketValue)} | ${h.unrealizedPnlPercent.toStringAsFixed(2)}% |');
    }
    sb.writeln();
    sb.writeln('## 行业分布');
    sb.writeln();
    final w = s.sectorWeights.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final e in w) {
      sb.writeln('* ${e.key}：${e.value.toStringAsFixed(1)}%');
    }
    return sb.toString();
  }
}

class _Title extends StatelessWidget {
  const _Title(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
          color: AppColors.amber,
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6));
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text(text,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: AppColors.textSecondary, fontSize: 12)),
        ),
      );
}

class _CodeBlock extends StatelessWidget {
  const _CodeBlock({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.bgBase,
        border: Border.all(color: AppColors.borderDim),
        borderRadius: BorderRadius.circular(2),
      ),
      child: SelectableText(
        text,
        style: TextStyle(
          color: AppColors.textPrimary,
          fontFamily: 'monospace',
          fontSize: 11,
          height: 1.4,
        ),
      ),
    );
  }
}
