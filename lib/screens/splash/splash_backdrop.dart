import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 开屏的「夜空」色组：一条竖向多段渐变 + 地平线辉光 + 线条 / 星光的底色。
///
/// 两套：
/// - [neutral]：中性夜色。它同时是原生启动屏那张渐变图（iOS LaunchImage /
///   Android splash_gradient），所以冷启动第一帧不跳。
/// - [brand]：品牌夜色 —— 暖墨 → 古铜 → 金 → 桃色天光。多主题下线后它成了唯一的
///   一套（原先按主题切色的 forTopic 一起去掉了）。
///
/// 改 [neutral.stops] 必须同时重新生成原生启动屏图片（tools/gen_splash_gradient.py）。
@immutable
class SplashPalette {
  const SplashPalette({
    required this.stops,
    required this.glow,
    required this.line,
    required this.star,
    required this.titleTop,
    required this.titleBottom,
    required this.slogan,
  });

  /// 竖向渐变五段色，自上而下，位置见 [stopPositions]。
  final List<Color> stops;

  /// 地平线辉光 / 柔光斑的颜色。
  final Color glow;

  /// 细线（轨道、等高线、进度发丝线）的底色，透明度由画笔给。
  final Color line;

  /// 星点颜色。
  final Color star;

  /// 题字「喜爱」的上 / 下渐变色。
  final Color titleTop;
  final Color titleBottom;

  /// 口号颜色。
  final Color slogan;

  static const stopPositions = <double>[0, 0.3, 0.58, 0.82, 1];

  static const neutral = SplashPalette(
    stops: [
      Color(0xFF0B0B12),
      Color(0xFF15141F),
      Color(0xFF242130),
      Color(0xFF3E3745),
      Color(0xFF6E6068),
    ],
    glow: Color(0xFFCDB4B4),
    line: Color(0xFFE6DFE8),
    star: Color(0xFFFFFFFF),
    titleTop: Color(0xFFF7F4F6),
    titleBottom: Color(0xFFDCD2D8),
    slogan: Color(0xFFE2DCE2),
  );

  static const brand = SplashPalette(
    stops: [
      Color(0xFF120B06),
      Color(0xFF24160C),
      Color(0xFF452B16),
      Color(0xFF7E5530),
      Color(0xFFC99668),
    ],
    glow: Color(0xFFF4C48C),
    line: Color(0xFFF2DCB3),
    star: Color(0xFFFFF1D8),
    titleTop: Color(0xFFFFF7E8),
    titleBottom: Color(0xFFE6C48A),
    slogan: Color(0xFFEBDCC2),
  );

  static SplashPalette lerp(SplashPalette a, SplashPalette b, double t) {
    if (t <= 0) return a;
    if (t >= 1) return b;
    Color c(Color x, Color y) => Color.lerp(x, y, t)!;
    return SplashPalette(
      stops: [for (var i = 0; i < a.stops.length; i++) c(a.stops[i], b.stops[i])],
      glow: c(a.glow, b.glow),
      line: c(a.line, b.line),
      star: c(a.star, b.star),
      titleTop: c(a.titleTop, b.titleTop),
      titleBottom: c(a.titleBottom, b.titleBottom),
      slogan: c(a.slogan, b.slogan),
    );
  }
}

/// 开屏背景画布：渐变、辉光、轨道细线、湖面 / 等高线、星光。
///
/// 全部按 0..1 的进度参数画，动效节奏由 `SplashScreen` 统一给；
/// 进度全为 0 时只剩纯竖向渐变 —— 与原生启动屏那张图逐像素一致。
class SplashBackdropPainter extends CustomPainter {
  SplashBackdropPainter({
    required this.palette,
    required this.clock,
    required this.ambient,
    required this.stars,
    required this.lines,
    required this.focusY,
  });

  final SplashPalette palette;

  /// 连续时钟（秒），驱动闪烁、呼吸、漂移。减少动态效果时固定不变。
  final double clock;

  /// 辉光 / 光斑的出现进度。
  final double ambient;

  /// 星光出现进度（每颗星在其中错开）。
  final double stars;

  /// 细线描出进度。
  final double lines;

  /// 题字中心的纵向位置（占屏高比例）；轨道围着它转。
  final double focusY;

  static final List<_Star> _starField = _buildStars();
  static const List<_Sparkle> _sparkles = [
    _Sparkle(0.17, 0.13, 6.5, 0.0, 0.10),
    _Sparkle(0.83, 0.085, 4.5, 1.7, 0.30),
    _Sparkle(0.70, 0.27, 8.0, 3.1, 0.45),
    _Sparkle(0.24, 0.31, 3.8, 4.4, 0.62),
    _Sparkle(0.90, 0.52, 5.0, 2.3, 0.78),
  ];

  static List<_Star> _buildStars() {
    final r = math.Random(20261011);
    final out = <_Star>[];
    while (out.length < 54) {
      final x = r.nextDouble();
      // 越往上越密：夜空在上，天光在下。
      final y = math.pow(r.nextDouble(), 1.55).toDouble() * 0.74;
      // 题字附近留白，别让星点压字。
      if ((y - 0.43).abs() < 0.085 && (x - 0.5).abs() < 0.3) continue;
      out.add(_Star(
        x: x,
        y: y,
        radius: 0.35 + math.pow(r.nextDouble(), 2.2) * 0.95,
        alpha: 0.30 + r.nextDouble() * 0.6,
        period: 2.2 + r.nextDouble() * 3.2,
        phase: r.nextDouble() * math.pi * 2,
        delay: r.nextDouble(),
      ));
    }
    return out;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final w = size.width, h = size.height;

    // 1. 竖向多段渐变（原生启动屏同一套色值）。
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: palette.stops,
          stops: SplashPalette.stopPositions,
        ).createShader(rect),
    );

    if (ambient > 0) _paintAmbient(canvas, size);
    if (lines > 0) {
      _paintOrbits(canvas, size);
      _paintContours(canvas, size);
    }
    if (stars > 0) _paintStars(canvas, w, h);
  }

  void _glowCircle(Canvas canvas, Offset c, double r, Color color, double a) {
    if (a <= 0) return;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(colors: [
          color.withValues(alpha: a),
          color.withValues(alpha: a * 0.35),
          color.withValues(alpha: 0),
        ], stops: const [0, 0.45, 1])
            .createShader(Rect.fromCircle(center: c, radius: r)),
    );
  }

  void _paintAmbient(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final breath = 0.92 + 0.08 * math.sin(clock * 2 * math.pi / 7);
    // 地平线辉光：天光从屏幕下沿外升起来。
    _glowCircle(canvas, Offset(w * 0.5, h * 1.08), h * 0.62, palette.glow,
        0.42 * ambient * breath);
    // 题字背后极淡的一团光，让字「浮」起来。
    _glowCircle(canvas, Offset(w * 0.5, h * focusY), w * 0.62,
        palette.titleTop, 0.07 * ambient);
  }

  void _paintOrbits(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final c = Offset(w * 0.5, h * focusY);
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(-0.14);
    const specs = [
      // rx（占屏宽）, ry/rx, 透明度, 起点
      (0.50, 0.30, 0.22, 0.58),
      (0.74, 0.32, 0.13, 0.12),
      (1.02, 0.34, 0.07, 0.36),
    ];
    for (var i = 0; i < specs.length; i++) {
      final (rxf, ratio, a, start) = specs[i];
      final rx = w * rxf, ry = rx * ratio;
      final oval = Rect.fromCenter(center: Offset.zero, width: rx * 2, height: ry * 2);
      final path = Path()..addOval(oval);
      final metric = path.computeMetrics().first;
      final len = metric.length;
      final sweep = (lines * 1.15 - i * 0.07).clamp(0.0, 1.0);
      if (sweep <= 0) continue;
      final from = len * start;
      final to = from + len * sweep;
      final seg = Path()..addPath(metric.extractPath(from, math.min(to, len)), Offset.zero);
      if (to > len) seg.addPath(metric.extractPath(0, to - len), Offset.zero);
      canvas.drawPath(
        seg,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.7
          ..isAntiAlias = true
          ..shader = LinearGradient(colors: [
            palette.line.withValues(alpha: a * 0.15),
            palette.line.withValues(alpha: a),
            palette.line.withValues(alpha: a * 0.15),
          ]).createShader(oval),
      );
      // 最里那条轨道上有一粒光在走（从画线的笔尖接上，之后匀速绕行）。
      if (i == 0 && sweep >= 1) {
        final t = metric.getTangentForOffset(len * ((start + clock * 0.03) % 1));
        if (t != null) {
          _glowCircle(canvas, t.position, 7, palette.star, 0.45);
          canvas.drawCircle(t.position, 1.3,
              Paint()..color = palette.star.withValues(alpha: 0.9));
        }
      }
    }
    canvas.restore();
  }

  void _paintContours(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    // 下方几道平行起伏的细线：喜爱钱看是行情，喜爱钓鱼看是湖面。
    // 同一条波形逐道下移、振幅渐大，彼此不交叉。
    const steps = 56;
    final phase = clock * 0.35;
    for (var i = 0; i < 4; i++) {
      final reveal = ((lines - 0.2 - i * 0.08) / 0.5).clamp(0.0, 1.0);
      if (reveal <= 0) continue;
      final baseY = h * (0.80 + i * 0.036);
      final amp = 4.0 + i * 1.2;
      final path = Path();
      for (var s = 0; s <= steps; s++) {
        final x = w * s / steps;
        final u = s / steps * math.pi * 2;
        final y = baseY +
            amp * math.sin(u * 0.9 + phase + i * 0.35) +
            amp * 0.35 * math.sin(u * 2.1 - phase * 0.6);
        s == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
      }
      final a = (0.20 - i * 0.035) * reveal;
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.6
          ..shader = LinearGradient(colors: [
            palette.line.withValues(alpha: 0),
            palette.line.withValues(alpha: a),
            palette.line.withValues(alpha: a),
            palette.line.withValues(alpha: 0),
          ], stops: const [0, 0.28, 0.72, 1])
              .createShader(Rect.fromLTWH(0, baseY - 20, w, 40)),
      );
    }
  }

  void _paintStars(Canvas canvas, double w, double h) {
    final dot = Paint()..isAntiAlias = true;
    for (final s in _starField) {
      final reveal = ((stars - s.delay * 0.6) / 0.4).clamp(0.0, 1.0);
      if (reveal <= 0) continue;
      final tw = 0.55 + 0.45 * math.sin(clock * 2 * math.pi / s.period + s.phase);
      dot.color = palette.star.withValues(alpha: s.alpha * reveal * tw);
      canvas.drawCircle(Offset(s.x * w, s.y * h), s.radius, dot);
    }
    for (final k in _sparkles) {
      final reveal = ((stars - k.delay * 0.6) / 0.4).clamp(0.0, 1.0);
      if (reveal <= 0) continue;
      final tw = 0.5 + 0.5 * math.sin(clock * 2 * math.pi / 3.6 + k.phase);
      final c = Offset(k.x * w, k.y * h);
      final r = k.size * (0.78 + 0.22 * tw) * (0.6 + 0.4 * reveal);
      _glowCircle(canvas, c, r * 2.2, palette.star, 0.22 * reveal * (0.6 + 0.4 * tw));
      final waist = r * 0.11;
      final p = Path()
        ..moveTo(c.dx, c.dy - r)
        ..lineTo(c.dx + waist, c.dy - waist)
        ..lineTo(c.dx + r, c.dy)
        ..lineTo(c.dx + waist, c.dy + waist)
        ..lineTo(c.dx, c.dy + r)
        ..lineTo(c.dx - waist, c.dy + waist)
        ..lineTo(c.dx - r, c.dy)
        ..lineTo(c.dx - waist, c.dy - waist)
        ..close();
      canvas.drawPath(
          p, Paint()..color = palette.star.withValues(alpha: 0.9 * reveal * (0.65 + 0.35 * tw)));
    }
  }

  @override
  bool shouldRepaint(SplashBackdropPainter old) =>
      old.clock != clock ||
      old.ambient != ambient ||
      old.stars != stars ||
      old.lines != lines ||
      old.focusY != focusY ||
      !identical(old.palette, palette);
}

class _Star {
  const _Star({
    required this.x,
    required this.y,
    required this.radius,
    required this.alpha,
    required this.period,
    required this.phase,
    required this.delay,
  });
  final double x, y, radius, alpha, period, phase, delay;
}

class _Sparkle {
  const _Sparkle(this.x, this.y, this.size, this.phase, this.delay);
  final double x, y, size, phase, delay;
}
