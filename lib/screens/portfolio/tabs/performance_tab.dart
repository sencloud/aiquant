import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../models/portfolio.dart';
import '../../../state/portfolio_state.dart';
import '../../../theme/app_theme.dart';

/// "绩效 / 风险" tab. Computes light client-side analytics from the holdings
/// and the portfolio NAV time series:
///   - portfolio CAGR proxy
///   - daily-return volatility (annualised)
///   - Sharpe ratio (assumed rf = 4 %)
///   - max drawdown
///   - top 3 winners / losers
class PerformanceTab extends StatefulWidget {
  const PerformanceTab({super.key});

  @override
  State<PerformanceTab> createState() => _PerformanceTabState();
}

class _PerformanceTabState extends State<PerformanceTab> {
  List<MapEntry<DateTime, double>>? _series;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final pts =
        await context.read<PortfolioState>().performanceSeries(days: 252);
    if (!mounted) return;
    setState(() {
      _series = pts;
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

    final stats = _Stats.fromSeries(_series ?? const []);
    final fmt = NumberFormat('#,##0.00');

    final top = [...s.holdings]
      ..sort((a, b) => b.unrealizedPnl.compareTo(a.unrealizedPnl));
    final losers = [...s.holdings]
      ..sort((a, b) => a.unrealizedPnl.compareTo(b.unrealizedPnl));

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _Title('收益与风险（基于近 252 个交易日）'),
                const SizedBox(height: 10),
                _kpiGrid([
                  _Kpi('累计收益率', stats.totalReturnPct == null
                      ? '--'
                      : '${stats.totalReturnPct!.toStringAsFixed(2)}%'),
                  _Kpi('年化波动率', stats.annualVol == null
                      ? '--'
                      : '${stats.annualVol!.toStringAsFixed(2)}%'),
                  _Kpi('Sharpe (rf=4%)', stats.sharpe == null
                      ? '--'
                      : stats.sharpe!.toStringAsFixed(2)),
                  _Kpi('最大回撤', stats.maxDrawdownPct == null
                      ? '--'
                      : '${stats.maxDrawdownPct!.toStringAsFixed(2)}%'),
                  _Kpi('当前市值', fmt.format(s.totalMarketValue),
                      suffix: s.portfolio.currency),
                  _Kpi('未实现盈亏',
                      '${s.totalUnrealizedPnl >= 0 ? '+' : '-'}${fmt.format(s.totalUnrealizedPnl.abs())}',
                      color: s.totalUnrealizedPnl >= 0
                          ? AppColors.positive
                          : AppColors.negative),
                ]),
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
      final cols = c.maxWidth > 540 ? 3 : 2;
      return GridView.count(
        crossAxisCount: cols,
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 2.6,
        children: [
          for (final k in kpis) _KpiBox(kpi: k),
        ],
      );
    });
  }
}

class _Stats {
  final double? totalReturnPct;
  final double? annualVol;
  final double? sharpe;
  final double? maxDrawdownPct;

  _Stats({
    this.totalReturnPct,
    this.annualVol,
    this.sharpe,
    this.maxDrawdownPct,
  });

  factory _Stats.fromSeries(List<MapEntry<DateTime, double>> pts) {
    if (pts.length < 5) return _Stats();
    final values = [for (final p in pts) p.value];
    final first = values.first;
    final last = values.last;
    final totalRet = first <= 0 ? null : (last / first - 1) * 100;

    final returns = <double>[];
    for (int i = 1; i < values.length; i++) {
      final prev = values[i - 1];
      if (prev <= 0) continue;
      returns.add(values[i] / prev - 1);
    }
    if (returns.isEmpty) {
      return _Stats(totalReturnPct: totalRet);
    }
    final mean = returns.reduce((a, b) => a + b) / returns.length;
    double sse = 0;
    for (final r in returns) {
      sse += (r - mean) * (r - mean);
    }
    final std = math.sqrt(sse / returns.length);
    final annualVol = std * math.sqrt(252) * 100;

    const rf = 0.04;
    final excess = mean * 252 - rf;
    final sharpe = (std * math.sqrt(252)).abs() < 1e-9
        ? null
        : excess / (std * math.sqrt(252));

    double peak = values.first;
    double maxDD = 0;
    for (final v in values) {
      if (v > peak) peak = v;
      final dd = peak <= 0 ? 0 : (v - peak) / peak;
      if (dd < maxDD) maxDD = dd.toDouble();
    }
    final mdd = maxDD * 100;

    return _Stats(
      totalReturnPct: totalRet,
      annualVol: annualVol,
      sharpe: sharpe,
      maxDrawdownPct: mdd,
    );
  }
}

class _Kpi {
  final String label;
  final String value;
  final String? suffix;
  final Color? color;
  _Kpi(this.label, this.value, {this.suffix, this.color});
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
              style: TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6)),
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
                        fontSize: 16,
                        fontWeight: FontWeight.w800)),
              ),
              if (kpi.suffix != null) ...[
                const SizedBox(width: 4),
                Text(kpi.suffix!,
                    style: TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ],
            ],
          ),
        ],
      ),
    );
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
              style: TextStyle(
                  color: AppColors.textPrimary, fontSize: 11),
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
            style: TextStyle(
                color: AppColors.textSecondary, fontSize: 12)),
      ),
    );
  }
}
