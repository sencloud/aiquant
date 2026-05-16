import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../state/portfolio_state.dart';
import '../../../theme/app_theme.dart';

/// 量化统计 — distribution / concentration / dispersion stats over the
/// current holdings (lightweight client-side equivalent of the QuantStatsView).
class QuantTab extends StatelessWidget {
  const QuantTab({super.key});

  @override
  Widget build(BuildContext context) {
    final ps = context.watch<PortfolioState>();
    final s = ps.currentSummary;
    if (s == null || s.holdings.isEmpty) {
      return const _Empty('加入品种后这里会展示统计指标。');
    }

    final pnls = [for (final h in s.holdings) h.unrealizedPnlPercent];
    final mean = pnls.isEmpty ? 0 : pnls.reduce((a, b) => a + b) / pnls.length;
    final std = pnls.length < 2
        ? 0
        : math.sqrt(pnls.fold<double>(
                0, (acc, v) => acc + math.pow(v - mean, 2).toDouble()) /
            pnls.length);
    final maxPos = pnls.fold<double>(double.negativeInfinity,
        (m, v) => v > m ? v : m);
    final maxNeg =
        pnls.fold<double>(double.infinity, (m, v) => v < m ? v : m);

    final weights = [for (final h in s.holdings) h.marketValue];
    final totalMv = weights.fold<double>(0, (a, b) => a + b);
    final shares = totalMv == 0
        ? <double>[]
        : weights.map((v) => v / totalMv).toList();
    final hhi = shares.fold<double>(0, (a, w) => a + w * w);
    shares.sort((a, b) => b.compareTo(a));
    final top3 =
        shares.take(3).fold<double>(0, (a, w) => a + w) * 100;
    final assetCount = s.holdings.length;
    final sectorCount = s.sectorWeights.length;

    final fmt = NumberFormat('0.00');

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _Title('收益率分布（基于持仓盈亏%）'),
                const SizedBox(height: 8),
                _Grid([
                  _Kv('均值', '${fmt.format(mean)}%'),
                  _Kv('标准差', '${fmt.format(std)}%'),
                  _Kv('最大盈利', '${fmt.format(maxPos)}%',
                      color: AppColors.positive),
                  _Kv('最大亏损', '${fmt.format(maxNeg)}%',
                      color: AppColors.negative),
                ]),
                const SizedBox(height: 8),
                _Hist(values: pnls),
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
                const _Title('集中度'),
                const SizedBox(height: 8),
                _Grid([
                  _Kv('品种数量', '$assetCount'),
                  _Kv('行业数量', '$sectorCount'),
                  _Kv('HHI 指数', fmt.format(hhi)),
                  _Kv('Top 3 集中度', '${fmt.format(top3)}%'),
                ]),
              ],
            ),
          ),
        ),
      ],
    );
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

class _Grid extends StatelessWidget {
  const _Grid(this.items);
  final List<_Kv> items;
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, c) {
      final cols = c.maxWidth > 480 ? 4 : 2;
      return GridView.count(
        crossAxisCount: cols,
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 2.4,
        children: [for (final i in items) i],
      );
    });
  }
}

class _Kv extends StatelessWidget {
  const _Kv(this.label, this.value, {this.color});
  final String label;
  final String value;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.bgBase,
        border: Border.all(color: AppColors.borderDim),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label,
              style: TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5)),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  color: color ?? AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _Hist extends StatelessWidget {
  const _Hist({required this.values});
  final List<double> values;

  @override
  Widget build(BuildContext context) {
    if (values.length < 2) {
      return SizedBox(
        height: 80,
        child: Center(
          child: Text('数据点过少',
              style: TextStyle(color: AppColors.textTertiary, fontSize: 11)),
        ),
      );
    }
    final minV = values.reduce(math.min);
    final maxV = values.reduce(math.max);
    final span = (maxV - minV).abs();
    if (span < 1e-6) {
      return SizedBox(
        height: 80,
        child: Center(
          child: Text('值无差异',
              style: TextStyle(color: AppColors.textTertiary, fontSize: 11)),
        ),
      );
    }
    const buckets = 12;
    final counts = List<int>.filled(buckets, 0);
    for (final v in values) {
      var idx = ((v - minV) / span * buckets).floor();
      if (idx >= buckets) idx = buckets - 1;
      counts[idx]++;
    }
    final maxCount = counts.reduce(math.max);
    return SizedBox(
      height: 100,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (int i = 0; i < buckets; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: Container(
                  height: maxCount == 0
                      ? 0
                      : 96 * counts[i] / maxCount,
                  color: counts[i] == 0
                      ? AppColors.bgRaised
                      : (i >= buckets / 2
                          ? AppColors.positive
                          : AppColors.negative),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
