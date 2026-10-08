import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../services/backtest/backtest_models.dart';
import '../../../theme/app_theme.dart';

/// 策略 vs 基准净值曲线（策略无关：只认 BacktestViewData）。
///
/// 策略线用主题琥珀实线，基准细虚线弱化。
/// X 轴 = 采样点序号（避免 DateTime 转 double 精度问题），tooltip 显示日期。
class NavChart extends StatelessWidget {
  const NavChart({super.key, required this.view});

  final BacktestViewData view;

  static const _strategyColor = Color(0xFFF59E0B); // 金黄（主题色）
  static const _benchColor = Color(0xFF64748B); // 灰蓝（弱化基准）

  @override
  Widget build(BuildContext context) {
    final nav = view.navSeries;
    final bench = view.benchmarkNavSeries;
    if (nav.isEmpty || bench.isEmpty) return const SizedBox.shrink();

    final stratSpots = <FlSpot>[
      for (var i = 0; i < nav.length; i++)
        FlSpot(i.toDouble(), nav[i].nav),
    ];
    final benchSpots = <FlSpot>[
      for (var i = 0; i < bench.length; i++)
        FlSpot(i.toDouble(), bench[i].nav),
    ];

    // Y 轴范围：两条曲线 min/max 各留 6% 边距，下限不低于 0
    var minY = double.infinity;
    var maxY = double.negativeInfinity;
    for (final p in [...nav, ...bench]) {
      if (p.nav < minY) minY = p.nav;
      if (p.nav > maxY) maxY = p.nav;
    }
    final pad = (maxY - minY) * 0.06 + 0.01;
    minY = (minY - pad).clamp(0, double.infinity);
    maxY = maxY + pad;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 20, 10),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderDim),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Text('净值曲线',
                style: TextStyle(
                    color: AppColors.amber,
                    fontSize: 12,
                    fontWeight: FontWeight.w800)),
            const SizedBox(width: 16),
            _legend(view.strategyLabel.replaceFirst('策略 · ', ''),
                _strategyColor, solid: true),
            const SizedBox(width: 14),
            _legend(view.benchmarkLabel.replaceFirst('基准 · ', ''),
                _benchColor, solid: false),
            const Spacer(),
            Text('起点归一',
                style: TextStyle(
                    color: AppColors.textTertiary, fontSize: 10.5)),
          ]),
          const SizedBox(height: 10),
          SizedBox(
            height: 280,
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: (nav.length - 1).toDouble(),
                minY: minY,
                maxY: maxY,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval:
                      ((maxY - minY) / 5).clamp(0.05, double.infinity),
                  getDrawingHorizontalLine: (v) => FlLine(
                    color: AppColors.borderDim,
                    strokeWidth: 0.6,
                  ),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 44,
                      getTitlesWidget: (v, meta) => Text(
                        v.toStringAsFixed(2),
                        style: TextStyle(
                            color: AppColors.textTertiary, fontSize: 10),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: _xInterval(nav.length),
                      getTitlesWidget: (v, meta) {
                        final idx = v.toInt();
                        if (idx < 0 || idx >= nav.length) {
                          return const SizedBox.shrink();
                        }
                        final d = nav[idx].date;
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            DateFormat('yy/M').format(d),
                            style: TextStyle(
                                color: AppColors.textTertiary,
                                fontSize: 10),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (spots) {
                      final out = <LineTooltipItem>[];
                      for (final s in spots) {
                        final idx = s.x.toInt();
                        final d =
                            idx < nav.length ? nav[idx].date : null;
                        final label =
                            d != null ? DateFormat('yyyy-MM-dd').format(d) : '';
                        out.add(LineTooltipItem(
                          '$label\n${s.y.toStringAsFixed(3)}',
                          TextStyle(
                            color: s.bar.color ?? Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ));
                      }
                      return out;
                    },
                  ),
                ),
                lineBarsData: [
                  _line(benchSpots, _benchColor, dashed: true),
                  _line(stratSpots, _strategyColor),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  LineChartBarData _line(List<FlSpot> spots, Color color,
      {bool dashed = false}) {
    return LineChartBarData(
      spots: spots,
      isCurved: false,
      color: color,
      barWidth: dashed ? 1.2 : 2.0,
      dotData: const FlDotData(show: false),
      dashArray: dashed ? [5, 4] : null,
    );
  }

  Widget _legend(String label, Color color, {required bool solid}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: solid ? 3 : 2,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(1.5),
          ),
        ),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
      ],
    );
  }

  double _xInterval(int n) {
    if (n <= 12) return 1;
    if (n <= 24) return 3;
    if (n <= 48) return 6;
    return 12;
  }
}
