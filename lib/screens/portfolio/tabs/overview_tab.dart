import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../state/portfolio_state.dart';
import '../../../theme/app_theme.dart';
import '../widgets/positions_table.dart';

class OverviewTab extends StatefulWidget {
  const OverviewTab({super.key});

  @override
  State<OverviewTab> createState() => _OverviewTabState();
}

class _OverviewTabState extends State<OverviewTab> {
  List<MapEntry<DateTime, double>>? _series;
  bool _loadingSeries = false;
  int _periodDays = 90;
  String? _seriesError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSeries());
  }

  Future<void> _loadSeries() async {
    setState(() {
      _loadingSeries = true;
      _seriesError = null;
    });
    try {
      final pts =
          await context.read<PortfolioState>().performanceSeries(days: _periodDays);
      if (!mounted) return;
      setState(() {
        _series = pts;
        _loadingSeries = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _seriesError = e.toString();
        _loadingSeries = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ps = context.watch<PortfolioState>();
    final summary = ps.currentSummary;

    return RefreshIndicator(
      onRefresh: () async {
        await ps.refreshQuotes();
        await _loadSeries();
      },
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (ps.loadingQuotes) const _LoadingBanner('正在拉取最新行情…'),
          if (ps.quoteError != null)
            _WarnBanner('行情更新部分失败：${ps.quoteError}'),
          _PerformanceCard(
            series: _series,
            loading: _loadingSeries,
            error: _seriesError,
            periodDays: _periodDays,
            onPeriodChanged: (d) {
              setState(() => _periodDays = d);
              _loadSeries();
            },
          ),
          const SizedBox(height: 12),
          PositionsTable(holdings: summary?.holdings ?? const []),
        ],
      ),
    );
  }
}

class _LoadingBanner extends StatelessWidget {
  const _LoadingBanner(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.bgRaised,
        border: Border.all(color: AppColors.borderDim),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Text(text,
              style: TextStyle(
                  color: AppColors.textSecondary, fontSize: 11)),
        ],
      ),
    );
  }
}

class _WarnBanner extends StatelessWidget {
  const _WarnBanner(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.bgRaised,
        border: Border.all(color: AppColors.warning),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber, color: AppColors.warning, size: 14),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 11)),
          ),
        ],
      ),
    );
  }
}

/// 组合走势卡片。
///
/// 原版直接画"市值随时间"折线，对普通用户不直观（同样的 +1 万对 100 万和
/// 10 万组合意义完全不同）。这里改成"累计收益率%"展示，并把周期收益、
/// 期间最大涨幅 / 最大回撤、起止市值一并放到 header，让用户一眼看明白
/// 这段时间到底赚了还是亏了、波动多大。
class _PerformanceCard extends StatelessWidget {
  const _PerformanceCard({
    required this.series,
    required this.loading,
    required this.error,
    required this.periodDays,
    required this.onPeriodChanged,
  });

  final List<MapEntry<DateTime, double>>? series;
  final bool loading;
  final String? error;
  final int periodDays;
  final ValueChanged<int> onPeriodChanged;

  static const _periods = [
    [7, '1W'],
    [30, '1M'],
    [90, '3M'],
    [180, '6M'],
    [365, '1Y'],
    [1825, '5Y'],
  ];

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('组合走势',
                    style: TextStyle(
                        color: AppColors.amber,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6)),
                const Spacer(),
                ..._periods.map((p) => _periodChip(p[0] as int, p[1] as String)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '相对周期起点的累计收益率',
              style: TextStyle(
                  color: AppColors.textTertiary, fontSize: 10),
            ),
            const SizedBox(height: 10),
            _summaryStrip(),
            const SizedBox(height: 8),
            SizedBox(
              height: 220,
              child: _chartArea(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _periodChip(int days, String label) {
    final selected = days == periodDays;
    return GestureDetector(
      onTap: () => onPeriodChanged(days),
      child: Container(
        margin: const EdgeInsets.only(left: 4),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: selected ? AppColors.amber : Colors.transparent,
          border: Border.all(
              color: selected ? AppColors.amber : AppColors.borderDim),
          borderRadius: BorderRadius.circular(2),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: selected ? Colors.black : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  /// 走势摘要条：累计收益、最大涨/回撤、起止市值。
  Widget _summaryStrip() {
    if (series == null || series!.length < 2) return const SizedBox.shrink();
    final stats = _Stats.from(series!);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          flex: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('周期累计收益',
                  style: TextStyle(
                      color: AppColors.textTertiary, fontSize: 10)),
              const SizedBox(height: 2),
              Text(
                _pct(stats.totalReturnPct),
                style: TextStyle(
                  color: _signColor(stats.totalReturnPct),
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  height: 1.0,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _miniStat('最高',
              _pct(stats.maxReturnPct), _signColor(stats.maxReturnPct)),
        ),
        Expanded(
          child: _miniStat('最大回撤',
              _pct(-stats.maxDrawdownPct), AppColors.danger),
        ),
      ],
    );
  }

  Widget _miniStat(String title, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: TextStyle(
                color: AppColors.textTertiary, fontSize: 10)),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.w800,
            height: 1.0,
          ),
        ),
      ],
    );
  }

  Widget _chartArea() {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Text(error!,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: AppColors.textTertiary, fontSize: 11)),
        ),
      );
    }
    if (series == null || series!.length < 2) {
      return Center(
        child: Text('暂无足够数据 — 加入更多品种或拉长周期',
            style: TextStyle(color: AppColors.textTertiary, fontSize: 11)),
      );
    }
    final pts = series!;
    final base = pts.first.value;
    // 起点为 0% 的"累计收益率"序列；首点全 0，避免被 0/0 干扰。
    final returns = base.abs() < 1e-9
        ? List<double>.filled(pts.length, 0)
        : [for (final e in pts) (e.value - base) / base * 100.0];
    final spots = [
      for (int i = 0; i < returns.length; i++)
        FlSpot(i.toDouble(), returns[i]),
    ];

    final lastIdx = returns.length - 1;
    final lastY = returns[lastIdx];
    final maxY = returns.reduce((a, b) => a > b ? a : b);
    final minY = returns.reduce((a, b) => a < b ? a : b);
    final span = (maxY - minY).abs();
    final pad = (span < 1 ? 1 : span) * 0.18;
    final isUp = lastY >= 0;
    final lineColor = isUp ? AppColors.positive : AppColors.danger;

    return LineChart(
      LineChartData(
        minY: minY - pad,
        maxY: maxY + pad,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval:
              (span / 4).clamp(0.5, double.infinity).toDouble(),
          getDrawingHorizontalLine: (_) => FlLine(
            color: AppColors.borderDim.withValues(alpha: 0.5),
            strokeWidth: 0.6,
            dashArray: const [3, 3],
          ),
        ),
        borderData: FlBorderData(show: false),
        // 0% 基准线 — 让用户一眼看出"赚了还是亏了"。
        extraLinesData: ExtraLinesData(
          horizontalLines: [
            HorizontalLine(
              y: 0,
              color: AppColors.textTertiary.withValues(alpha: 0.5),
              strokeWidth: 0.8,
              dashArray: const [4, 4],
              label: HorizontalLineLabel(
                show: true,
                alignment: Alignment.bottomRight,
                padding: const EdgeInsets.only(right: 4, bottom: 1),
                style: TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                ),
                labelResolver: (_) => '起点 0%',
              ),
            ),
          ],
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 38,
              getTitlesWidget: (v, _) => Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text(
                  '${v >= 0 ? '+' : ''}${v.toStringAsFixed(span < 2 ? 1 : 0)}%',
                  style: TextStyle(
                      fontSize: 9, color: AppColors.textTertiary),
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: (pts.length / 5).ceilToDouble().clamp(1, 9999),
              getTitlesWidget: (v, _) {
                final idx = v.toInt();
                if (idx < 0 || idx >= pts.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    DateFormat('M/d').format(pts[idx].key),
                    style: TextStyle(
                        fontSize: 9, color: AppColors.textTertiary),
                  ),
                );
              },
            ),
          ),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        // 触摸气泡显示日期 + 累计收益 %。
        lineTouchData: LineTouchData(
          handleBuiltInTouches: true,
          touchTooltipData: LineTouchTooltipData(
            tooltipRoundedRadius: 4,
            tooltipPadding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            getTooltipColor: (_) =>
                AppColors.bgRaised.withValues(alpha: 0.95),
            getTooltipItems: (touched) {
              return touched.map((spot) {
                final idx = spot.x.toInt().clamp(0, pts.length - 1);
                final date = DateFormat('yyyy-MM-dd').format(pts[idx].key);
                final v = returns[idx];
                return LineTooltipItem(
                  '$date\n${_pct(v)}',
                  TextStyle(
                    color: _signColor(v),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                );
              }).toList();
            },
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            color: lineColor,
            isCurved: true,
            barWidth: 1.8,
            // 末点用大点标出"现在的位置"。
            dotData: FlDotData(
              show: true,
              checkToShowDot: (s, _) => s.x.toInt() == lastIdx,
              getDotPainter: (s, _, __, ___) => FlDotCirclePainter(
                radius: 3.5,
                color: lineColor,
                strokeWidth: 1.5,
                strokeColor: AppColors.bgBase,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              color: lineColor.withValues(alpha: 0.10),
            ),
          ),
        ],
      ),
    );
  }

  static String _pct(double v) {
    final sign = v > 0 ? '+' : (v == 0 ? '' : '');
    return '$sign${v.toStringAsFixed(2)}%';
  }

  static Color _signColor(double v) {
    if (v > 0.001) return AppColors.positive;
    if (v < -0.001) return AppColors.danger;
    return AppColors.textSecondary;
  }
}

class _Stats {
  _Stats({
    required this.totalReturnPct,
    required this.maxReturnPct,
    required this.maxDrawdownPct,
  });

  final double totalReturnPct;
  final double maxReturnPct;
  final double maxDrawdownPct;

  factory _Stats.from(List<MapEntry<DateTime, double>> pts) {
    final base = pts.first.value;
    if (base.abs() < 1e-9) {
      return _Stats(
          totalReturnPct: 0, maxReturnPct: 0, maxDrawdownPct: 0);
    }
    final last = pts.last.value;
    final total = (last - base) / base * 100.0;
    double maxReturn = 0;
    double maxDD = 0;
    double peak = pts.first.value;
    for (final e in pts) {
      final r = (e.value - base) / base * 100.0;
      if (r > maxReturn) maxReturn = r;
      if (e.value > peak) peak = e.value;
      if (peak > 0) {
        final dd = (peak - e.value) / peak * 100.0;
        if (dd > maxDD) maxDD = dd;
      }
    }
    return _Stats(
      totalReturnPct: total,
      maxReturnPct: maxReturn,
      maxDrawdownPct: maxDD,
    );
  }
}
