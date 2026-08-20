import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../models/instrument.dart';
import '../../../theme/app_theme.dart';
import 'chart_indicators.dart';

/// K 线图可覆盖的指标开关集合。
class ChartIndicatorFlags {
  const ChartIndicatorFlags({
    this.ma = true,
    this.boll = false,
    this.vol = true,
    this.macd = false,
    this.kdj = false,
    this.rsi = false,
  });

  /// 主图：MA 均线（MA5/MA10/MA20）
  final bool ma;

  /// 主图：BOLL 布林带
  final bool boll;

  /// 副图：成交量
  final bool vol;

  /// 副图：MACD
  final bool macd;

  /// 副图：KDJ
  final bool kdj;

  /// 副图：RSI
  final bool rsi;

  ChartIndicatorFlags copyWith({
    bool? ma,
    bool? boll,
    bool? vol,
    bool? macd,
    bool? kdj,
    bool? rsi,
  }) =>
      ChartIndicatorFlags(
        ma: ma ?? this.ma,
        boll: boll ?? this.boll,
        vol: vol ?? this.vol,
        macd: macd ?? this.macd,
        kdj: kdj ?? this.kdj,
        rsi: rsi ?? this.rsi,
      );
}

/// K 线图组件：主图（蜡烛+均线/BOLL）+ 可选副图（成交量/MACD/KDJ/RSI）。
///
/// 实现说明：项目当前 fl_chart 0.69 没有 CandlestickChart（1.x 才有），
/// 因此用 CustomPainter 自绘——顺带天然支持多窗格共享 X 轴手势联动。
class CandlestickChart extends StatelessWidget {
  const CandlestickChart({
    super.key,
    required this.candles,
    this.flags = const ChartIndicatorFlags(),
  });

  final List<CandlePoint> candles;
  final ChartIndicatorFlags flags;

  @override
  Widget build(BuildContext context) {
    if (candles.length < 2) {
      // AppColors.textTertiary 是运行时可变字段（随主题切换），不能 const。
      return Center(
        child: Text('K 线数据不足',
            style: TextStyle(color: AppColors.textTertiary, fontSize: 11)),
      );
    }

    // 副图数量决定布局高度分配。
    final subCount = [
      flags.vol,
      flags.macd,
      flags.kdj,
      flags.rsi,
    ].where((b) => b).length;

    return LayoutBuilder(builder: (context, constraints) {
      final h = constraints.maxHeight;
      // 主图至少占 45%，副图各占固定份额，剩余给主图。
      final subH = subCount == 0 ? 0.0 : math.min(h * 0.4, subCount * 90.0);
      final mainH = h - subH;
      final subWidth = constraints.maxWidth;
      final panes = <Widget>[];

      panes.add(SizedBox(
        width: subWidth,
        height: mainH,
        child: _MainPane(candles: candles, flags: flags),
      ));

      if (flags.vol) {
        panes.add(SizedBox(
          width: subWidth,
          height: subH / subCount,
          child: _VolPane(candles: candles),
        ));
      }
      if (flags.macd) {
        panes.add(SizedBox(
          width: subWidth,
          height: subH / subCount,
          child: _MacdPane(candles: candles),
        ));
      }
      if (flags.kdj) {
        panes.add(SizedBox(
          width: subWidth,
          height: subH / subCount,
          child: _KdjPane(candles: candles),
        ));
      }
      if (flags.rsi) {
        panes.add(SizedBox(
          width: subWidth,
          height: subH / subCount,
          child: _RsiPane(candles: candles),
        ));
      }
      return Column(children: panes);
    });
  }
}

// ─────────────────────────── 公共绘制工具 ───────────────────────────

/// 依据蜡烛数量自动挑选 X 轴日期标签的索引步长。
int _dateLabelStep(int n) {
  if (n <= 10) return 1;
  if (n <= 25) return 5;
  if (n <= 60) return 10;
  if (n <= 120) return 20;
  return 40;
}

String _fmtMd(DateTime d) =>
    '${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

/// 主图窗格：蜡烛 + MA / BOLL + 右侧价格刻度 + 底部日期。
class _MainPane extends StatelessWidget {
  const _MainPane({required this.candles, required this.flags});
  final List<CandlePoint> candles;
  final ChartIndicatorFlags flags;

  @override
  Widget build(BuildContext context) {
    final ma5 = flags.ma ? ChartIndicators.smaSeries(candles, 5) : null;
    final ma10 = flags.ma ? ChartIndicators.smaSeries(candles, 10) : null;
    final ma20 = flags.ma ? ChartIndicators.smaSeries(candles, 20) : null;
    final (bollMid, bollUp, bollLow) =
        flags.boll ? ChartIndicators.bollSeries(candles) : (null, null, null);

    return CustomPaint(
      painter: _MainPanePainter(
        candles: candles,
        ma5: ma5,
        ma10: ma10,
        ma20: ma20,
        bollMid: bollMid,
        bollUp: bollUp,
        bollLow: bollLow,
      ),
      size: Size.infinite,
    );
  }
}

class _MainPanePainter extends CustomPainter {
  _MainPanePainter({
    required this.candles,
    this.ma5,
    this.ma10,
    this.ma20,
    this.bollMid,
    this.bollUp,
    this.bollLow,
  });

  final List<CandlePoint> candles;
  final List<double?>? ma5;
  final List<double?>? ma10;
  final List<double?>? ma20;
  final List<double?>? bollMid;
  final List<double?>? bollUp;
  final List<double?>? bollLow;

  static const _priceLabelW = 52.0;
  static const _dateLabelH = 14.0;
  static const _padTop = 6.0;

  @override
  void paint(Canvas canvas, Size size) {
    final plotW = size.width - _priceLabelW;
    final plotH = size.height - _dateLabelH;
    if (plotW <= 0 || plotH <= 0 || candles.isEmpty) return;

    // 价格上下限：蜡烛高低 + 均线/BOLL 取值。
    var minP = double.infinity;
    var maxP = double.negativeInfinity;
    for (final c in candles) {
      minP = math.min(minP, c.low ?? c.close);
      maxP = math.max(maxP, c.high ?? c.close);
    }
    for (final s in [ma5, ma10, ma20, bollMid, bollUp, bollLow]) {
      if (s == null) continue;
      for (final v in s) {
        if (v == null) continue;
        minP = math.min(minP, v);
        maxP = math.max(maxP, v);
      }
    }
    if (!minP.isFinite || !maxP.isFinite || minP == maxP) {
      minP -= 1;
      maxP += 1;
    }
    final pad = (maxP - minP) * 0.05;
    minP -= pad;
    maxP += pad;

    final n = candles.length;
    double x(int i) => (i + 0.5) * plotW / n;
    double y(double p) => _padTop + (maxP - p) / (maxP - minP) * (plotH - _padTop * 2);

    // 网格 + 右侧价格刻度
    final gridPaint = Paint()
      ..color = AppColors.borderDim.withValues(alpha: 0.45)
      ..strokeWidth = 0.5;
    final labelTp = TextPainter(textDirection: TextDirection.ltr)
      ..text = const TextSpan();
    final priceStyle = TextStyle(
        color: AppColors.textTertiary, fontSize: 9, fontFamily: 'monospace');
    const gridLines = 4;
    for (var g = 0; g <= gridLines; g++) {
      final p = minP + (maxP - minP) * g / gridLines;
      final yy = y(p);
      canvas.drawLine(Offset(0, yy), Offset(plotW, yy), gridPaint);
      labelTp
        ..text = TextSpan(text: _fmtPrice(p), style: priceStyle)
        ..layout()
        ..paint(canvas, Offset(plotW + 4, yy - labelTp.height / 2));
    }

    // 日期标签
    final dateStyle = TextStyle(
        color: AppColors.textTertiary, fontSize: 9, fontFamily: 'monospace');
    final step = _dateLabelStep(n);
    for (var i = 0; i < n; i += step) {
      labelTp
        ..text = TextSpan(
            text: _fmtMd(candles[i].date), style: dateStyle)
        ..layout();
      final cx = (x(i) - labelTp.width / 2).clamp(0.0, plotW - labelTp.width);
      labelTp.paint(
          canvas, Offset(cx, size.height - _dateLabelH + 2));
    }

    // 蜡烛：涨红跌绿（A 股惯例，AppColors.positive=红）。
    final nPaint = Paint(); // 阳线（涨）
    final dPaint = Paint(); // 阴线（跌）
    final candleW = (plotW / n * 0.7).clamp(1.0, 12.0);
    for (var i = 0; i < n; i++) {
      final c = candles[i];
      final o = c.open ?? c.close;
      final h = c.high ?? math.max(o, c.close);
      final l = c.low ?? math.min(o, c.close);
      final up = c.close >= o;
      nPaint.color = up ? AppColors.positive : AppColors.negative;
      dPaint.color = nPaint.color;

      // 影线
      canvas.drawLine(Offset(x(i), y(h)), Offset(x(i), y(l)), nPaint
        ..strokeWidth = math.max(candleW * 0.12, 0.6));
      // 实体
      final top = y(math.max(o, c.close));
      final bottom = y(math.min(o, c.close));
      final bodyH = math.max(bottom - top, 1.0);
      canvas.drawRect(
        Rect.fromLTWH(x(i) - candleW / 2, top, candleW, bodyH),
        nPaint,
      );
    }

    // 均线 / BOLL
    void drawLine(List<double?>? s, Color color) {
      if (s == null) return;
      final path = Path();
      var started = false;
      for (var i = 0; i < n; i++) {
        final v = s[i];
        if (v == null) {
          started = false;
          continue;
        }
        if (!started) {
          path.moveTo(x(i), y(v));
          started = true;
        } else {
          path.lineTo(x(i), y(v));
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0
          ..isAntiAlias = true,
      );
    }

    drawLine(bollMid, const Color(0xFFEAB308));
    drawLine(bollUp, const Color(0xFF9333EA));
    drawLine(bollLow, const Color(0xFF9333EA));
    drawLine(ma5, const Color(0xFF2563EB));
    drawLine(ma10, const Color(0xFFEAB308));
    drawLine(ma20, const Color(0xFF9333EA));

    // 左上角指标数值标签（只显示最后一个有效值）。
    const legendStyle = TextStyle(fontSize: 9, fontFamily: 'monospace');
    var lx = 4.0;
    void legend(String label, double? v, Color color) {
      if (v == null) return;
      labelTp
        ..text = TextSpan(
          text: '$label ${_fmtPrice(v)}',
          style: legendStyle.copyWith(color: color),
        )
        ..layout();
      labelTp.paint(canvas, Offset(lx, 2));
      lx += labelTp.width + 8;
    }

    legend('MA5', ma5?.last, const Color(0xFF2563EB));
    legend('MA10', ma10?.last, const Color(0xFFEAB308));
    legend('MA20', ma20?.last, const Color(0xFF9333EA));
    if (bollMid?.last != null) {
      legend('BOLL', bollMid!.last, const Color(0xFF16A34A));
    }
  }

  static String _fmtPrice(double v) {
    if (v.abs() >= 1000) return v.toStringAsFixed(0);
    if (v.abs() >= 100) return v.toStringAsFixed(1);
    return v.toStringAsFixed(2);
  }

  @override
  bool shouldRepaint(covariant _MainPanePainter old) =>
      old.candles != candles ||
      old.ma5 != ma5 ||
      old.ma10 != ma10 ||
      old.ma20 != ma20 ||
      old.bollMid != bollMid ||
      old.bollUp != bollUp ||
      old.bollLow != bollLow;
}

/// 成交量副图。
class _VolPane extends StatelessWidget {
  const _VolPane({required this.candles});
  final List<CandlePoint> candles;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _VolPanePainter(candles: candles),
      size: Size.infinite,
    );
  }
}

class _VolPanePainter extends CustomPainter {
  _VolPanePainter({required this.candles});
  final List<CandlePoint> candles;

  static const _labelW = 52.0;

  @override
  void paint(Canvas canvas, Size size) {
    final plotW = size.width - _labelW;
    final plotH = size.height - 10;
    if (plotW <= 0 || plotH <= 0 || candles.isEmpty) return;

    var maxV = 0.0;
    for (final c in candles) {
      maxV = math.max(maxV, c.vol ?? 0);
    }
    if (maxV <= 0) {
      // 无成交量数据时提示。
      final tp = TextPainter(
        text: TextSpan(
            text: '成交量数据缺失',
            style: TextStyle(color: AppColors.textTertiary, fontSize: 9)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(4, (size.height - tp.height) / 2));
      return;
    }

    final n = candles.length;
    final barW = (plotW / n * 0.7).clamp(1.0, 12.0);
    for (var i = 0; i < n; i++) {
      final c = candles[i];
      final v = c.vol ?? 0;
      if (v <= 0) continue;
      final barH = v / maxV * (plotH - 4);
      final o = c.open ?? c.close;
      final color = c.close >= o ? AppColors.positive : AppColors.negative;
      canvas.drawRect(
        Rect.fromLTWH(
            (i + 0.5) * plotW / n - barW / 2, plotH - barH, barW, barH),
        Paint()..color = color.withValues(alpha: 0.8),
      );
    }

    // 标题 + 最大量刻度
    final tp = TextPainter(
      text: TextSpan(
        text: '成交量 ${_fmtVol(maxV)}',
        style: TextStyle(
            color: AppColors.textTertiary, fontSize: 9, fontFamily: 'monospace'),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, const Offset(4, 0));
  }

  static String _fmtVol(double v) {
    if (v >= 100000000) return '${(v / 100000000).toStringAsFixed(1)}亿';
    if (v >= 10000) return '${(v / 10000).toStringAsFixed(1)}万';
    return v.toStringAsFixed(0);
  }

  @override
  bool shouldRepaint(covariant _VolPanePainter old) => old.candles != candles;
}

/// MACD 副图：DIF / DEA 线 + 红绿柱。
class _MacdPane extends StatelessWidget {
  const _MacdPane({required this.candles});
  final List<CandlePoint> candles;

  @override
  Widget build(BuildContext context) {
    final (dif, dea, bar) = ChartIndicators.macdSeries(candles);
    return CustomPaint(
      painter: _MacdPanePainter(dif: dif, dea: dea, bar: bar),
      size: Size.infinite,
    );
  }
}

class _MacdPanePainter extends CustomPainter {
  _MacdPanePainter({required this.dif, required this.dea, required this.bar});
  final List<double?> dif;
  final List<double?> dea;
  final List<double?> bar;

  @override
  void paint(Canvas canvas, Size size) {
    final n = dif.length;
    if (n == 0) return;
    final plotW = size.width - 52;
    final plotH = size.height - 10;
    if (plotW <= 0 || plotH <= 0) return;

    var maxAbs = 0.0;
    for (final s in [dif, dea, bar]) {
      for (final v in s) {
        if (v != null) maxAbs = math.max(maxAbs, v.abs());
      }
    }
    if (maxAbs == 0) {
      final tp = TextPainter(
        text: TextSpan(
            text: 'MACD 数据不足',
            style: TextStyle(color: AppColors.textTertiary, fontSize: 9)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(4, (size.height - tp.height) / 2));
      return;
    }

    final zero = plotH / 2;
    double y(double v) => zero - v / maxAbs * (plotH / 2 - 4);
    double x(int i) => (i + 0.5) * plotW / n;

    // 零轴
    canvas.drawLine(
      Offset(0, zero),
      Offset(plotW, zero),
      Paint()
        ..color = AppColors.borderDim.withValues(alpha: 0.6)
        ..strokeWidth = 0.5,
    );

    // 柱
    final barW = (plotW / n * 0.7).clamp(1.0, 12.0);
    for (var i = 0; i < n; i++) {
      final v = bar[i];
      if (v == null) continue;
      final color = v >= 0 ? AppColors.positive : AppColors.negative;
      final top = math.min(y(v), zero);
      final h = (y(v) - zero).abs().clamp(0.5, plotH);
      canvas.drawRect(
        Rect.fromLTWH(x(i) - barW / 2, top, barW, h),
        Paint()..color = color.withValues(alpha: 0.85),
      );
    }

    // DIF / DEA 线
    void line(List<double?> s, Color color) {
      final path = Path();
      var started = false;
      for (var i = 0; i < n; i++) {
        final v = s[i];
        if (v == null) {
          started = false;
          continue;
        }
        if (!started) {
          path.moveTo(x(i), y(v));
          started = true;
        } else {
          path.lineTo(x(i), y(v));
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0
          ..isAntiAlias = true,
      );
    }

    line(dif, const Color(0xFF2563EB));
    line(dea, const Color(0xFFEAB308));

    // 标题
    final tp = TextPainter(
      text: TextSpan(
        text:
            'MACD(12,26,9) DIF ${_f(dif.last)} DEA ${_f(dea.last)}',
        style: TextStyle(
            color: AppColors.textTertiary, fontSize: 9, fontFamily: 'monospace'),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, const Offset(4, 0));
  }

  static String _f(double? v) =>
      v == null ? '--' : v.toStringAsFixed(2);

  @override
  bool shouldRepaint(covariant _MacdPanePainter old) =>
      old.dif != dif || old.dea != dea || old.bar != bar;
}

/// KDJ 副图。
class _KdjPane extends StatelessWidget {
  const _KdjPane({required this.candles});
  final List<CandlePoint> candles;

  @override
  Widget build(BuildContext context) {
    final (k, d, j) = ChartIndicators.kdjSeries(candles);
    return CustomPaint(
      painter: _KdjPanePainter(k: k, d: d, j: j),
      size: Size.infinite,
    );
  }
}

class _KdjPanePainter extends CustomPainter {
  _KdjPanePainter({required this.k, required this.d, required this.j});
  final List<double?> k;
  final List<double?> d;
  final List<double?> j;

  @override
  void paint(Canvas canvas, Size size) {
    final n = k.length;
    if (n == 0) return;
    final plotW = size.width - 52;
    final plotH = size.height - 10;
    if (plotW <= 0 || plotH <= 0) return;

    // KDJ 固定 0-100 区间（J 可能超出，做裁剪）。
    var maxV = 100.0;
    var minV = 0.0;
    double y(double v) =>
        4 + (maxV - v) / (maxV - minV) * (plotH - 8);
    double x(int i) => (i + 0.5) * plotW / n;

    // 20 / 80 参考线
    final refPaint = Paint()
      ..color = AppColors.borderDim.withValues(alpha: 0.6)
      ..strokeWidth = 0.5;
    canvas.drawLine(Offset(0, y(80)), Offset(plotW, y(80)), refPaint);
    canvas.drawLine(Offset(0, y(20)), Offset(plotW, y(20)), refPaint);

    void line(List<double?> s, Color color) {
      final path = Path();
      var started = false;
      for (var i = 0; i < n; i++) {
        final v = s[i];
        if (v == null) {
          started = false;
          continue;
        }
        final yy = y(v.clamp(-20, 120));
        if (!started) {
          path.moveTo(x(i), yy);
          started = true;
        } else {
          path.lineTo(x(i), yy);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0
          ..isAntiAlias = true,
      );
    }

    line(k, const Color(0xFF2563EB));
    line(d, const Color(0xFFEAB308));
    line(j, const Color(0xFF9333EA));

    final tp = TextPainter(
      text: TextSpan(
        text: 'KDJ(9,3,3) K ${_f(k.last)} D ${_f(d.last)} J ${_f(j.last)}',
        style: TextStyle(
            color: AppColors.textTertiary, fontSize: 9, fontFamily: 'monospace'),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, const Offset(4, 0));
  }

  static String _f(double? v) =>
      v == null ? '--' : v.toStringAsFixed(1);

  @override
  bool shouldRepaint(covariant _KdjPanePainter old) =>
      old.k != k || old.d != d || old.j != j;
}

/// RSI 副图。
class _RsiPane extends StatelessWidget {
  const _RsiPane({required this.candles});
  final List<CandlePoint> candles;

  @override
  Widget build(BuildContext context) {
    final rsi = ChartIndicators.rsiSeries(candles);
    return CustomPaint(
      painter: _RsiPanePainter(rsi: rsi),
      size: Size.infinite,
    );
  }
}

class _RsiPanePainter extends CustomPainter {
  _RsiPanePainter({required this.rsi});
  final List<double?> rsi;

  @override
  void paint(Canvas canvas, Size size) {
    final n = rsi.length;
    if (n == 0) return;
    final plotW = size.width - 52;
    final plotH = size.height - 10;
    if (plotW <= 0 || plotH <= 0) return;

    double y(double v) => 4 + (100 - v) / 100 * (plotH - 8);
    double x(int i) => (i + 0.5) * plotW / n;

    // 30 / 70 参考线
    final refPaint = Paint()
      ..color = AppColors.borderDim.withValues(alpha: 0.6)
      ..strokeWidth = 0.5;
    canvas.drawLine(Offset(0, y(70)), Offset(plotW, y(70)), refPaint);
    canvas.drawLine(Offset(0, y(30)), Offset(plotW, y(30)), refPaint);

    final path = Path();
    var started = false;
    for (var i = 0; i < n; i++) {
      final v = rsi[i];
      if (v == null) {
        started = false;
        continue;
      }
      if (!started) {
        path.moveTo(x(i), y(v));
        started = true;
      } else {
        path.lineTo(x(i), y(v));
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF2563EB)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..isAntiAlias = true,
    );

    final tp = TextPainter(
      text: TextSpan(
        text: 'RSI(14) ${_f(rsi.last)}',
        style: TextStyle(
            color: AppColors.textTertiary, fontSize: 9, fontFamily: 'monospace'),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, const Offset(4, 0));
  }

  static String _f(double? v) =>
      v == null ? '--' : v.toStringAsFixed(1);

  @override
  bool shouldRepaint(covariant _RsiPanePainter old) => old.rsi != rsi;
}
