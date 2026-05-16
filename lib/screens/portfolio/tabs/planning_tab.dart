import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../models/instrument.dart';
import '../../../services/indicators.dart';
import '../../../state/portfolio_state.dart';
import '../../../theme/app_theme.dart';

/// "规划" tab — 两种工具：
///   1. 复利预估（保留）
///   2. 基于历史日收益的 Monte Carlo 组合推演（500 条路径，给出 P10/P50/P90）
class PlanningTab extends StatefulWidget {
  const PlanningTab({super.key});

  @override
  State<PlanningTab> createState() => _PlanningTabState();
}

class _PlanningTabState extends State<PlanningTab> {
  // 复利
  double _annualReturn = 8;
  double _years = 10;
  double _monthlyContrib = 1000;

  // Monte Carlo
  double _mcYears = 5;
  double _mcMonthly = 1000;
  int _mcPaths = 500;
  bool _mcRunning = false;
  _McResult? _mcResult;

  @override
  Widget build(BuildContext context) {
    final ps = context.watch<PortfolioState>();
    final s = ps.currentSummary;
    if (s == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text('选择一个组合后即可使用规划工具。',
              style: TextStyle(color: AppColors.textSecondary)),
        ),
      );
    }
    final fmt = NumberFormat('#,##0.00');
    final start = s.totalMarketValue;
    final monthlyRate = math.pow(1 + _annualReturn / 100, 1 / 12) - 1;
    final months = (_years * 12).round();
    double future = start;
    for (int i = 0; i < months; i++) {
      future = future * (1 + monthlyRate) + _monthlyContrib;
    }
    final contrib = _monthlyContrib * months;
    final earned = future - start - contrib;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _T('未来值规划（复利公式）'),
                const SizedBox(height: 8),
                _slider('年化收益率假设',
                    '${_annualReturn.toStringAsFixed(1)}%',
                    _annualReturn, -10, 30, 80, (v) {
                  setState(() => _annualReturn = v);
                }),
                _slider('投资期限', '${_years.toStringAsFixed(0)} 年',
                    _years, 1, 40, 39, (v) {
                  setState(() => _years = v);
                }),
                _slider(
                    '每月新增投入',
                    '${fmt.format(_monthlyContrib)} ${s.portfolio.currency}',
                    _monthlyContrib, 0, 50000, 100, (v) {
                  setState(() => _monthlyContrib = v);
                }),
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
                const _T('预测结果'),
                const SizedBox(height: 8),
                _row('当前市值', fmt.format(start), s.portfolio.currency),
                _row('累计追加投入', fmt.format(contrib), s.portfolio.currency),
                _row('累计收益', fmt.format(earned), s.portfolio.currency,
                    color: earned >= 0
                        ? AppColors.positive
                        : AppColors.negative),
                Divider(color: AppColors.borderDim, height: 24),
                _row('${_years.toStringAsFixed(0)} 年后价值',
                    fmt.format(future), s.portfolio.currency,
                    big: true),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _mcCard(s.totalMarketValue, s.portfolio.currency),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _T('提示'),
                const SizedBox(height: 6),
                Text(
                    '· 复利模拟未考虑税费、汇率与黑天鹅事件；\n'
                    '· Monte Carlo 基于持仓近 252 日历史，对收益率分布做有放回抽样；\n'
                    '· P10/P50/P90 表示在 $_mcPaths 条路径中累计占比 10/50/90 处的终值。',
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

  Widget _mcCard(double startValue, String currency) {
    final fmt = NumberFormat('#,##0');
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _T('Monte Carlo 推演（基于持仓历史）'),
            const SizedBox(height: 8),
            _slider('投资期限', '${_mcYears.toStringAsFixed(0)} 年', _mcYears, 1, 20,
                19, (v) {
              setState(() => _mcYears = v);
            }),
            _slider(
                '每月新增投入',
                '${NumberFormat('#,##0').format(_mcMonthly)} $currency',
                _mcMonthly, 0, 30000, 60, (v) {
              setState(() => _mcMonthly = v);
            }),
            _slider('路径数量', '$_mcPaths', _mcPaths.toDouble(), 100, 2000, 19,
                (v) {
              setState(() => _mcPaths = v.round());
            }),
            const SizedBox(height: 8),
            Row(
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.science_outlined, size: 16),
                  label: Text(_mcRunning ? '运行中…' : '运行 Monte Carlo'),
                  onPressed: _mcRunning ? null : _runMc,
                ),
              ],
            ),
            if (_mcResult != null) ...[
              const SizedBox(height: 12),
              _mcResultView(_mcResult!, startValue, currency, fmt),
            ],
          ],
        ),
      ),
    );
  }

  Widget _mcResultView(
      _McResult r, double startValue, String currency, NumberFormat fmt) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 6,
          children: [
            _kv('当前市值', '${fmt.format(startValue)} $currency'),
            _kv('累计投入', '${fmt.format(r.totalContrib)} $currency'),
            _kv('P10 终值', '${fmt.format(r.p10)} $currency',
                color: AppColors.negative),
            _kv('P50 终值', '${fmt.format(r.p50)} $currency'),
            _kv('P90 终值', '${fmt.format(r.p90)} $currency',
                color: AppColors.positive),
            _kv('盈利路径占比',
                '${(r.winRate * 100).toStringAsFixed(1)}%',
                color: r.winRate >= 0.5
                    ? AppColors.positive
                    : AppColors.negative),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(height: 220, child: _McChart(result: r)),
      ],
    );
  }

  Future<void> _runMc() async {
    setState(() {
      _mcRunning = true;
      _mcResult = null;
    });
    try {
      final ps = context.read<PortfolioState>();
      final s = ps.currentSummary;
      if (s == null || s.holdings.isEmpty) {
        return;
      }
      final histories = await ps.ensureHistories(days: 252);
      // 拼出每日组合收益率序列
      final dates = <DateTime>{};
      for (final cs in histories.values) {
        for (final c in cs) {
          dates.add(DateTime(c.date.year, c.date.month, c.date.day));
        }
      }
      final sorted = dates.toList()..sort();

      // 构造 NAV 序列
      final navByDate = <DateTime, double>{};
      for (final d in sorted) {
        double sum = 0;
        for (final h in s.holdings) {
          final cs = histories[h.symbol] ?? const [];
          double? lastClose;
          for (final c in cs) {
            if (!c.date.isAfter(d)) {
              lastClose = c.close;
            } else {
              break;
            }
          }
          if (lastClose != null) sum += lastClose * h.quantity;
        }
        if (sum > 0) navByDate[d] = sum;
      }
      final navList = (navByDate.entries.toList()
            ..sort((a, b) => a.key.compareTo(b.key)))
          .toList();
      if (navList.length < 30) {
        if (!mounted) return;
        setState(() {});
        return;
      }
      final navCandles = [
        for (final e in navList) CandlePoint(date: e.key, close: e.value)
      ];
      final returns = Indicators.dailyReturns(navCandles);
      if (returns.isEmpty) return;

      final years = _mcYears.round();
      final monthly = _mcMonthly;
      final paths = _mcPaths;
      final result = await _simulate(
        returns: returns,
        startValue: s.totalMarketValue,
        years: years,
        monthlyContribution: monthly,
        paths: paths,
      );
      if (!mounted) return;
      setState(() {
        _mcResult = result;
      });
    } finally {
      if (mounted) setState(() => _mcRunning = false);
    }
  }

  Future<_McResult> _simulate({
    required List<double> returns,
    required double startValue,
    required int years,
    required double monthlyContribution,
    required int paths,
  }) async {
    final rnd = math.Random();
    const tradingDays = 252;
    final totalDays = years * tradingDays;
    final monthDays = (tradingDays / 12).round();

    final allPaths = List<List<double>>.generate(paths, (_) {
      double v = startValue;
      final out = <double>[v];
      for (var d = 1; d <= totalDays; d++) {
        final r = returns[rnd.nextInt(returns.length)];
        v *= (1 + r);
        if (d % monthDays == 0) v += monthlyContribution;
        out.add(v);
      }
      return out;
    });

    // 终值分布
    final ends = [for (final p in allPaths) p.last]..sort();
    double pct(double q) {
      final idx = (q * (ends.length - 1)).round().clamp(0, ends.length - 1);
      return ends[idx];
    }

    final p10 = pct(0.10);
    final p50 = pct(0.50);
    final p90 = pct(0.90);
    final totalContrib =
        monthlyContribution * (years * 12);
    final invested = startValue + totalContrib;
    final wins = ends.where((v) => v > invested).length;
    final winRate = wins / ends.length;

    // 计算 P10/P50/P90 时间序列（按时间点取每点的分位数）
    final n = allPaths.first.length;
    final p10Series = List<double>.filled(n, 0);
    final p50Series = List<double>.filled(n, 0);
    final p90Series = List<double>.filled(n, 0);
    for (var t = 0; t < n; t++) {
      final col = [for (final p in allPaths) p[t]]..sort();
      p10Series[t] = col[(0.10 * (col.length - 1)).round()];
      p50Series[t] = col[(0.50 * (col.length - 1)).round()];
      p90Series[t] = col[(0.90 * (col.length - 1)).round()];
    }

    return _McResult(
      p10: p10,
      p50: p50,
      p90: p90,
      winRate: winRate,
      totalContrib: totalContrib,
      p10Series: p10Series,
      p50Series: p50Series,
      p90Series: p90Series,
      stepDays: 1,
    );
  }

  // ── UI helpers ─────────────────────────────────────────────────────────

  Widget _kv(String label, String value, {Color? color}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label：',
            style: TextStyle(color: AppColors.textTertiary, fontSize: 11)),
        Text(value,
            style: TextStyle(
                color: color ?? AppColors.textPrimary,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w800,
                fontSize: 12)),
      ],
    );
  }

  Widget _slider(String label, String value, double v, double min, double max,
      int divisions, ValueChanged<double> onChanged) {
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
                          color: AppColors.textSecondary, fontSize: 11))),
              Text(value,
                  style: const TextStyle(
                      color: AppColors.amber,
                      fontWeight: FontWeight.w800,
                      fontSize: 12)),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: AppColors.amber,
              inactiveTrackColor: AppColors.borderDim,
              thumbColor: AppColors.amber,
              overlayColor: AppColors.amber.withValues(alpha: 0.15),
              trackHeight: 2.5,
            ),
            child: Slider(
                value: v,
                min: min,
                max: max,
                divisions: divisions,
                onChanged: onChanged),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value, String suffix,
      {bool big = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Text(label,
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 12)),
          ),
          Text(value,
              style: TextStyle(
                  color: color ?? AppColors.textPrimary,
                  fontFamily: 'monospace',
                  fontSize: big ? 18 : 13,
                  fontWeight: FontWeight.w800)),
          const SizedBox(width: 4),
          Text(suffix,
              style: TextStyle(
                  color: AppColors.textTertiary, fontSize: 11)),
        ],
      ),
    );
  }
}

class _McResult {
  const _McResult({
    required this.p10,
    required this.p50,
    required this.p90,
    required this.winRate,
    required this.totalContrib,
    required this.p10Series,
    required this.p50Series,
    required this.p90Series,
    required this.stepDays,
  });
  final double p10;
  final double p50;
  final double p90;
  final double winRate;
  final double totalContrib;
  final List<double> p10Series;
  final List<double> p50Series;
  final List<double> p90Series;
  final int stepDays;
}

class _McChart extends StatelessWidget {
  const _McChart({required this.result});
  final _McResult result;

  @override
  Widget build(BuildContext context) {
    final n = result.p50Series.length;
    // 为可读性按周降采样
    final stride = math.max(1, n ~/ 200);
    final p10 = <FlSpot>[];
    final p50 = <FlSpot>[];
    final p90 = <FlSpot>[];
    for (var i = 0; i < n; i += stride) {
      p10.add(FlSpot(i.toDouble(), result.p10Series[i]));
      p50.add(FlSpot(i.toDouble(), result.p50Series[i]));
      p90.add(FlSpot(i.toDouble(), result.p90Series[i]));
    }
    final minY = result.p10Series.reduce(math.min) * 0.95;
    final maxY = result.p90Series.reduce(math.max) * 1.05;

    return LineChart(LineChartData(
      minY: minY,
      maxY: maxY,
      gridData: const FlGridData(show: false),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 50,
            getTitlesWidget: (v, _) => Text(
              NumberFormat.compact().format(v),
              style: TextStyle(fontSize: 9, color: AppColors.textTertiary),
            ),
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 22,
            interval: (n / 5).ceilToDouble().clamp(1, 1e9),
            getTitlesWidget: (v, _) {
              final years = v / 252;
              return Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('${years.toStringAsFixed(1)}Y',
                    style: TextStyle(
                        fontSize: 9, color: AppColors.textTertiary)),
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
          spots: p90,
          color: AppColors.positive,
          barWidth: 1.2,
          isCurved: true,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
            show: true,
            color: AppColors.positive.withValues(alpha: 0.08),
          ),
        ),
        LineChartBarData(
          spots: p50,
          color: AppColors.amber,
          barWidth: 1.6,
          isCurved: true,
          dotData: const FlDotData(show: false),
        ),
        LineChartBarData(
          spots: p10,
          color: AppColors.negative,
          barWidth: 1.2,
          isCurved: true,
          dotData: const FlDotData(show: false),
        ),
      ],
    ));
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
