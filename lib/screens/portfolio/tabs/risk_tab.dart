import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../models/portfolio.dart';
import '../../../state/portfolio_state.dart';
import '../../../theme/app_theme.dart';

/// "风控" tab — concentration, single-name, sector & day-shock heatmap.
class RiskTab extends StatelessWidget {
  const RiskTab({super.key});

  @override
  Widget build(BuildContext context) {
    final ps = context.watch<PortfolioState>();
    final s = ps.currentSummary;
    if (s == null || s.holdings.isEmpty) {
      return const _Empty('加入品种后这里会展示风险敞口与建议。');
    }
    final fmt = NumberFormat('0.00');
    final total = s.totalMarketValue;

    final largestSym = [...s.holdings]
      ..sort((a, b) => b.marketValue.compareTo(a.marketValue));
    final topShare = total <= 0
        ? 0
        : largestSym.first.marketValue / total * 100;

    final sortedSectors = s.sectorWeights.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topSector = sortedSectors.isEmpty ? null : sortedSectors.first;

    final dayShock = s.holdings
        .map((h) => (h.dayChangePercent ?? 0).abs())
        .fold<double>(0, math.max);

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _T('集中度概览'),
                const SizedBox(height: 8),
                _Kv('单品种最大占比 (${largestSym.first.symbol})',
                    '${fmt.format(topShare)}%',
                    warn: topShare > 30),
                if (topSector != null)
                  _Kv('单行业最大占比 (${topSector.key})',
                      '${fmt.format(topSector.value)}%',
                      warn: topSector.value > 50),
                _Kv('当日单边最大波动',
                    '${fmt.format(dayShock)}%',
                    warn: dayShock > 5),
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
                const _T('品种风险热度'),
                const SizedBox(height: 8),
                _Heatmap(holdings: s.holdings),
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
                const _T('风险提示'),
                const SizedBox(height: 6),
                Text(
                  '· 单一品种或行业占比 > 30% 视为集中度偏高；\n'
                  '· 当日波动 > 5% 通常意味着事件性冲击，建议关注；\n'
                  '· 如需 VaR / CVaR / 压力测试，请使用 Fincept PC 终端。',
                  style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                      height: 1.6),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Heatmap extends StatelessWidget {
  const _Heatmap({required this.holdings});
  final List<PortfolioAsset> holdings;
  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final h in holdings)
          Container(
            width: 92,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: _bgFor(h.unrealizedPnlPercent),
              border: Border.all(color: AppColors.borderDim),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(h.name.isEmpty ? h.symbol : h.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 11)),
                const SizedBox(height: 2),
                Text('${h.unrealizedPnlPercent.toStringAsFixed(2)}%',
                    style: TextStyle(
                        color: h.unrealizedPnlPercent >= 0
                            ? AppColors.positive
                            : AppColors.negative,
                        fontFamily: 'monospace',
                        fontSize: 12,
                        fontWeight: FontWeight.w800)),
              ],
            ),
          )
      ],
    );
  }

  Color _bgFor(double pnlPct) {
    final mag = pnlPct.abs().clamp(0.0, 20.0) / 20.0;
    final base = pnlPct >= 0 ? AppColors.positive : AppColors.negative;
    return base.withValues(alpha: 0.08 + mag * 0.18);
  }
}

class _T extends StatelessWidget {
  const _T(this.text);
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

class _Kv extends StatelessWidget {
  const _Kv(this.label, this.value, {this.warn = false});
  final String label;
  final String value;
  final bool warn;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 12)),
          ),
          Text(value,
              style: TextStyle(
                  color: warn ? AppColors.warning : AppColors.textPrimary,
                  fontFamily: 'monospace',
                  fontSize: 13,
                  fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}
