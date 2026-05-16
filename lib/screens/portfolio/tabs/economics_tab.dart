import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../models/instrument.dart';
import '../../../services/tushare_service.dart';
import '../../../theme/app_theme.dart';

/// "经济" tab — quick read on a few benchmark indices via Tushare. Hosts
/// the index history chart used as a market-context backdrop in the
/// PC EconomicsView. Mobile version focuses on three indices the user can
/// switch between.
class EconomicsTab extends StatefulWidget {
  const EconomicsTab({super.key});

  @override
  State<EconomicsTab> createState() => _EconomicsTabState();
}

class _EconomicsTabState extends State<EconomicsTab> {
  static const _indices = [
    ['000001.SH', '上证指数'],
    ['000300.SH', '沪深300'],
    ['399001.SZ', '深证成指'],
    ['000688.SH', '科创50'],
    ['399006.SZ', '创业板指'],
  ];

  String _ts = '000300.SH';
  bool _loading = false;
  String? _error;
  List<CandlePoint> _series = const [];

  final TushareService _svc = TushareService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final pts = await _svc.indexDaily(
        tsCode: _ts,
        startDate: _ymd(DateTime.now().subtract(const Duration(days: 365))),
        endDate: _ymd(DateTime.now()),
      );
      setState(() {
        _series = pts;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}'
      '${d.month.toString().padLeft(2, '0')}'
      '${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text('指数行情',
                          style: TextStyle(
                              color: AppColors.amber,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.6)),
                    ),
                    DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _ts,
                        dropdownColor: AppColors.bgRaised,
                        style: TextStyle(
                            color: AppColors.textPrimary, fontSize: 12),
                        items: [
                          for (final p in _indices)
                            DropdownMenuItem(
                                value: p[0], child: Text('${p[1]}  ${p[0]}')),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() => _ts = v);
                          _load();
                        },
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh,
                          size: 16, color: AppColors.amber),
                      onPressed: _load,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(height: 220, child: _chart()),
                if (_series.isNotEmpty) _stats(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _chart() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
          child: Padding(
        padding: const EdgeInsets.all(8),
        child: Text(_error!,
            textAlign: TextAlign.center,
            style: TextStyle(
                color: AppColors.textTertiary, fontSize: 11)),
      ));
    }
    if (_series.length < 2) {
      return Center(
        child: Text('暂无数据',
            style: TextStyle(color: AppColors.textTertiary, fontSize: 11)),
      );
    }
    final spots = [
      for (int i = 0; i < _series.length; i++)
        FlSpot(i.toDouble(), _series[i].close),
    ];
    final minY = _series.map((e) => e.close).reduce((a, b) => a < b ? a : b);
    final maxY = _series.map((e) => e.close).reduce((a, b) => a > b ? a : b);
    return LineChart(LineChartData(
      minY: minY * 0.99,
      maxY: maxY * 1.01,
      gridData: const FlGridData(show: false),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 50,
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
            interval: (_series.length / 5).ceilToDouble().clamp(1, 9999),
            getTitlesWidget: (v, _) {
              final i = v.toInt();
              if (i < 0 || i >= _series.length) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  DateFormat('M/d').format(_series[i].date),
                  style: TextStyle(
                      fontSize: 9, color: AppColors.textTertiary),
                ),
              );
            },
          ),
        ),
        topTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          color: AppColors.amber,
          isCurved: true,
          barWidth: 1.6,
          dotData: const FlDotData(show: false),
        ),
      ],
    ));
  }

  Widget _stats() {
    final last = _series.last;
    final first = _series.first;
    final ret = (last.close / first.close - 1) * 100;
    final fmt = NumberFormat('#,##0.00');
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 16,
        runSpacing: 4,
        children: [
          _kv('最新', fmt.format(last.close)),
          _kv('近 1Y 收益', '${ret >= 0 ? "+" : ""}${ret.toStringAsFixed(2)}%',
              color: ret >= 0 ? AppColors.positive : AppColors.negative),
          _kv('日期', DateFormat('yyyy-MM-dd').format(last.date)),
        ],
      ),
    );
  }

  Widget _kv(String k, String v, {Color? color}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$k：',
            style: TextStyle(
                color: AppColors.textTertiary, fontSize: 11)),
        Text(v,
            style: TextStyle(
                color: color ?? AppColors.textPrimary,
                fontWeight: FontWeight.w800,
                fontFamily: 'monospace',
                fontSize: 11)),
      ],
    );
  }
}
