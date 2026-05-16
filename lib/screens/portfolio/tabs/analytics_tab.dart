import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../state/portfolio_state.dart';
import '../../../theme/app_theme.dart';
import '../widgets/sector_donut.dart';

/// "行业 / Sectors" tab — sector-level breakdown of holdings, top contributors
/// to value and to P&L, and a per-asset class roll-up. Mirrors the
/// AnalyticsSectorsView from the Qt project.
class AnalyticsTab extends StatelessWidget {
  const AnalyticsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final ps = context.watch<PortfolioState>();
    final s = ps.currentSummary;
    if (s == null || s.holdings.isEmpty) {
      return const _Empty(
          message: '加入品种后这里会展示行业分布和子板块的贡献。');
    }

    final fmt = NumberFormat('#,##0.00');
    final sectorWeights = s.sectorWeights;
    final pnlBySector = <String, double>{};
    for (final h in s.holdings) {
      pnlBySector.update(h.sector.isEmpty ? '其它' : h.sector,
          (v) => v + h.unrealizedPnl,
          ifAbsent: () => h.unrealizedPnl);
    }
    final pnlEntries = pnlBySector.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final byClass = <String, double>{};
    for (final h in s.holdings) {
      byClass.update(h.assetClass.isEmpty ? '其它' : h.assetClass,
          (v) => v + h.marketValue,
          ifAbsent: () => h.marketValue);
    }
    final classEntries = byClass.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionTitle('行业市值占比'),
                const SizedBox(height: 8),
                SectorDonut(weights: sectorWeights),
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
                const _SectionTitle('行业盈亏贡献'),
                const SizedBox(height: 6),
                for (final e in pnlEntries)
                  _BarRow(
                    label: e.key,
                    valueText:
                        '${e.value >= 0 ? "+" : "-"}${fmt.format(e.value.abs())}',
                    fraction: _scale(pnlBySector.values, e.value.abs()),
                    color: e.value >= 0
                        ? AppColors.positive
                        : AppColors.negative,
                  ),
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
                const _SectionTitle('资产类别'),
                const SizedBox(height: 6),
                for (final e in classEntries)
                  _BarRow(
                    label: e.key,
                    valueText: fmt.format(e.value),
                    fraction: e.value /
                        (s.totalMarketValue == 0 ? 1 : s.totalMarketValue),
                    color: sectorColorFor(e.key),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static double _scale(Iterable<double> values, double v) {
    final maxAbs = values.fold<double>(
        0, (m, x) => x.abs() > m ? x.abs() : m);
    if (maxAbs == 0) return 0;
    return v / maxAbs;
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: const TextStyle(
            color: AppColors.amber,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6));
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.insights, color: AppColors.amber, size: 36),
            const SizedBox(height: 12),
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _BarRow extends StatelessWidget {
  const _BarRow({
    required this.label,
    required this.valueText,
    required this.fraction,
    required this.color,
  });

  final String label;
  final String valueText;
  final double fraction; // 0..1
  final Color color;

  @override
  Widget build(BuildContext context) {
    final f = fraction.isNaN || fraction <= 0 ? 0.0 : fraction.clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label,
                    style: TextStyle(
                        color: AppColors.textPrimary, fontSize: 11)),
              ),
              Text(valueText,
                  style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'monospace')),
            ],
          ),
          const SizedBox(height: 4),
          Container(
            height: 4,
            color: AppColors.bgBase,
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: f.toDouble(),
              child: Container(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
