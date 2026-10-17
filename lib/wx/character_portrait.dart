import 'package:flutter/material.dart';

import '../models/resident.dart';

/// 居民头像：优先用写真（`assets/portraits/<id>.jpg`），没有素材时回落到
/// 一支笔画出来的插画半身像（渐变底 + 发型/肤色 + 极简五官）。
///
/// 写真由 `.tools/gen_portraits.py` 调阿里云百炼生成；插画兜底保证在缺图、
/// 加载失败（比如金图测试里没有 assets）时也不会出现空白头像。
class CharacterPortrait extends StatelessWidget {
  const CharacterPortrait({
    super.key,
    required this.resident,
    this.radius = 8,
  });

  final Resident resident;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.asset(
        'assets/portraits/${resident.id}.jpg',
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => CustomPaint(
          painter: _PortraitPainter(resident),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _PortraitPainter extends CustomPainter {
  _PortraitPainter(this.r);

  final Resident r;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final rect = Offset.zero & size;

    // 底：从左上到右下的双色渐变。
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [r.colorA, r.colorB],
        ).createShader(rect),
    );

    // 右上角一团柔光，让人物从背景里浮起来。
    final glowRect = Rect.fromCircle(
        center: Offset(w * 0.78, h * 0.16), radius: w * 0.75);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white.withValues(alpha: 0.22),
            Colors.white.withValues(alpha: 0.0),
          ],
        ).createShader(glowRect),
    );

    _paintBackHair(canvas, w, h);

    // 肩与身体：一个压低的椭圆，像裁到胸口的半身像。
    canvas.drawPath(
      Path()
        ..addOval(Rect.fromCenter(
          center: Offset(w * 0.5, h * 1.06),
          width: w * 1.02,
          height: h * 0.82,
        )),
      Paint()..color = _shade(r.colorB, 0.72),
    );
    // 衣领的一点亮面
    canvas.drawPath(
      Path()
        ..addOval(Rect.fromCenter(
          center: Offset(w * 0.5, h * 1.12),
          width: w * 0.66,
          height: h * 0.52,
        )),
      Paint()..color = _shade(r.colorB, 0.86),
    );

    // 脖子
    final neckRect = Rect.fromCenter(
        center: Offset(w * 0.5, h * 0.59),
        width: w * 0.16,
        height: h * 0.16);
    canvas.drawRRect(
      RRect.fromRectAndRadius(neckRect, Radius.circular(w * 0.06)),
      Paint()..color = _shade(r.skin, 0.9),
    );

    // 头
    final headRect = Rect.fromCenter(
        center: Offset(w * 0.5, h * 0.37),
        width: w * 0.34,
        height: h * 0.42);
    canvas.drawOval(headRect, Paint()..color = r.skin);

    // 下颌的一点阴影，让头不是一张平片。
    canvas.save();
    canvas.clipPath(Path()..addOval(headRect));
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(w * 0.5, h * 0.58),
          width: w * 0.30,
          height: h * 0.16),
      Paint()..color = _shade(r.skin, 0.9).withValues(alpha: 0.55),
    );
    // 颧骨的高光
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(w * 0.60, h * 0.36),
          width: w * 0.10,
          height: h * 0.14),
      Paint()..color = Colors.white.withValues(alpha: 0.10),
    );
    canvas.restore();

    _paintFrontHair(canvas, w, h, headRect);
    _paintFace(canvas, w, h);

    // 耳饰：只在长发 / 波波头上有，位置在耳垂。
    if (r.hairStyle == HairStyle.long || r.hairStyle == HairStyle.bob) {
      canvas.drawCircle(
        Offset(w * 0.335, h * 0.44),
        w * 0.014,
        Paint()..color = const Color(0xFFE8C88A),
      );
    }

    // 底部压一层暗角，方便卡片上压白字。
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: 0.28),
          ],
          stops: const [0.55, 1],
        ).createShader(rect),
    );
  }

  void _paintBackHair(Canvas canvas, double w, double h) {
    final paint = Paint()..color = r.hair;
    switch (r.hairStyle) {
      case HairStyle.long:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset(w * 0.5, h * 0.47),
                width: w * 0.50,
                height: h * 0.62),
            Radius.circular(w * 0.20),
          ),
          paint,
        );
        for (final x in [0.24, 0.76]) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(
                  center: Offset(w * x, h * 0.56),
                  width: w * 0.13,
                  height: h * 0.40),
              Radius.circular(w * 0.07),
            ),
            paint,
          );
        }
        break;
      case HairStyle.bob:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset(w * 0.5, h * 0.40),
                width: w * 0.46,
                height: h * 0.44),
            Radius.circular(w * 0.16),
          ),
          paint,
        );
        break;
      case HairStyle.wavy:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset(w * 0.5, h * 0.42),
                width: w * 0.48,
                height: h * 0.46),
            Radius.circular(w * 0.18),
          ),
          paint,
        );
        for (final p in [
          Offset(w * 0.24, h * 0.58),
          Offset(w * 0.76, h * 0.58),
        ]) {
          canvas.drawCircle(p, w * 0.10, paint);
        }
        break;
      case HairStyle.curly:
        // 蓬松的卷发：一大团打底，两侧和底部再点几颗，像发量很多。
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset(w * 0.5, h * 0.38),
                width: w * 0.52,
                height: h * 0.48),
            Radius.circular(w * 0.20),
          ),
          paint,
        );
        for (final p in [
          Offset(w * 0.27, h * 0.50),
          Offset(w * 0.73, h * 0.50),
          Offset(w * 0.30, h * 0.62),
          Offset(w * 0.70, h * 0.62),
        ]) {
          canvas.drawCircle(p, w * 0.085, paint);
        }
        break;
      case HairStyle.short:
      case HairStyle.buzz:
        break;
    }
  }

  void _paintFrontHair(Canvas canvas, double w, double h, Rect head) {
    final paint = Paint()..color = r.hair;
    // 「兜帽」：从左边太阳穴兜过整个头顶到右边太阳穴，内缘让出脸的开口。
    // 长发 / 波波头 / 大波浪 / 短发共用这条外形，只是内缘高度不同 ——
    // 比一条横在额头上的刘海干净，也不会在头顶留一条肤色缝。
    Path hood(double inner, double sweep) => Path()
      ..moveTo(w * 0.315, h * 0.385)
      ..quadraticBezierTo(w * 0.285, h * 0.095, w * 0.50, h * 0.092)
      ..quadraticBezierTo(w * 0.715, h * 0.095, w * 0.685, h * 0.385)
      ..quadraticBezierTo(w * (0.60 + sweep), h * inner, w * 0.50, h * (inner + 0.005))
      ..quadraticBezierTo(w * (0.40 - sweep), h * inner, w * 0.315, h * 0.385)
      ..close();

    switch (r.hairStyle) {
      case HairStyle.long:
        canvas.drawPath(hood(0.255, 0.02), paint);
        break;
      case HairStyle.bob:
        canvas.drawPath(hood(0.285, 0.0), paint);
        break;
      case HairStyle.wavy:
        canvas.drawPath(hood(0.265, 0.04), paint);
        break;
      case HairStyle.curly:
        canvas.drawPath(hood(0.30, 0.0), paint);
        for (var i = 0; i < 4; i++) {
          canvas.drawCircle(
            Offset(w * (0.36 + 0.093 * i), h * 0.245),
            w * 0.058,
            paint,
          );
        }
        break;
      case HairStyle.short:
        canvas.drawPath(hood(0.30, 0.0), paint);
        break;
      case HairStyle.buzz:
        canvas.save();
        canvas.clipPath(Path()..addOval(head.inflate(1)));
        canvas.drawRect(
          Rect.fromLTRB(head.left, head.top, head.right, head.top + head.height * 0.30),
          paint,
        );
        canvas.restore();
        break;
    }
  }

  /// 极简五官：两条短眉、两点眼睛、一点唇色。
  ///
  /// 画得太细会脏、太满会土，所以只给三个「够看」的信号，整体仍是插画。
  void _paintFace(Canvas canvas, double w, double h) {
    final ink = Paint()..color = const Color(0xFF3A2A22);
    final brow = Paint()
      ..color = const Color(0xFF4A382E)
      ..strokeWidth = w * 0.012
      ..strokeCap = StrokeCap.round;

    // 眉
    canvas.drawLine(
        Offset(w * 0.415, h * 0.335), Offset(w * 0.465, h * 0.330), brow);
    canvas.drawLine(
        Offset(w * 0.535, h * 0.330), Offset(w * 0.585, h * 0.335), brow);
    // 眼
    for (final x in [0.442, 0.558]) {
      canvas.drawOval(
        Rect.fromCenter(
            center: Offset(w * x, h * 0.365),
            width: w * 0.030,
            height: h * 0.018),
        ink,
      );
    }
    // 唇
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(w * 0.5, h * 0.455),
          width: w * 0.045,
          height: h * 0.014),
      Paint()..color = const Color(0xFFB76A5E).withValues(alpha: 0.75),
    );
  }

  Color _shade(Color c, double factor) {
    final hsl = HSLColor.fromColor(c);
    return hsl.withLightness((hsl.lightness * factor).clamp(0.0, 1.0)).toColor();
  }

  @override
  bool shouldRepaint(_PortraitPainter old) => old.r.id != r.id;
}
