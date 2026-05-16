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

/// 量化统计 — 含集中度、收益分布、相关性热力图、滚动波动率/Sharpe、VaR/CVaR。
class QuantTab extends StatefulWidget {
  const QuantTab({super.key});

  @override
  State<QuantTab> createState() => _QuantTabState();
}

class _QuantTabState extends State<QuantTab> {
  static const _windowDays = 252;
  static const _rollingWindow = 30; // 滚动窗口（交易日）

  Map<String, List<CandlePoint>>? _histories;
  List<MapEntry<DateTime, double>>? _nav;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final ps = context.read<PortfolioState>();
    final h = await ps.ensureHistories(days: _windowDays);
    final n = await ps.performanceSeries(days: _windowDays);
    if (!mounted) return;
    setState(() {
      _histories = h;
      _nav = n;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ps = context.watch<PortfolioState>();
    final s = ps.currentSummary;
    if (s == null || s.holdings.isEmpty) {
      return const _Empty('加入品种后这里会展示统计指标。');
    }
    if (_loading) return const Center(child: CircularProgressIndicator());

    final pnls = [for (final h in s.holdings) h.unrealizedPnlPercent];
    final mean = pnls.isEmpty ? 0.0 : pnls.reduce((a, b) => a + b) / pnls.length;
    final std = pnls.length < 2
        ? 0.0
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
    final sortedShares = [...shares]..sort((a, b) => b.compareTo(a));
    final top3 =
        sortedShares.take(3).fold<double>(0, (a, w) => a + w) * 100;
    final assetCount = s.holdings.length;
    final sectorCount = s.sectorWeights.length;

    final fmt = NumberFormat('0.00');

    final navAsCandles = [
      for (final e in (_nav ?? const <MapEntry<DateTime, double>>[]))
        CandlePoint(date: e.key, close: e.value)
    ];

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
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
                    _Kv('偏度', fmt.format(Indicators.skewness(pnls))),
                    _Kv('峰度', fmt.format(Indicators.excessKurtosis(pnls))),
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
          const SizedBox(height: 12),
          _correlationCard(s.holdings, _histories ?? const {}),
          const SizedBox(height: 12),
          _rollingCard(navAsCandles),
          const SizedBox(height: 12),
          _varCard(navAsCandles),
        ],
      ),
    );
  }

  Widget _correlationCard(
      List<PortfolioAsset> holdings,
      Map<String, List<CandlePoint>> histories) {
    final symbols = <String>[
      for (final h in holdings)
        if ((histories[h.symbol]?.length ?? 0) > 5) h.symbol
    ];
    if (symbols.length < 2) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _Title('相关性矩阵'),
              const SizedBox(height: 8),
              Text('需要至少 2 只持仓且有日线数据。',
                  style: TextStyle(
                      color: AppColors.textTertiary, fontSize: 11)),
            ],
          ),
        ),
      );
    }

    // 用每只标的的日收益率两两计算 Pearson
    final returns = <String, List<double>>{};
    for (final sym in symbols) {
      returns[sym] = Indicators.dailyReturns(histories[sym]!);
    }
    // 按最短长度对齐尾部（每对各自对齐）
    final n = symbols.length;
    final m = List<List<double>>.generate(
        n, (_) => List<double>.filled(n, 0));
    for (var i = 0; i < n; i++) {
      for (var j = 0; j < n; j++) {
        if (i == j) {
          m[i][j] = 1;
          continue;
        }
        final a = returns[symbols[i]]!;
        final b = returns[symbols[j]]!;
        final len = math.min(a.length, b.length);
        if (len < 5) {
          m[i][j] = 0;
          continue;
        }
        m[i][j] = Indicators.correlation(
          a.sublist(a.length - len),
          b.sublist(b.length - len),
        );
      }
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _Title('相关性矩阵（基于近 252 日收益率）'),
            const SizedBox(height: 8),
            _CorrHeatmap(symbols: symbols, matrix: m),
          ],
        ),
      ),
    );
  }

  Widget _rollingCard(List<CandlePoint> nav) {
    if (nav.length < _rollingWindow + 5) return const SizedBox.shrink();
    final vol = Indicators.rollingVolatility(nav, _rollingWindow);
    final sharpe = Indicators.rollingSharpe(nav, _rollingWindow);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _Title('滚动指标（30 个交易日窗口）'),
            const SizedBox(height: 8),
            const Row(
              children: [
                _Legend(color: AppColors.amber, label: '滚动波动率（年化）'),
                SizedBox(width: 12),
                _Legend(color: AppColors.info, label: '滚动 Sharpe'),
              ],
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: 160,
              child: _RollingChart(vol: vol, sharpe: sharpe),
            ),
          ],
        ),
      ),
    );
  }

  Widget _varCard(List<CandlePoint> nav) {
    if (nav.length < 30) return const SizedBox.shrink();
    final var95 = Indicators.varHistorical(nav, p: 0.95);
    final cvar95 = Indicators.cvarHistorical(nav, p: 0.95);
    final var99 = Indicators.varHistorical(nav, p: 0.99);
    final cvar99 = Indicators.cvarHistorical(nav, p: 0.99);
    final fmt = NumberFormat('0.00');
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _Title('风险指标 VaR / CVaR（历史模拟法 · 单日）'),
            const SizedBox(height: 8),
            _Grid([
              _Kv('VaR 95%', '-${fmt.format(var95 * 100)}%',
                  color: AppColors.negative),
              _Kv('CVaR 95%', '-${fmt.format(cvar95 * 100)}%',
                  color: AppColors.negative),
              _Kv('VaR 99%', '-${fmt.format(var99 * 100)}%',
                  color: AppColors.negative),
              _Kv('CVaR 99%', '-${fmt.format(cvar99 * 100)}%',
                  color: AppColors.negative),
            ]),
            const SizedBox(height: 4),
            Text(
                '说明：VaR 表示在给定置信度下的最大可能单日亏损；CVaR 是超过 VaR 之后的平均亏损。',
                style:
                    TextStyle(color: AppColors.textTertiary, fontSize: 10)),
          ],
        ),
      ),
    );
  }
}

class _CorrHeatmap extends StatelessWidget {
  const _CorrHeatmap({required this.symbols, required this.matrix});
  final List<String> symbols;
  final List<List<double>> matrix;

  @override
  Widget build(BuildContext context) {
    final n = symbols.length;
    const cell = 28.0;
    const labelWidth = 64.0;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 列标签
          Row(
            children: [
              const SizedBox(width: labelWidth),
              for (final sym in symbols)
                SizedBox(
                  width: cell,
                  child: Center(
                    child: Text(sym.split('.').first,
                        style: TextStyle(
                            fontSize: 8.5,
                            color: AppColors.textTertiary,
                            fontWeight: FontWeight.w800)),
                  ),
                ),
            ],
          ),
          // 行
          for (var i = 0; i < n; i++)
            Row(
              children: [
                SizedBox(
                  width: labelWidth,
                  child: Text(symbols[i].split('.').first,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textSecondary)),
                ),
                for (var j = 0; j < n; j++)
                  Container(
                    width: cell,
                    height: cell,
                    margin: const EdgeInsets.all(1),
                    color: _colorFor(matrix[i][j]),
                    alignment: Alignment.center,
                    child: Text(
                      matrix[i][j].toStringAsFixed(2),
                      style: TextStyle(
                        fontSize: 8.5,
                        fontWeight: FontWeight.w800,
                        color:
                            matrix[i][j].abs() > 0.5
                                ? Colors.white
                                : AppColors.textPrimary,
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Color _colorFor(double r) {
    final v = r.clamp(-1.0, 1.0);
    if (v >= 0) {
      return Color.lerp(AppColors.bgRaised, AppColors.positive, v)!;
    } else {
      return Color.lerp(AppColors.bgRaised, AppColors.negative, -v)!;
    }
  }
}

class _RollingChart extends StatelessWidget {
  const _RollingChart({required this.vol, required this.sharpe});
  final List<MapEntry<DateTime, double>> vol;
  final List<MapEntry<DateTime, double>> sharpe;

  @override
  Widget build(BuildContext context) {
    if (vol.length < 2 && sharpe.length < 2) {
      return Center(
        child: Text('数据不足',
            style: TextStyle(color: AppColors.textTertiary, fontSize: 11)),
      );
    }
    // 双轴：左轴 vol（百分比），右轴 sharpe；这里简化：vol 转成百分数，sharpe 缩放到接近的范围
    final volSpots = [
      for (var i = 0; i < vol.length; i++)
        FlSpot(i.toDouble(), vol[i].value * 100)
    ];
    // sharpe 放在第二条线，y 轴用同一刻度（sharpe 一般在 -3..3），乘以 5 让其与 vol(%) 视觉接近
    final sharpeSpots = <FlSpot>[];
    if (sharpe.isNotEmpty && vol.isNotEmpty && vol.length == sharpe.length) {
      for (var i = 0; i < sharpe.length; i++) {
        sharpeSpots.add(FlSpot(i.toDouble(), sharpe[i].value * 5));
      }
    } else {
      // 长度不一致时按比例映射
      for (var i = 0; i < vol.length; i++) {
        final ratio = i / (vol.length - 1).clamp(1, 1e9);
        final j = (ratio * (sharpe.length - 1)).round();
        if (j >= 0 && j < sharpe.length) {
          sharpeSpots.add(FlSpot(i.toDouble(), sharpe[j].value * 5));
        }
      }
    }

    final allY = [
      for (final s in volSpots) s.y,
      for (final s in sharpeSpots) s.y
    ];
    final minY = allY.reduce(math.min);
    final maxY = allY.reduce(math.max);

    return LineChart(LineChartData(
      minY: minY - 1,
      maxY: maxY + 1,
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
            interval: (vol.length / 5).ceilToDouble().clamp(1, 9999),
            getTitlesWidget: (v, _) {
              final i = v.toInt();
              if (i < 0 || i >= vol.length) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  DateFormat('M/d').format(vol[i].key),
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
          spots: volSpots,
          color: AppColors.amber,
          isCurved: true,
          barWidth: 1.4,
          dotData: const FlDotData(show: false),
        ),
        if (sharpeSpots.isNotEmpty)
          LineChartBarData(
            spots: sharpeSpots,
            color: AppColors.info,
            isCurved: true,
            barWidth: 1.4,
            dotData: const FlDotData(show: false),
          ),
      ],
    ));
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
        Container(width: 12, height: 2, color: color),
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
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
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
                  height: maxCount == 0 ? 0 : 96 * counts[i] / maxCount,
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
