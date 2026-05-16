import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../models/portfolio.dart';
import '../../../state/portfolio_state.dart';
import '../../../theme/app_theme.dart';
import '../widgets/positions_table.dart';
import '../widgets/sector_donut.dart';

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
            currency: summary?.portfolio.currency ?? 'CNY',
            onPeriodChanged: (d) {
              setState(() => _periodDays = d);
              _loadSeries();
            },
          ),
          const SizedBox(height: 12),
          if (summary != null && summary.holdings.isNotEmpty)
            _SectorBreakdownCard(summary: summary),
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

class _PerformanceCard extends StatelessWidget {
  const _PerformanceCard({
    required this.series,
    required this.loading,
    required this.error,
    required this.periodDays,
    required this.currency,
    required this.onPeriodChanged,
  });

  final List<MapEntry<DateTime, double>>? series;
  final bool loading;
  final String? error;
  final int periodDays;
  final String currency;
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
            const SizedBox(height: 12),
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
    final spots = [
      for (int i = 0; i < pts.length; i++)
        FlSpot(i.toDouble(), pts[i].value),
    ];
    final minY = pts.map((e) => e.value).reduce((a, b) => a < b ? a : b);
    final maxY = pts.map((e) => e.value).reduce((a, b) => a > b ? a : b);
    final pad = (maxY - minY).abs() * 0.05 + 1;

    return LineChart(
      LineChartData(
        minY: minY - pad,
        maxY: maxY + pad,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 60,
              getTitlesWidget: (v, _) => Text(
                NumberFormat.compact().format(v),
                style: TextStyle(
                    fontSize: 9, color: AppColors.textTertiary),
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
        lineTouchData: const LineTouchData(handleBuiltInTouches: true),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            color: AppColors.amber,
            isCurved: true,
            barWidth: 1.6,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: AppColors.amber.withValues(alpha: 0.10),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectorBreakdownCard extends StatelessWidget {
  const _SectorBreakdownCard({required this.summary});
  final PortfolioSummary summary;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('行业分布',
                style: TextStyle(
                    color: AppColors.amber,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6)),
            const SizedBox(height: 8),
            SectorDonut(weights: summary.sectorWeights),
          ],
        ),
      ),
    );
  }
}
