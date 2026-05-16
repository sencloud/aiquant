import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/instrument.dart';
import '../../models/portfolio.dart';
import '../../services/indicators.dart';
import '../../services/portfolio_repository.dart';
import '../../services/tushare_service.dart';
import '../../theme/app_theme.dart';

/// 多组合对比页面：选 2 个或更多组合，并排展示
///   - KPI（市值/累计收益/Sharpe/Sortino/MaxDD）
///   - rebased = 100 的 NAV 对比图
class PortfolioCompareScreen extends StatefulWidget {
  const PortfolioCompareScreen({super.key});

  @override
  State<PortfolioCompareScreen> createState() => _PortfolioCompareScreenState();
}

class _PortfolioCompareScreenState extends State<PortfolioCompareScreen> {
  static const _windowDays = 252;
  static const _palette = [
    AppColors.amber,
    AppColors.info,
    AppColors.positive,
    AppColors.negative,
    Color(0xFF7C3AED),
    Color(0xFF0891B2),
  ];

  final _repo = PortfolioRepository();
  final _tushare = TushareService();

  Set<String> _selectedIds = {};
  bool _loading = false;
  Map<String, _ComparePoint> _data = {};

  @override
  void initState() {
    super.initState();
    final all = _repo.allPortfolios();
    _selectedIds = {for (final p in all.take(2)) p.id};
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    final all = _repo.allPortfolios();
    return Scaffold(
      appBar: AppBar(title: const Text('多组合对比')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _Title('选择要对比的组合'),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      for (final p in all)
                        FilterChip(
                          label: Text(p.name),
                          selected: _selectedIds.contains(p.id),
                          onSelected: (v) {
                            setState(() {
                              if (v) {
                                _selectedIds.add(p.id);
                              } else {
                                _selectedIds.remove(p.id);
                              }
                            });
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        icon: const Icon(Icons.play_arrow, size: 16),
                        label: Text(_loading ? '加载中…' : '运行对比'),
                        onPressed: _loading || _selectedIds.length < 2
                            ? null
                            : _load,
                      ),
                      const SizedBox(width: 8),
                      if (_selectedIds.length < 2)
                        Text('至少选择 2 个组合',
                            style: TextStyle(
                                color: AppColors.textTertiary, fontSize: 11)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_data.isNotEmpty) ...[
            _kpiTable(all),
            const SizedBox(height: 12),
            _navChartCard(),
          ],
        ],
      ),
    );
  }

  Future<void> _load() async {
    if (_selectedIds.length < 2) return;
    setState(() => _loading = true);
    final out = <String, _ComparePoint>{};
    for (final id in _selectedIds) {
      try {
        final cp = await _buildPoint(id);
        if (cp != null) out[id] = cp;
      } catch (_) {/* skip */}
    }
    if (!mounted) return;
    setState(() {
      _data = out;
      _loading = false;
    });
  }

  Future<_ComparePoint?> _buildPoint(String portfolioId) async {
    final p = _repo.allPortfolios().firstWhere((e) => e.id == portfolioId);
    final holdings = _repo.holdingsFor(portfolioId);
    if (holdings.isEmpty) return null;

    // 拉每只持仓的历史
    final histories = <String, List<CandlePoint>>{};
    final start = DateTime.now().subtract(const Duration(days: _windowDays + 14));
    for (final h in holdings) {
      try {
        histories[h.symbol] =
            await _tushare.historyFor(h.symbol, start: start, end: DateTime.now());
      } catch (_) {
        histories[h.symbol] = const [];
      }
    }

    // NAV
    final dates = <DateTime>{};
    for (final cs in histories.values) {
      for (final c in cs) {
        dates.add(DateTime(c.date.year, c.date.month, c.date.day));
      }
    }
    final sorted = dates.toList()..sort();
    final nav = <CandlePoint>[];
    for (final d in sorted) {
      double sum = 0;
      for (final h in holdings) {
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
      if (sum > 0) nav.add(CandlePoint(date: d, close: sum));
    }
    if (nav.length < 5) return null;

    // KPI
    final cum = Indicators.cumulativeReturn(nav);
    final ann = Indicators.annualizedReturn(nav);
    final vol = Indicators.annualizedVolatility(nav);
    final sh = Indicators.sharpeRatio(nav, riskFree: 0.03);
    final so = Indicators.sortinoRatio(nav, riskFree: 0.03);
    final mdd = Indicators.maxDrawdown(nav).drawdown;
    final cal = Indicators.calmarRatio(nav);
    final mv = holdings.fold<double>(0, (s, h) {
      final last = histories[h.symbol]?.lastOrNull?.close ?? h.avgBuyPrice;
      return s + last * h.quantity;
    });
    return _ComparePoint(
      portfolio: p,
      nav: nav,
      marketValue: mv,
      cumulativeReturn: cum,
      annualReturn: ann,
      annualVol: vol,
      sharpe: sh,
      sortino: so,
      calmar: cal,
      maxDrawdown: mdd,
    );
  }

  Widget _kpiTable(List<Portfolio> all) {
    final entries = _data.entries.toList();
    final fmt = NumberFormat('#,##0');
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columnSpacing: 16,
            headingRowHeight: 28,
            dataRowMinHeight: 28,
            dataRowMaxHeight: 32,
            columns: const [
              DataColumn(label: Text('组合')),
              DataColumn(label: Text('市值'), numeric: true),
              DataColumn(label: Text('累计'), numeric: true),
              DataColumn(label: Text('年化'), numeric: true),
              DataColumn(label: Text('波动'), numeric: true),
              DataColumn(label: Text('Sharpe'), numeric: true),
              DataColumn(label: Text('Sortino'), numeric: true),
              DataColumn(label: Text('Calmar'), numeric: true),
              DataColumn(label: Text('MaxDD'), numeric: true),
            ],
            rows: [
              for (var i = 0; i < entries.length; i++)
                DataRow(cells: [
                  DataCell(Row(
                    children: [
                      Container(
                          width: 10,
                          height: 10,
                          color: _palette[i % _palette.length]),
                      const SizedBox(width: 6),
                      Text(entries[i].value.portfolio.name,
                          style: TextStyle(
                              color: AppColors.textPrimary, fontSize: 11)),
                    ],
                  )),
                  DataCell(_num(fmt.format(entries[i].value.marketValue))),
                  DataCell(_pct(entries[i].value.cumulativeReturn)),
                  DataCell(_pct(entries[i].value.annualReturn)),
                  DataCell(_pct(entries[i].value.annualVol)),
                  DataCell(_num(entries[i].value.sharpe.toStringAsFixed(2))),
                  DataCell(_num(entries[i].value.sortino.toStringAsFixed(2))),
                  DataCell(_num(entries[i].value.calmar.toStringAsFixed(2))),
                  DataCell(_pct(-entries[i].value.maxDrawdown,
                      forceColor: AppColors.negative)),
                ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _num(String s) => Text(s,
      style: TextStyle(
          color: AppColors.textPrimary,
          fontFamily: 'monospace',
          fontSize: 11));

  Widget _pct(double v, {Color? forceColor}) {
    final c = forceColor ?? (v >= 0 ? AppColors.positive : AppColors.negative);
    return Text('${v >= 0 ? '+' : ''}${(v * 100).toStringAsFixed(2)}%',
        style: TextStyle(
            color: c,
            fontFamily: 'monospace',
            fontSize: 11,
            fontWeight: FontWeight.w800));
  }

  Widget _navChartCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _Title('NAV 对比（rebased = 100）'),
            const SizedBox(height: 6),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                for (var i = 0; i < _data.length; i++)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                          width: 12,
                          height: 2,
                          color: _palette[i % _palette.length]),
                      const SizedBox(width: 4),
                      Text(_data.values.elementAt(i).portfolio.name,
                          style: TextStyle(
                              color: AppColors.textSecondary, fontSize: 10)),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 6),
            SizedBox(height: 240, child: _CompareChart(data: _data)),
          ],
        ),
      ),
    );
  }
}

class _ComparePoint {
  const _ComparePoint({
    required this.portfolio,
    required this.nav,
    required this.marketValue,
    required this.cumulativeReturn,
    required this.annualReturn,
    required this.annualVol,
    required this.sharpe,
    required this.sortino,
    required this.calmar,
    required this.maxDrawdown,
  });
  final Portfolio portfolio;
  final List<CandlePoint> nav;
  final double marketValue;
  final double cumulativeReturn;
  final double annualReturn;
  final double annualVol;
  final double sharpe;
  final double sortino;
  final double calmar;
  final double maxDrawdown;
}

class _CompareChart extends StatelessWidget {
  const _CompareChart({required this.data});
  final Map<String, _ComparePoint> data;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return Center(
          child: Text('暂无数据',
              style: TextStyle(color: AppColors.textTertiary, fontSize: 11)));
    }
    const palette = _PortfolioCompareScreenState._palette;
    // 对每条 NAV，rebased = first / 100，按 index 画
    final allBars = <LineChartBarData>[];
    var idx = 0;
    final allValues = <double>[];
    for (final cp in data.values) {
      if (cp.nav.length < 2) {
        idx++;
        continue;
      }
      final first = cp.nav.first.close;
      if (first <= 0) {
        idx++;
        continue;
      }
      final spots = [
        for (var i = 0; i < cp.nav.length; i++)
          FlSpot(i.toDouble(), cp.nav[i].close / first * 100)
      ];
      allValues.addAll(spots.map((e) => e.y));
      allBars.add(LineChartBarData(
        spots: spots,
        color: palette[idx % palette.length],
        isCurved: true,
        barWidth: 1.6,
        dotData: const FlDotData(show: false),
      ));
      idx++;
    }
    if (allValues.isEmpty) {
      return Center(
          child: Text('暂无数据',
              style: TextStyle(color: AppColors.textTertiary, fontSize: 11)));
    }
    final minY = allValues.reduce(math.min);
    final maxY = allValues.reduce(math.max);
    final maxX = allBars.map((b) => b.spots.length).reduce(math.max).toDouble();

    return LineChart(LineChartData(
      minY: minY * 0.98,
      maxY: maxY * 1.02,
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
            interval: (maxX / 5).ceilToDouble().clamp(1, 1e9),
            getTitlesWidget: (v, _) => Text('${(v / 22).toStringAsFixed(0)}M',
                style: TextStyle(
                    fontSize: 9, color: AppColors.textTertiary)),
          ),
        ),
        rightTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      lineBarsData: allBars,
    ));
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
