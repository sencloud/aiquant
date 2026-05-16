import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../models/portfolio.dart';
import '../../../state/portfolio_state.dart';
import '../../../theme/app_theme.dart';

/// "优化 / Optimization" — surfaces a few simple long-only re-weighting
/// candidates the user can compare against the current allocation.
/// Server-side optimisation (the Qt PortfolioOptimizationView) lives behind a
/// Python service we don't have here, so we run two cheap heuristics on the
/// client:
///   - 等权重 (equal weight)
///   - 反向波动 (1 / sigma) — uses available day_change_percent as a sigma proxy
class OptimizationTab extends StatelessWidget {
  const OptimizationTab({super.key});

  @override
  Widget build(BuildContext context) {
    final ps = context.watch<PortfolioState>();
    final s = ps.currentSummary;
    if (s == null || s.holdings.isEmpty) {
      return const _Empty('加入品种后这里会展示组合权重的优化建议。');
    }

    final equal = _equalWeights(s.holdings);
    final invVol = _inverseVolWeights(s.holdings);
    final current = _currentWeights(s);

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _Title('权重对比'),
                const SizedBox(height: 6),
                const _LegendRow(),
                const SizedBox(height: 4),
                for (final h in s.holdings)
                  _Row(
                    label: '${h.symbol}  ${h.name}',
                    current: current[h.symbol] ?? 0,
                    equal: equal[h.symbol] ?? 0,
                    invVol: invVol[h.symbol] ?? 0,
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
                const _Title('说明'),
                const SizedBox(height: 8),
                Text(
                    '等权重 (Equal): 假设每个标的占比一致，是抑制集中度的常见基线。\n'
                    '反向波动 (Inv-Vol): 用近一日 |涨跌%| 作为波动率代理，'
                    '对越平稳的标的赋予越高权重，适合稳健型投资者。\n'
                    '完整的 Markowitz / Black-Litterman 等方法依赖历史协方差，'
                    '请结合 PC 端 Python 服务使用。',
                    style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                        height: 1.6)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Map<String, double> _equalWeights(List<PortfolioAsset> holdings) {
    final n = holdings.length;
    if (n == 0) return const {};
    final w = 100.0 / n;
    return {for (final h in holdings) h.symbol: w};
  }

  Map<String, double> _inverseVolWeights(List<PortfolioAsset> holdings) {
    final invs = <String, double>{};
    for (final h in holdings) {
      final sigma = (h.dayChangePercent ?? 1.5).abs();
      invs[h.symbol] = 1.0 / (sigma + 0.5);
    }
    final total = invs.values.fold<double>(0, (s, v) => s + v);
    if (total == 0) return _equalWeights(holdings);
    return {
      for (final e in invs.entries) e.key: e.value / total * 100,
    };
  }

  Map<String, double> _currentWeights(PortfolioSummary s) {
    if (s.totalMarketValue <= 0) return const {};
    return {
      for (final h in s.holdings) h.symbol: h.marketValue / s.totalMarketValue * 100,
    };
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
                    color: AppColors.textSecondary, fontSize: 12))),
      );
}

class _LegendRow extends StatelessWidget {
  const _LegendRow();
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(flex: 5, child: Text('品种', style: _hStyle)),
        Expanded(flex: 3, child: Text('当前', textAlign: TextAlign.right, style: _hStyle)),
        Expanded(flex: 3, child: Text('等权', textAlign: TextAlign.right, style: _hStyle)),
        Expanded(flex: 3, child: Text('反向波动', textAlign: TextAlign.right, style: _hStyle)),
      ],
    );
  }
}

TextStyle get _hStyle => TextStyle(
    color: AppColors.textTertiary,
    fontSize: 10,
    fontWeight: FontWeight.w800,
    letterSpacing: 0.5);

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.current,
    required this.equal,
    required this.invVol,
  });
  final String label;
  final double current;
  final double equal;
  final double invVol;

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('0.00');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: AppColors.textPrimary, fontSize: 11)),
          ),
          Expanded(
              flex: 3,
              child: Text('${fmt.format(current)}%',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: AppColors.textPrimary))),
          Expanded(
              flex: 3,
              child: Text('${fmt.format(equal)}%',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: AppColors.amber))),
          Expanded(
              flex: 3,
              child: Text('${fmt.format(invVol)}%',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: AppColors.info))),
        ],
      ),
    );
  }
}
