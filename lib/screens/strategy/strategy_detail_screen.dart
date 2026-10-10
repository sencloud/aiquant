import 'package:flutter/material.dart';

import '../../models/strategy_snapshot.dart';
import '../../theme/app_theme.dart';
import 'widgets/strategy_cards.dart';

/// 策略详情：把"凭什么信这个策略"讲清楚。
///
/// 排序刻意如此——先口径（怎么算的），再绩效（算出来什么），最后是证据
/// （逐年、因子检验、股票池对比）。只放收益曲线、不出口径的做法是不可信的。
class StrategyDetailScreen extends StatelessWidget {
  const StrategyDetailScreen({super.key, required this.snapshot});

  final StrategySnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final m = snapshot.metrics;
    return Scaffold(
      appBar: AppBar(title: const Text('策略详情')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
        children: [
          _howItWorks(),
          const SizedBox(height: 12),
          _performance(m),
          if (snapshot.curve.length > 1) ...[
            const SizedBox(height: 12),
            _curve(),
          ],
          if (snapshot.yearly.isNotEmpty) ...[
            const SizedBox(height: 12),
            _yearly(),
          ],
          if (snapshot.factors.isNotEmpty) ...[
            const SizedBox(height: 12),
            _factors(),
          ],
          if (snapshot.universes.isNotEmpty) ...[
            const SizedBox(height: 12),
            _universes(),
          ],
          const SizedBox(height: 12),
          _disclosure(),
        ],
      ),
    );
  }

  // ── 口径说明 ──────────────────────────────────────────────────────────

  Widget _howItWorks() {
    final meta = snapshot.meta;
    return StrategyCard(
      title: '怎么算的',
      children: [
        Text(
          meta.summary,
          style: TextStyle(
              color: AppColors.textPrimary, fontSize: 12.5, height: 1.7),
        ),
        const SizedBox(height: 12),
        StatRow('股票池', meta.universe.isEmpty ? '—' : meta.universe),
        StatRow('持仓只数', meta.topN == 0 ? '—' : '${meta.topN} 只等权'),
        const StatRow('调仓频率', '月度（差额调仓）'),
        StatRow('排除行业',
            meta.exclude.isEmpty ? '无' : meta.exclude.join('、')),
        StatRow('回测区间', meta.since.isEmpty ? '—' : '${meta.since} 起'),
        StatRow('回测本金',
            meta.capital > 0 ? money(meta.capital, digits: 0) : '—'),
      ],
    );
  }

  // ── 绩效与基准 ────────────────────────────────────────────────────────

  Widget _performance(StrategyMetrics m) {
    final bench = snapshot.benchmarks.isEmpty ? null : snapshot.benchmarks.first;
    return StrategyCard(
      title: '绩效（回测口径）',
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              money(m.equity, digits: 0),
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w800),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                '本金 ${money(m.capital, digits: 0)} → ${pct(m.pnlPct)}',
                style: TextStyle(color: pnlColor(m.pnl), fontSize: 12),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        StatRow('年化收益', pct(m.cagr)),
        StatRow('夏普比率', m.sharpe.toStringAsFixed(2)),
        StatRow('最大回撤', pct(m.maxDrawdown)),
        StatRow('月度胜率', '${(m.monthWin * 100).toStringAsFixed(1)}%'),
        StatRow('交易笔数', '${m.trades} 笔'),
        StatRow('累计费用', money(m.fees, digits: 0)),
        if (bench != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.bgRaised,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.borderDim),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('对照：${bench.name}',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 11.5)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text('同期 ${pct(bench.totalReturn)}',
                        style: TextStyle(
                            color: pnlColor(bench.totalReturn),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700)),
                    const Spacer(),
                    Text('策略超额 ${pct(m.pnlPct - bench.totalReturn)}',
                        style: TextStyle(
                            color: pnlColor(m.pnlPct - bench.totalReturn),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
                if (bench.comment.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(bench.comment,
                      style: TextStyle(
                          color: AppColors.textTertiary,
                          fontSize: 10.5,
                          height: 1.5)),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  // ── 净值曲线 ──────────────────────────────────────────────────────────

  Widget _curve() {
    final first = snapshot.curve.first;
    final last = snapshot.curve.last;
    return StrategyCard(
      title: '净值曲线',
      trailing: Text('${first.date} → ${last.date}',
          style: TextStyle(color: AppColors.textTertiary, fontSize: 10.5)),
      children: [
        SizedBox(
          height: 150,
          child: CustomPaint(
            painter: _CurvePainter(snapshot.curve),
            size: Size.infinite,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _legend('策略', AppColors.amber, '${last.equity.toStringAsFixed(2)} 倍'),
            const SizedBox(width: 16),
            _legend('上证50 指数', AppColors.textSecondary,
                '${last.bench.toStringAsFixed(2)} 倍'),
          ],
        ),
      ],
    );
  }

  Widget _legend(String label, Color color, String value) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 10, height: 2.5, color: color),
          const SizedBox(width: 6),
          Text('$label $value',
              style: TextStyle(color: AppColors.textTertiary, fontSize: 10.5)),
        ],
      );

  // ── 逐年 ──────────────────────────────────────────────────────────────

  Widget _yearly() {
    return StrategyCard(
      title: '逐年收益',
      children: [
        for (final y in snapshot.yearly)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                SizedBox(
                  width: 44,
                  child: Text('${y.year}',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 11.5)),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: (y.ret.abs() / 0.6).clamp(0.02, 1.0),
                      minHeight: 6,
                      backgroundColor: AppColors.bgRaised,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(pnlColor(y.ret)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 62,
                  child: Text(
                    pct(y.ret),
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        color: pnlColor(y.ret),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ── 因子检验 ──────────────────────────────────────────────────────────

  Widget _factors() {
    return StrategyCard(
      title: '因子检验（全是硬指标）',
      trailing: Text('IC / t / 样本外',
          style: TextStyle(color: AppColors.textTertiary, fontSize: 10.5)),
      children: [
        Text(
          '样本内 IC 高、样本外还能保持，才说明因子不是拟合出来的。'
          't 值低于 2 基本可以当噪声处理。',
          style: TextStyle(
              color: AppColors.textTertiary, fontSize: 10.5, height: 1.5),
        ),
        const SizedBox(height: 8),
        for (final f in snapshot.factors) _factorRow(f),
      ],
    );
  }

  Widget _factorRow(StrategyFactor f) {
    // 样本外明显衰减（掉一半以上）时标黄：这类因子历史上就是不可靠的。
    final decayed = f.ic.abs() > 0.001 && f.oos.abs() < f.ic.abs() * 0.5;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(f.name,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: AppColors.textPrimary, fontSize: 12)),
                    ),
                    if (f.group.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Text(f.group,
                          style: TextStyle(
                              color: AppColors.textTertiary, fontSize: 9.5)),
                    ],
                    if (decayed) ...[
                      const SizedBox(width: 6),
                      const Text('样本外衰减',
                          style: TextStyle(
                              color: AppColors.warning, fontSize: 9.5)),
                    ],
                  ],
                ),
                if (f.desc.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(f.desc,
                      style: TextStyle(
                          color: AppColors.textTertiary, fontSize: 10)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          _factorNum('IC', f.ic, 3),
          _factorNum('t', f.t, 1),
          _factorNum('OOS', f.oos, 3),
        ],
      ),
    );
  }

  Widget _factorNum(String label, double v, int digits) => SizedBox(
        width: 52,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(v.toStringAsFixed(digits),
                style: TextStyle(
                    color: AppColors.textPrimary, fontSize: 11.5)),
            Text(label,
                style:
                    TextStyle(color: AppColors.textTertiary, fontSize: 9)),
          ],
        ),
      );

  // ── 股票池对比 ────────────────────────────────────────────────────────

  Widget _universes() {
    return StrategyCard(
      title: '同一套因子，换股票池会怎样',
      children: [
        Text(
          '说明"为什么选上证50"：换到大盘股池子收益更高、回撤更小，'
          '换到中小盘池子会明显变差。',
          style: TextStyle(
              color: AppColors.textTertiary, fontSize: 10.5, height: 1.5),
        ),
        const SizedBox(height: 8),
        for (final u in snapshot.universes)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Expanded(
                  child: Text(u.name,
                      style: TextStyle(
                          color: AppColors.textPrimary, fontSize: 12)),
                ),
                SizedBox(
                  width: 66,
                  child: Text(pct(u.cagr),
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          color: pnlColor(u.cagr),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700)),
                ),
                SizedBox(
                  width: 54,
                  child: Text('夏普 ${u.sharpe.toStringAsFixed(2)}',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 10.5)),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ── 口径与风险 ────────────────────────────────────────────────────────

  Widget _disclosure() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.bgRaised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderDim),
      ),
      child: Text(
        snapshot.meta.disclosure,
        style: TextStyle(
            color: AppColors.textSecondary, fontSize: 11, height: 1.7),
      ),
    );
  }
}

/// 策略 / 基准两条净值曲线的极简折线图。
///
/// 只画两条线 + 首尾基准线，不做坐标轴：这里要传达的是"策略长期跑赢基准"，
/// 精确到某天的数值应该去问 AI 或看明细，不该塞在这张小图里。
class _CurvePainter extends CustomPainter {
  _CurvePainter(this.points);

  final List<StrategyCurvePoint> points;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    var lo = double.infinity;
    var hi = -double.infinity;
    for (final p in points) {
      for (final v in [p.equity, p.bench]) {
        if (v <= 0) continue;
        lo = v < lo ? v : lo;
        hi = v > hi ? v : hi;
      }
    }
    if (!lo.isFinite || !hi.isFinite || hi <= lo) return;
    final pad = (hi - lo) * 0.08;
    lo -= pad;
    hi += pad;

    Offset at(int i, double v) => Offset(
          size.width * i / (points.length - 1),
          size.height * (1 - (v - lo) / (hi - lo)),
        );

    // 1.0 基准线（相当于"不涨不跌"），给两条线一个视觉参照。
    if (lo < 1 && hi > 1) {
      final y = size.height * (1 - (1 - lo) / (hi - lo));
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        Paint()
          ..color = AppColors.borderDim
          ..strokeWidth = 1,
      );
    }

    void drawLine(double Function(StrategyCurvePoint) pick, Color color, double w) {
      final path = Path();
      for (var i = 0; i < points.length; i++) {
        final v = pick(points[i]);
        if (v <= 0) continue;
        final o = at(i, v);
        if (path.getBounds().isEmpty) {
          path.moveTo(o.dx, o.dy);
        } else {
          path.lineTo(o.dx, o.dy);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = w
          ..strokeCap = StrokeCap.round,
      );
    }

    drawLine((p) => p.bench, AppColors.textTertiary, 1.2);
    drawLine((p) => p.equity, AppColors.amber, 1.8);
  }

  @override
  bool shouldRepaint(covariant _CurvePainter old) => old.points != points;
}
