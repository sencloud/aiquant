import 'package:flutter/material.dart';

import '../../../services/backtest/backtest_models.dart';
import '../../../theme/app_theme.dart';

/// 回测结果指标区（策略无关：只认 BacktestViewData）。
///
/// 1. 概览条（stats 列表，由策略引擎按语义生成）
/// 2. 策略 vs 基准对比表 + 年化超额大数字
/// 3. 期末持仓（短线策略没有，为空时不渲染）
///
/// 收益类正 = 红、负 = 绿（A 股惯例，走 AppColors.positive/negative）。
class MetricsCards extends StatelessWidget {
  const MetricsCards({super.key, required this.view});

  final BacktestViewData view;

  @override
  Widget build(BuildContext context) {
    final s = view.strategyMetrics;
    final b = view.benchmarkMetrics;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── 概览条 ───────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: _cardDeco(),
          child: Row(
            children: [
              for (var i = 0; i < view.stats.length; i++) ...[
                if (i > 0) _vd(),
                _overviewItem(view.stats[i].label, view.stats[i].value),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),

        // ── 对比区：策略表 + 基准表 + Alpha ─────────────────────
        Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _metricsTable(
                title: view.strategyLabel,
                titleColor: AppColors.amber,
                m: s,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _metricsTable(
                title: view.benchmarkLabel,
                titleColor: AppColors.textSecondary,
                m: b,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: _alphaCard()),
          ],
        ),
        if (view.finalHoldings.isNotEmpty) ...[
          const SizedBox(height: 12),
          _holdingsCard(),
        ],
      ],
    );
  }

  Widget _vd() => Container(
        width: 1,
        height: 26,
        margin: const EdgeInsets.symmetric(horizontal: 18),
        color: AppColors.borderDim,
      );

  Widget _overviewItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style:
                TextStyle(color: AppColors.textTertiary, fontSize: 10.5)),
        const SizedBox(height: 3),
        Text(value,
            style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w700)),
      ],
    );
  }

  BoxDecoration _cardDeco() => BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderDim),
      );

  Widget _metricsTable({
    required String title,
    required Color titleColor,
    required BacktestMetrics m,
  }) {
    String pct(double v) =>
        '${v > 0 ? '+' : ''}${(v * 100).toStringAsFixed(2)}%';
    final rows = <(String, String, Color)>[
      ('总收益', pct(m.totalReturn), _posNeg(m.totalReturn)),
      ('年化收益', pct(m.annReturn), _posNeg(m.annReturn)),
      ('年化波动', '${(m.annVol * 100).toStringAsFixed(2)}%',
          AppColors.textPrimary),
      ('Sharpe', m.sharpe.toStringAsFixed(3), AppColors.textPrimary),
      ('最大回撤',
          '-${(m.maxDrawdown * 100).toStringAsFixed(2)}%',
          AppColors.negative),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: _cardDeco(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  color: titleColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          for (final (k, v, c) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Expanded(
                      child: Text(k,
                          style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12))),
                  Text(v,
                      style: TextStyle(
                          color: c,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// 正 = 红（涨），负 = 绿（跌）——A 股语义色。
  Color _posNeg(double v) =>
      v > 0 ? AppColors.positive : AppColors.negative;

  Widget _alphaCard() {
    final alpha = view.alpha;
    final positive = alpha >= 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: _cardDeco(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('年化超额 Alpha',
              style: TextStyle(
                  color: AppColors.amber,
                  fontSize: 12,
                  fontWeight: FontWeight.w800)),
          const Spacer(),
          Text(
            '${positive ? '+' : ''}${(alpha * 100).toStringAsFixed(2)}%',
            style: TextStyle(
              color: positive ? AppColors.positive : AppColors.negative,
              fontSize: 30,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text('策略年化 − 基准年化',
              style: TextStyle(
                  color: AppColors.textTertiary, fontSize: 10.5)),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Widget _holdingsCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: _cardDeco(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('期末持仓',
              style: TextStyle(
                  color: AppColors.amber,
                  fontSize: 12,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final h in view.finalHoldings)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: AppColors.bgRaised,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.borderDim),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(h.symbol,
                          style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 12,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(width: 8),
                      Text(
                        '${(h.weight * 100).toStringAsFixed(1)}%',
                        style: const TextStyle(
                            color: AppColors.amber,
                            fontSize: 12,
                            fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
