/// 小应用的图表：折线 / 柱状 / 面积 与 K 线。纯 CustomPainter，不引第三方库。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../expr/xel.dart' show numStr;

/// 序列配色：品牌色在前，其余固定。
List<Color> seriesColors() =>
    [AppColors.amber, AppColors.info, AppColors.positive, AppColors.negative];

class ChartSeries {
  ChartSeries(this.name, this.values);
  final String name;
  final List<double?> values;
}

class MiniChart extends StatelessWidget {
  const MiniChart({
    super.key,
    required this.kind,
    required this.labels,
    required this.series,
    this.height = 160,
  });

  final String kind; // line / bar / area
  final List<String> labels;
  final List<ChartSeries> series;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = seriesColors();
    final hasData = series.any((s) => s.values.any((v) => v != null));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (series.length > 1 || (series.isNotEmpty && series.first.name.isNotEmpty))
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.xs),
            child: Wrap(spacing: AppSpace.md, children: [
              for (var i = 0; i < series.length; i++)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                          color: colors[i % colors.length],
                          borderRadius: BorderRadius.circular(2))),
                  const SizedBox(width: 4),
                  Text(series[i].name,
                      style: AppType.micro
                          .copyWith(color: AppColors.textSecondary)),
                ]),
            ]),
          ),
        SizedBox(
          height: height,
          child: hasData
              ? CustomPaint(
                  painter: _ChartPainter(
                    kind: kind,
                    labels: labels,
                    series: series,
                    colors: colors,
                    grid: AppColors.borderDim,
                    text: AppColors.textTertiary,
                  ),
                )
              : Center(
                  child: Text('暂无数据',
                      style: AppType.caption
                          .copyWith(color: AppColors.textTertiary))),
        ),
      ],
    );
  }
}

String _axisNum(double v) {
  final a = v.abs();
  if (a >= 1e8) return '${numStr((v / 1e8 * 10).roundToDouble() / 10)}亿';
  if (a >= 1e4) return '${numStr((v / 1e4 * 10).roundToDouble() / 10)}万';
  if (a >= 100) return numStr(v.roundToDouble());
  return numStr((v * 100).roundToDouble() / 100);
}

class _ChartPainter extends CustomPainter {
  _ChartPainter({
    required this.kind,
    required this.labels,
    required this.series,
    required this.colors,
    required this.grid,
    required this.text,
  });

  final String kind;
  final List<String> labels;
  final List<ChartSeries> series;
  final List<Color> colors;
  final Color grid;
  final Color text;

  @override
  void paint(Canvas canvas, Size size) {
    var lo = double.infinity, hi = -double.infinity;
    var n = labels.length;
    for (final s in series) {
      n = math.max(n, s.values.length);
      for (final v in s.values) {
        if (v == null || v.isNaN || v.isInfinite) continue;
        lo = math.min(lo, v);
        hi = math.max(hi, v);
      }
    }
    if (n == 0 || lo == double.infinity) return;
    if (kind == 'bar') {
      lo = math.min(lo, 0);
      hi = math.max(hi, 0);
    }
    if (hi == lo) {
      hi += 1;
      lo -= 1;
    }
    final pad = (hi - lo) * 0.08;
    hi += pad;
    if (!(kind == 'bar' && lo == 0)) lo -= pad;

    const left = 40.0, bottom = 16.0, top = 4.0;
    final w = size.width - left, h = size.height - bottom - top;
    double y(double v) => top + h - (v - lo) / (hi - lo) * h;

    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 0.5;
    for (var i = 0; i <= 3; i++) {
      final v = lo + (hi - lo) * i / 3;
      final yy = y(v);
      canvas.drawLine(Offset(left, yy), Offset(size.width, yy), gridPaint);
      _label(canvas, _axisNum(v), Offset(0, yy - 6), left - 4, TextAlign.right);
    }
    if (labels.isNotEmpty) {
      final idx = {0, labels.length ~/ 2, labels.length - 1};
      for (final i in idx) {
        final x = left + (n == 1 ? w / 2 : w * i / (n - 1));
        final align = i == 0
            ? TextAlign.left
            : (i == labels.length - 1 ? TextAlign.right : TextAlign.center);
        final lx = align == TextAlign.left
            ? x
            : (align == TextAlign.right ? x - 72 : x - 36);
        _label(canvas, labels[i], Offset(lx, size.height - bottom + 2), 72, align);
      }
    }

    for (var si = 0; si < series.length; si++) {
      final c = colors[si % colors.length];
      final vals = series[si].values;
      if (kind == 'bar') {
        final slot = w / n;
        final bw = math.max(1.0, slot * 0.7 / series.length);
        for (var i = 0; i < vals.length; i++) {
          final v = vals[i];
          if (v == null) continue;
          final x = left + slot * i + slot * 0.15 + bw * si;
          final y0 = y(math.max(lo, 0)), y1 = y(v);
          canvas.drawRect(Rect.fromLTRB(x, math.min(y0, y1), x + bw, math.max(y0, y1)),
              Paint()..color = c);
        }
        continue;
      }
      final path = Path();
      var started = false;
      Offset? first, last;
      for (var i = 0; i < vals.length; i++) {
        final v = vals[i];
        if (v == null) continue;
        final p = Offset(left + (n == 1 ? w / 2 : w * i / (n - 1)), y(v));
        if (!started) {
          path.moveTo(p.dx, p.dy);
          first = p;
          started = true;
        } else {
          path.lineTo(p.dx, p.dy);
        }
        last = p;
      }
      if (!started) continue;
      if (kind == 'area' && first != null && last != null) {
        final fill = Path.from(path)
          ..lineTo(last.dx, top + h)
          ..lineTo(first.dx, top + h)
          ..close();
        canvas.drawPath(fill, Paint()..color = c.withValues(alpha: 0.15));
      }
      canvas.drawPath(
          path,
          Paint()
            ..color = c
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6
            ..strokeJoin = StrokeJoin.round);
    }
  }

  void _label(Canvas canvas, String s, Offset at, double width, TextAlign align) {
    final tp = TextPainter(
      text: TextSpan(
          text: s,
          style: AppType.micro.copyWith(color: text, fontSize: 10)),
      textDirection: TextDirection.ltr,
      textAlign: align,
      maxLines: 1,
      ellipsis: '…',
    )..layout(minWidth: width, maxWidth: width);
    tp.paint(canvas, at);
  }

  @override
  bool shouldRepaint(covariant _ChartPainter old) =>
      old.series != series || old.labels != labels || old.kind != kind;
}

class KBar {
  KBar(this.date, this.open, this.high, this.low, this.close);
  final String date;
  final double open, high, low, close;
}

class MiniKline extends StatelessWidget {
  const MiniKline({super.key, required this.bars, this.height = 200});
  final List<KBar> bars;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (bars.isEmpty) {
      return SizedBox(
          height: height,
          child: Center(
              child: Text('暂无数据',
                  style: AppType.caption.copyWith(color: AppColors.textTertiary))));
    }
    return SizedBox(
      height: height,
      child: CustomPaint(
          painter: _KPainter(bars, AppColors.borderDim, AppColors.textTertiary)),
    );
  }
}

class _KPainter extends CustomPainter {
  _KPainter(this.bars, this.grid, this.text);
  final List<KBar> bars;
  final Color grid, text;

  @override
  void paint(Canvas canvas, Size size) {
    var lo = double.infinity, hi = -double.infinity;
    for (final b in bars) {
      lo = math.min(lo, b.low);
      hi = math.max(hi, b.high);
    }
    if (hi <= lo) hi = lo + 1;
    const left = 40.0, bottom = 16.0;
    final w = size.width - left, h = size.height - bottom;
    double y(double v) => h - (v - lo) / (hi - lo) * h;
    final g = Paint()
      ..color = grid
      ..strokeWidth = 0.5;
    for (var i = 0; i <= 3; i++) {
      final v = lo + (hi - lo) * i / 3;
      canvas.drawLine(Offset(left, y(v)), Offset(size.width, y(v)), g);
      final tp = TextPainter(
          text: TextSpan(
              text: _axisNum(v),
              style: AppType.micro.copyWith(color: text, fontSize: 10)),
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.right)
        ..layout(minWidth: left - 4, maxWidth: left - 4);
      tp.paint(canvas, Offset(0, y(v) - 6));
    }
    final slot = w / bars.length;
    final bw = math.max(1.0, slot * 0.7);
    for (var i = 0; i < bars.length; i++) {
      final b = bars[i];
      final up = b.close >= b.open;
      final p = Paint()..color = up ? AppColors.positive : AppColors.negative;
      final cx = left + slot * i + slot / 2;
      canvas.drawLine(Offset(cx, y(b.high)), Offset(cx, y(b.low)), p..strokeWidth = 1);
      final top = y(math.max(b.open, b.close)), bot = y(math.min(b.open, b.close));
      canvas.drawRect(
          Rect.fromLTRB(cx - bw / 2, top, cx + bw / 2, math.max(bot, top + 1)), p);
    }
    final first = bars.first.date, last = bars.last.date;
    for (final (s, x, align) in [
      (first, left, TextAlign.left),
      (last, size.width - 72, TextAlign.right)
    ]) {
      final tp = TextPainter(
          text: TextSpan(
              text: s, style: AppType.micro.copyWith(color: text, fontSize: 10)),
          textDirection: TextDirection.ltr,
          textAlign: align)
        ..layout(minWidth: 72, maxWidth: 72);
      tp.paint(canvas, Offset(x, size.height - bottom + 2));
    }
  }

  @override
  bool shouldRepaint(covariant _KPainter old) => old.bars != bars;
}
