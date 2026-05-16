import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../models/instrument.dart';
import '../../../models/portfolio.dart';
import '../../../services/indicators.dart';
import '../../../state/portfolio_state.dart';
import '../../../theme/app_theme.dart';

/// "绩效 / 风险" tab — 完整重写：
///   - 顶部 KPI：累计 / 年化 / 年化波动 / Sharpe / Sortino / Calmar / IR / MaxDD
///   - 中段：组合 NAV vs 沪深 300（同坐标 rebased = 100）
///   - drawdown 面积图（专门展示回撤区间）
///   - 月度收益热力图（QuantStats 经典图）
///   - 盈亏 / 亏损前三持仓
class PerformanceTab extends StatefulWidget {
  const PerformanceTab({super.key});

  @override
  State<PerformanceTab> createState() => _PerformanceTabState();
}

class _PerformanceTabState extends State<PerformanceTab> {
  static const _benchmarkCode = '000300.SH';
  static const _windowDays = 252;
  static const _riskFree = 0.03; // 默认 3%；后续可让用户调

  List<MapEntry<DateTime, double>>? _navSeries;
  List<CandlePoint>? _benchmarkSeries;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final ps = context.read<PortfolioState>();
    final nav = await ps.performanceSeries(days: _windowDays);
    final bench = await ps.benchmarkSeries(
        tsCode: _benchmarkCode, days: _windowDays);
    if (!mounted) return;
    setState(() {
      _navSeries = nav;
      _benchmarkSeries = bench;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ps = context.watch<PortfolioState>();
    final s = ps.currentSummary;
    if (s == null || s.holdings.isEmpty) {
      return const _EmptyMsg('加入品种后这里会展示组合的绩效与风险指标。');
    }
    if (_loading) return const Center(child: CircularProgressIndicator());

    final nav = _navSeries ?? const [];
    final bench = _benchmarkSeries ?? const [];
    final navAsCandles = [
      for (final e in nav) CandlePoint(date: e.key, close: e.value)
    ];

    final stats = _Stats.compute(navAsCandles, bench);
    final fmt = NumberFormat('#,##0.00');

    final top = [...s.holdings]
      ..sort((a, b) => b.unrealizedPnl.compareTo(a.unrealizedPnl));
    final losers = [...s.holdings]
      ..sort((a, b) => a.unrealizedPnl.compareTo(b.unrealizedPnl));

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _kpiCard(s, stats, fmt),
          const SizedBox(height: 12),
          _navVsBenchmarkCard(navAsCandles, bench),
          const SizedBox(height: 12),
          _drawdownCard(navAsCandles),
          const SizedBox(height: 12),
          _monthlyHeatmapCard(navAsCandles),
          const SizedBox(height: 12),
          _pnlCard(top, losers),
        ],
      ),
    );
  }

  Widget _kpiCard(PortfolioSummary s, _Stats stats, NumberFormat fmt) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _Title('收益与风险（近 252 个交易日 · rf=3%）'),
            const SizedBox(height: 10),
            _kpiGrid([
              _Kpi('累计收益率',
                  stats.cumulativeReturn == null ? '--' : '${(stats.cumulativeReturn! * 100).toStringAsFixed(2)}%',
                  color: stats.cumulativeReturn == null
                      ? null
                      : (stats.cumulativeReturn! >= 0 ? AppColors.positive : AppColors.negative)),
              _Kpi('年化收益率',
                  stats.annualReturn == null ? '--' : '${(stats.annualReturn! * 100).toStringAsFixed(2)}%'),
              _Kpi('年化波动率',
                  stats.annualVol == null ? '--' : '${(stats.annualVol! * 100).toStringAsFixed(2)}%'),
              _Kpi('Sharpe',
                  stats.sharpe == null ? '--' : stats.sharpe!.toStringAsFixed(2)),
              _Kpi('Sortino',
                  stats.sortino == null ? '--' : stats.sortino!.toStringAsFixed(2)),
              _Kpi('Calmar',
                  stats.calmar == null ? '--' : stats.calmar!.toStringAsFixed(2)),
              _Kpi('Information Ratio',
                  stats.ir == null ? '--' : stats.ir!.toStringAsFixed(2)),
              _Kpi('最大回撤',
                  stats.maxDrawdown == null ? '--' : '-${(stats.maxDrawdown! * 100).toStringAsFixed(2)}%',
                  color: AppColors.negative),
              _Kpi('Up/Down Capture',
                  stats.upCapture == null
                      ? '--'
                      : '${(stats.upCapture! * 100).toStringAsFixed(0)}/${(stats.downCapture! * 100).toStringAsFixed(0)}'),
              _Kpi('当前市值', fmt.format(s.totalMarketValue),
                  suffix: s.portfolio.currency),
              _Kpi(
                  '未实现盈亏',
                  '${s.totalUnrealizedPnl >= 0 ? '+' : '-'}${fmt.format(s.totalUnrealizedPnl.abs())}',
                  color: s.totalUnrealizedPnl >= 0
                      ? AppColors.positive
                      : AppColors.negative),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _navVsBenchmarkCard(List<CandlePoint> nav, List<CandlePoint> bench) {
    if (nav.length < 2) return const SizedBox.shrink();
    final navRebased = _rebaseTo100(nav);
    final benchRebased = bench.length < 2 ? const <_RP>[] : _rebaseTo100(bench);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                _Title('组合 vs 沪深 300（rebased = 100）'),
                Spacer(),
                _Legend(color: AppColors.amber, label: '组合'),
                SizedBox(width: 12),
                _Legend(color: AppColors.info, label: '沪深 300'),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 200,
              child: _LineCompareChart(
                  navRebased: navRebased, benchRebased: benchRebased),
            ),
          ],
        ),
      ),
    );
  }

  Widget _drawdownCard(List<CandlePoint> nav) {
    if (nav.length < 2) return const SizedBox.shrink();
    final dd = Indicators.drawdownSeries(nav);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _Title('回撤曲线（drawdown）'),
            const SizedBox(height: 8),
            SizedBox(height: 140, child: _DrawdownChart(series: dd)),
          ],
        ),
      ),
    );
  }

  Widget _monthlyHeatmapCard(List<CandlePoint> nav) {
    final months = Indicators.monthlyReturns(nav);
    if (months.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _Title('月度收益热力图'),
            const SizedBox(height: 8),
            _MonthlyHeatmap(months: months),
          ],
        ),
      ),
    );
  }

  Widget _pnlCard(List<PortfolioAsset> top, List<PortfolioAsset> losers) {
    return Column(
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _Title('盈亏前 3'),
                const SizedBox(height: 6),
                for (final h in top.take(3))
                  _PnlRow(asset: h, color: AppColors.positive),
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
                const _Title('亏损前 3'),
                const SizedBox(height: 6),
                for (final h in losers.take(3))
                  _PnlRow(asset: h, color: AppColors.negative),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _kpiGrid(List<_Kpi> kpis) {
    return LayoutBuilder(builder: (ctx, c) {
      final cols = c.maxWidth > 540 ? 4 : (c.maxWidth > 380 ? 3 : 2);
      return GridView.count(
        crossAxisCount: cols,
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 2.4,
        children: [for (final k in kpis) _KpiBox(kpi: k)],
      );
    });
  }

  /// 把 NAV/价格序列首日归一到 100，方便和基准在同一坐标对比
  List<_RP> _rebaseTo100(List<CandlePoint> series) {
    if (series.isEmpty) return const [];
    final first = series.first.close;
    if (first == 0) return const [];
    return [
      for (final c in series) _RP(c.date, c.close / first * 100),
    ];
  }
}

class _RP {
  const _RP(this.date, this.value);
  final DateTime date;
  final double value;
}

class _Stats {
  const _Stats({
    this.cumulativeReturn,
    this.annualReturn,
    this.annualVol,
    this.sharpe,
    this.sortino,
    this.calmar,
    this.ir,
    this.maxDrawdown,
    this.upCapture,
    this.downCapture,
  });
  final double? cumulativeReturn;
  final double? annualReturn;
  final double? annualVol;
  final double? sharpe;
  final double? sortino;
  final double? calmar;
  final double? ir;
  final double? maxDrawdown;
  final double? upCapture;
  final double? downCapture;

  static _Stats compute(List<CandlePoint> nav, List<CandlePoint> bench) {
    if (nav.length < 5) return const _Stats();
    final cr = Indicators.cumulativeReturn(nav);
    final ar = Indicators.annualizedReturn(nav);
    final av = Indicators.annualizedVolatility(nav);
    final sh = Indicators.sharpeRatio(nav,
        riskFree: _PerformanceTabState._riskFree);
    final so = Indicators.sortinoRatio(nav,
        riskFree: _PerformanceTabState._riskFree);
    final cal = Indicators.calmarRatio(nav);
    final mdd = Indicators.maxDrawdown(nav).drawdown;
    double? ir;
    double? upC;
    double? dnC;
    if (bench.length >= 5) {
      ir = Indicators.informationRatio(nav, bench);
      final cap = Indicators.captureRatios(nav, bench);
      upC = cap.$1;
      dnC = cap.$2;
    }
    return _Stats(
      cumulativeReturn: cr,
      annualReturn: ar,
      annualVol: av,
      sharpe: sh,
      sortino: so,
      calmar: cal,
      ir: ir,
      maxDrawdown: mdd,
      upCapture: upC,
      downCapture: dnC,
    );
  }
}

class _Kpi {
  const _Kpi(this.label, this.value, {this.suffix, this.color});
  final String label;
  final String value;
  final String? suffix;
  final Color? color;
}

class _KpiBox extends StatelessWidget {
  const _KpiBox({required this.kpi});
  final _Kpi kpi;
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
          Text(kpi.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4)),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(kpi.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: kpi.color ?? AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w800)),
              ),
              if (kpi.suffix != null) ...[
                const SizedBox(width: 4),
                Text(kpi.suffix!,
                    style: TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 10,
                        fontWeight: FontWeight.w700)),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});
  final Color color;
  final String label;
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
            width: 12, height: 2, color: color),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(
                fontSize: 10,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class _LineCompareChart extends StatelessWidget {
  const _LineCompareChart(
      {required this.navRebased, required this.benchRebased});
  final List<_RP> navRebased;
  final List<_RP> benchRebased;

  @override
  Widget build(BuildContext context) {
    final navSpots = [
      for (var i = 0; i < navRebased.length; i++)
        FlSpot(i.toDouble(), navRebased[i].value)
    ];
    final benchSpots = <FlSpot>[];
    if (benchRebased.isNotEmpty && navRebased.isNotEmpty) {
      // 简单按 index 对齐：基准长度大概率不同，按比例缩放映射到 navRebased 的横轴
      for (var i = 0; i < navRebased.length; i++) {
        final ratio = i / (navRebased.length - 1).clamp(1, 1e9);
        final j = (ratio * (benchRebased.length - 1)).round();
        if (j >= 0 && j < benchRebased.length) {
          benchSpots.add(FlSpot(i.toDouble(), benchRebased[j].value));
        }
      }
    }
    final allValues = [
      for (final p in navRebased) p.value,
      for (final s in benchSpots) s.y,
    ];
    final minY = allValues.reduce(math.min);
    final maxY = allValues.reduce(math.max);
    final pad = (maxY - minY).abs() * 0.05 + 1;
    return LineChart(LineChartData(
      minY: minY - pad,
      maxY: maxY + pad,
      gridData: const FlGridData(show: false),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 36,
            getTitlesWidget: (v, _) => Text(v.toStringAsFixed(0),
                style: TextStyle(
                    fontSize: 9, color: AppColors.textTertiary)),
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 22,
            interval:
                (navRebased.length / 5).ceilToDouble().clamp(1, 9999),
            getTitlesWidget: (v, _) {
              final i = v.toInt();
              if (i < 0 || i >= navRebased.length) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  DateFormat('M/d').format(navRebased[i].date),
                  style: TextStyle(
                      fontSize: 9, color: AppColors.textTertiary),
                ),
              );
            },
          ),
        ),
        rightTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      lineBarsData: [
        LineChartBarData(
          spots: navSpots,
          color: AppColors.amber,
          isCurved: true,
          barWidth: 1.6,
          dotData: const FlDotData(show: false),
        ),
        if (benchSpots.isNotEmpty)
          LineChartBarData(
            spots: benchSpots,
            color: AppColors.info,
            isCurved: true,
            barWidth: 1.4,
            dotData: const FlDotData(show: false),
          ),
      ],
    ));
  }
}

class _DrawdownChart extends StatelessWidget {
  const _DrawdownChart({required this.series});
  final List<MapEntry<DateTime, double>> series;

  @override
  Widget build(BuildContext context) {
    if (series.length < 2) {
      return Center(
        child: Text('数据点过少',
            style: TextStyle(color: AppColors.textTertiary, fontSize: 11)),
      );
    }
    // 回撤值越大表示亏越多——绘制成负数（向下）
    final spots = [
      for (var i = 0; i < series.length; i++)
        FlSpot(i.toDouble(), -series[i].value * 100)
    ];
    final minY = spots.map((e) => e.y).reduce(math.min);
    return LineChart(LineChartData(
      minY: minY * 1.1 - 0.5,
      maxY: 0.5,
      gridData: const FlGridData(show: false),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 40,
            getTitlesWidget: (v, _) => Text('${v.toStringAsFixed(0)}%',
                style: TextStyle(
                    fontSize: 9, color: AppColors.textTertiary)),
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 22,
            interval: (series.length / 4).ceilToDouble().clamp(1, 9999),
            getTitlesWidget: (v, _) {
              final i = v.toInt();
              if (i < 0 || i >= series.length) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  DateFormat('M/d').format(series[i].key),
                  style: TextStyle(
                      fontSize: 9, color: AppColors.textTertiary),
                ),
              );
            },
          ),
        ),
        rightTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          color: AppColors.negative,
          isCurved: false,
          barWidth: 1.2,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
            show: true,
            color: AppColors.negative.withValues(alpha: 0.18),
          ),
        ),
      ],
    ));
  }
}

class _MonthlyHeatmap extends StatelessWidget {
  const _MonthlyHeatmap({required this.months});
  final List<MapEntry<DateTime, double>> months;

  @override
  Widget build(BuildContext context) {
    // 按年分组 → 每年一行 12 个月
    final years = <int, List<double?>>{};
    for (final m in months) {
      final y = m.key.year;
      years.putIfAbsent(y, () => List<double?>.filled(12, null));
      years[y]![m.key.month - 1] = m.value;
    }
    final ys = years.keys.toList()..sort();

    final maxAbs = months
        .map((m) => m.value.abs())
        .fold<double>(0, (a, b) => a > b ? a : b);

    return Column(
      children: [
        Row(
          children: [
            const SizedBox(width: 32),
            for (final m in const [
              'Jan','Feb','Mar','Apr','May','Jun',
              'Jul','Aug','Sep','Oct','Nov','Dec'
            ])
              Expanded(
                child: Center(
                  child: Text(m,
                      style: TextStyle(
                          fontSize: 9,
                          color: AppColors.textTertiary,
                          fontWeight: FontWeight.w700)),
                ),
              ),
            const SizedBox(width: 36),
          ],
        ),
        const SizedBox(height: 4),
        for (final y in ys) _row(y, years[y]!, maxAbs),
      ],
    );
  }

  Widget _row(int year, List<double?> vals, double maxAbs) {
    var sumLn = 0.0;
    var any = false;
    for (final v in vals) {
      if (v == null) continue;
      sumLn += math.log(1 + v);
      any = true;
    }
    final yearReturn = any ? math.exp(sumLn) - 1 : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: Text('$year',
                style: TextStyle(
                    fontSize: 10,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w800)),
          ),
          for (final v in vals)
            Expanded(
              child: AspectRatio(
                aspectRatio: 1,
                child: Padding(
                  padding: const EdgeInsets.all(1),
                  child: Container(
                    color: _colorFor(v, maxAbs),
                    alignment: Alignment.center,
                    child: v == null
                        ? null
                        : Text(
                            (v * 100).toStringAsFixed(1),
                            style: TextStyle(
                              fontSize: 8.5,
                              color: v.abs() / (maxAbs == 0 ? 1 : maxAbs) > 0.5
                                  ? Colors.white
                                  : AppColors.textPrimary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                  ),
                ),
              ),
            ),
          SizedBox(
            width: 36,
            child: Text(
              yearReturn == null
                  ? ''
                  : '${(yearReturn * 100).toStringAsFixed(1)}%',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: yearReturn == null
                    ? AppColors.textTertiary
                    : (yearReturn >= 0
                        ? AppColors.positive
                        : AppColors.negative),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _colorFor(double? v, double maxAbs) {
    if (v == null) return AppColors.bgRaised;
    if (maxAbs == 0) return AppColors.bgRaised;
    final intensity = (v.abs() / maxAbs).clamp(0.0, 1.0);
    final base = v >= 0 ? AppColors.positive : AppColors.negative;
    return Color.lerp(AppColors.bgRaised, base, intensity)!;
  }
}

class _PnlRow extends StatelessWidget {
  const _PnlRow({required this.asset, required this.color});
  final PortfolioAsset asset;
  final Color color;
  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.00');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${asset.name.isEmpty ? asset.symbol : asset.name}  ·  ${asset.symbol}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AppColors.textPrimary, fontSize: 11),
            ),
          ),
          Text(
            '${asset.unrealizedPnl >= 0 ? '+' : '-'}${fmt.format(asset.unrealizedPnl.abs())}',
            style: TextStyle(
                color: color, fontFamily: 'monospace', fontSize: 11),
          ),
          const SizedBox(width: 12),
          Text(
            '${asset.unrealizedPnlPercent >= 0 ? '+' : ''}${asset.unrealizedPnlPercent.toStringAsFixed(2)}%',
            style: TextStyle(
                color: color, fontWeight: FontWeight.w700, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title(this.text);
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

class _EmptyMsg extends StatelessWidget {
  const _EmptyMsg(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(text,
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
      ),
    );
  }
}
