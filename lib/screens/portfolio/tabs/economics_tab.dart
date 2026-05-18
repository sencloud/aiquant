import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../models/instrument.dart';
import '../../../services/tushare_service.dart';
import '../../../theme/app_theme.dart';

/// "经济" tab — 真宏观看板：
///   - CPI / PPI / PMI / M2 / Shibor 1Y 最新读数 + 趋势线
///   - 沪深 300 / 上证 50 / 中证 500 的 PE / PB 在 5 年历史百分位
///   - 指数行情图（沪深 300 等）
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

  // 估值百分位的目标指数
  static const _valuationIndices = [
    ['000300.SH', '沪深300'],
    ['000016.SH', '上证50'],
    ['000905.SH', '中证500'],
  ];

  String _ts = '000300.SH';
  bool _loading = false;
  String? _error;
  List<CandlePoint> _series = const [];

  // 宏观系列：[(month, value)]
  List<MapEntry<String, double>> _cpi = const [];
  List<MapEntry<String, double>> _ppi = const [];
  List<MapEntry<String, double>> _pmiManu = const [];
  List<MapEntry<String, double>> _m2 = const [];
  List<MapEntry<String, double>> _shibor1y = const [];

  // 估值百分位
  List<_ValuationStat> _valuations = const [];

  bool _macroLoading = true;
  String? _macroError;

  final TushareService _svc = TushareService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();
      _loadMacro();
      _loadValuations();
    });
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

  Future<void> _loadMacro() async {
    setState(() {
      _macroLoading = true;
      _macroError = null;
    });
    try {
      final results = await Future.wait([
        _fetchMonthlySeries(
            apiName: 'cn_cpi', monthField: 'month', valueField: 'nt_yoy'),
        _fetchMonthlySeries(
            apiName: 'cn_ppi', monthField: 'month', valueField: 'ppi_yoy'),
        _fetchMonthlySeries(
            apiName: 'cn_pmi', monthField: 'month', valueField: 'pmi010000'),
        _fetchMonthlySeries(
            apiName: 'cn_m', monthField: 'month', valueField: 'm2_yoy'),
        _fetchShibor1y(),
      ]);
      setState(() {
        _cpi = results[0];
        _ppi = results[1];
        _pmiManu = results[2];
        _m2 = results[3];
        _shibor1y = results[4];
        _macroLoading = false;
      });
    } catch (e) {
      setState(() {
        _macroError = e.toString();
        _macroLoading = false;
      });
    }
  }

  Future<List<MapEntry<String, double>>> _fetchMonthlySeries({
    required String apiName,
    required String monthField,
    required String valueField,
  }) async {
    // 拉近 5 年的月度数据
    final now = DateTime.now();
    final start = '${(now.year - 5).toString().padLeft(4, '0')}01';
    final end =
        '${now.year.toString().padLeft(4, '0')}${now.month.toString().padLeft(2, '0')}';
    final rows = await _svc.query(
      apiName: apiName,
      params: {'start_m': start, 'end_m': end},
      fields: '$monthField,$valueField',
    );
    final out = <MapEntry<String, double>>[];
    for (final r in rows) {
      final m = (r[monthField] ?? '').toString();
      final v = r[valueField];
      if (m.isEmpty || v == null) continue;
      double? d;
      if (v is num) {
        d = v.toDouble();
      } else {
        d = double.tryParse(v.toString());
      }
      if (d == null) continue;
      out.add(MapEntry(m, d));
    }
    out.sort((a, b) => a.key.compareTo(b.key));
    return out;
  }

  Future<List<MapEntry<String, double>>> _fetchShibor1y() async {
    final now = DateTime.now();
    final start = _ymd(now.subtract(const Duration(days: 365 * 2)));
    final end = _ymd(now);
    final rows = await _svc.query(
      apiName: 'shibor',
      params: {'start_date': start, 'end_date': end},
      fields: 'date,1y',
    );
    final out = <MapEntry<String, double>>[];
    for (final r in rows) {
      final d = (r['date'] ?? '').toString();
      final v = r['1y'];
      double? parsed;
      if (v is num) {
        parsed = v.toDouble();
      } else {
        parsed = double.tryParse((v ?? '').toString());
      }
      if (d.isEmpty || parsed == null) continue;
      out.add(MapEntry(d, parsed));
    }
    out.sort((a, b) => a.key.compareTo(b.key));
    return out;
  }

  Future<void> _loadValuations() async {
    final results = <_ValuationStat>[];
    for (final p in _valuationIndices) {
      try {
        final v = await _fetchValuation(p[0], p[1]);
        if (v != null) results.add(v);
      } catch (_) {/* ignore single failure */}
    }
    if (!mounted) return;
    setState(() => _valuations = results);
  }

  Future<_ValuationStat?> _fetchValuation(String tsCode, String label) async {
    final now = DateTime.now();
    final start = _ymd(now.subtract(const Duration(days: 365 * 5)));
    final end = _ymd(now);
    final rows = await _svc.query(
      apiName: 'index_dailybasic',
      params: {'ts_code': tsCode, 'start_date': start, 'end_date': end},
      fields: 'trade_date,pe,pb',
    );
    final pe = <double>[];
    final pb = <double>[];
    for (final r in rows) {
      final p = r['pe'];
      final b = r['pb'];
      double? pv;
      double? bv;
      if (p is num) {
        pv = p.toDouble();
      } else {
        pv = double.tryParse((p ?? '').toString());
      }
      if (b is num) {
        bv = b.toDouble();
      } else {
        bv = double.tryParse((b ?? '').toString());
      }
      if (pv != null && pv > 0) pe.add(pv);
      if (bv != null && bv > 0) pb.add(bv);
    }
    if (pe.isEmpty || pb.isEmpty) return null;
    // tushare 默认按 trade_date 倒序，第一条是最新
    final latestPe = pe.first;
    final latestPb = pb.first;
    final pePctile = _percentile(pe, latestPe);
    final pbPctile = _percentile(pb, latestPb);
    return _ValuationStat(
      code: tsCode,
      label: label,
      pe: latestPe,
      pb: latestPb,
      pePercentile: pePctile,
      pbPercentile: pbPctile,
    );
  }

  /// 计算 v 在 list 中的百分位（0..1，1 表示比所有历史都高）
  double _percentile(List<double> xs, double v) {
    if (xs.isEmpty) return 0;
    var below = 0;
    for (final x in xs) {
      if (x <= v) below++;
    }
    return below / xs.length;
  }

  String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}'
      '${d.month.toString().padLeft(2, '0')}'
      '${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async {
        await Future.wait([_load(), _loadMacro(), _loadValuations()]);
      },
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _macroDashCard(),
          const SizedBox(height: 12),
          _valuationCard(),
          const SizedBox(height: 12),
          _indexCard(),
        ],
      ),
    );
  }

  Widget _macroDashCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _Title('宏观看板（最新 + 近 60 个月趋势）'),
            const SizedBox(height: 6),
            if (_macroLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_macroError != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(_macroError!,
                    style:
                        TextStyle(color: AppColors.textTertiary, fontSize: 11)),
              )
            else ...[
              _macroRow(
                  label: 'CPI 同比',
                  series: _cpi,
                  unit: '%',
                  hint: '> 0 表示通胀'),
              _macroRow(
                  label: 'PPI 同比',
                  series: _ppi,
                  unit: '%',
                  hint: '工业品出厂价格'),
              _macroRow(
                  label: '制造业 PMI',
                  series: _pmiManu,
                  unit: '',
                  hint: '> 50 扩张',
                  threshold: 50),
              _macroRow(
                  label: 'M2 同比',
                  series: _m2,
                  unit: '%',
                  hint: '广义货币'),
              _macroRow(
                  label: 'Shibor 1Y',
                  series: _shiborMonthly(),
                  unit: '%',
                  hint: '银行间 1 年期'),
            ],
          ],
        ),
      ),
    );
  }

  /// 把日频 Shibor 折成月频（取每月最后一个观察值），方便和其他指标在同一个网格里展示
  List<MapEntry<String, double>> _shiborMonthly() {
    if (_shibor1y.isEmpty) return const [];
    final monthly = <String, double>{};
    for (final p in _shibor1y) {
      // p.key 形如 20240315
      if (p.key.length < 6) continue;
      final mk = p.key.substring(0, 6);
      monthly[mk] = p.value; // 后值覆盖（升序排列后即为月末值）
    }
    final keys = monthly.keys.toList()..sort();
    return [for (final k in keys) MapEntry(k, monthly[k]!)];
  }

  Widget _macroRow({
    required String label,
    required List<MapEntry<String, double>> series,
    required String unit,
    required String hint,
    double? threshold,
  }) {
    if (series.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            SizedBox(
                width: 90,
                child: Text(label,
                    style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w800))),
            Text('--',
                style: TextStyle(
                    color: AppColors.textTertiary, fontSize: 11)),
          ],
        ),
      );
    }
    final last = series.last;
    final prev = series.length >= 2 ? series[series.length - 2] : null;
    final diff = prev == null ? null : last.value - prev.value;
    final lastColor = threshold != null
        ? (last.value >= threshold ? AppColors.positive : AppColors.negative)
        : (diff == null
            ? AppColors.textPrimary
            : (diff >= 0 ? AppColors.positive : AppColors.negative));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
              width: 90,
              child: Text(label,
                  style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w800))),
          Text(
            '${last.value.toStringAsFixed(2)}$unit',
            style: TextStyle(
                color: lastColor,
                fontWeight: FontWeight.w800,
                fontFamily: 'monospace',
                fontSize: 13),
          ),
          const SizedBox(width: 6),
          if (diff != null)
            Text(
              '${diff >= 0 ? '+' : ''}${diff.toStringAsFixed(2)}',
              style: TextStyle(
                  color:
                      diff >= 0 ? AppColors.positive : AppColors.negative,
                  fontFamily: 'monospace',
                  fontSize: 10),
            ),
          const Spacer(),
          SizedBox(
              width: 90,
              height: 22,
              child: _Spark(values: [for (final p in series) p.value])),
          const SizedBox(width: 8),
          SizedBox(
              width: 80,
              child: Text(_formatLastMonth(last.key),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 9,
                      fontWeight: FontWeight.w700))),
        ],
      ),
    );
  }

  String _formatLastMonth(String key) {
    if (key.length == 6) {
      return '${key.substring(0, 4)}-${key.substring(4, 6)}';
    }
    if (key.length == 8) {
      return '${key.substring(0, 4)}-${key.substring(4, 6)}-${key.substring(6, 8)}';
    }
    return key;
  }

  Widget _valuationCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _Title('指数估值百分位（近 5 年）'),
            const SizedBox(height: 6),
            if (_valuations.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('暂无数据，可能是数据接口暂时不可用。',
                    style: TextStyle(
                        color: AppColors.textTertiary, fontSize: 11)),
              )
            else
              for (final v in _valuations) _ValuationRow(v: v),
          ],
        ),
      ),
    );
  }

  Widget _indexCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(child: _Title('指数行情（近 1 年）')),
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
            style: TextStyle(color: AppColors.textTertiary, fontSize: 11)),
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
              style: TextStyle(fontSize: 9, color: AppColors.textTertiary),
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
            style: TextStyle(color: AppColors.textTertiary, fontSize: 11)),
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

class _Spark extends StatelessWidget {
  const _Spark({required this.values});
  final List<double> values;
  @override
  Widget build(BuildContext context) {
    if (values.length < 2) return const SizedBox();
    final last = values.length > 60 ? values.sublist(values.length - 60) : values;
    final spots = [
      for (var i = 0; i < last.length; i++) FlSpot(i.toDouble(), last[i])
    ];
    return LineChart(LineChartData(
      gridData: const FlGridData(show: false),
      borderData: FlBorderData(show: false),
      titlesData: const FlTitlesData(show: false),
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          color: AppColors.amber,
          barWidth: 1,
          isCurved: true,
          dotData: const FlDotData(show: false),
        ),
      ],
    ));
  }
}

class _ValuationStat {
  const _ValuationStat({
    required this.code,
    required this.label,
    required this.pe,
    required this.pb,
    required this.pePercentile,
    required this.pbPercentile,
  });
  final String code;
  final String label;
  final double pe;
  final double pb;
  final double pePercentile;
  final double pbPercentile;
}

class _ValuationRow extends StatelessWidget {
  const _ValuationRow({required this.v});
  final _ValuationStat v;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('${v.label}  ${v.code}',
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 12)),
              ),
              Text('PE ${v.pe.toStringAsFixed(2)} · PB ${v.pb.toStringAsFixed(2)}',
                  style: TextStyle(
                      color: AppColors.textSecondary,
                      fontFamily: 'monospace',
                      fontSize: 11)),
            ],
          ),
          const SizedBox(height: 4),
          _percentBar(label: 'PE 百分位', p: v.pePercentile),
          const SizedBox(height: 2),
          _percentBar(label: 'PB 百分位', p: v.pbPercentile),
        ],
      ),
    );
  }

  Widget _percentBar({required String label, required double p}) {
    final pct = (p * 100).clamp(0, 100);
    final color = p < 0.3
        ? AppColors.positive
        : (p > 0.7 ? AppColors.negative : AppColors.amber);
    return Row(
      children: [
        SizedBox(
            width: 60,
            child: Text(label,
                style: TextStyle(
                    color: AppColors.textTertiary, fontSize: 10))),
        Expanded(
          child: Stack(
            children: [
              Container(height: 6, color: AppColors.bgRaised),
              FractionallySizedBox(
                widthFactor: p.clamp(0.0, 1.0),
                child: Container(height: 6, color: color),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 44,
          child: Text(
            '${pct.toStringAsFixed(0)}%',
            textAlign: TextAlign.right,
            style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
                fontFamily: 'monospace',
                fontSize: 11),
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
