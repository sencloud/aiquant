import 'package:flutter/material.dart';

import '../market_theme.dart';

class MarketBrandMark extends StatelessWidget {
  const MarketBrandMark({super.key, this.size = 34});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0A1938), Color(0xFF1C49C9)],
        ),
        borderRadius: BorderRadius.circular(size * 0.28),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.26),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0A1938).withValues(alpha: 0.2),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: const CustomPaint(
        painter: _MarketBrandPainter(),
      ),
    );
  }
}

class MarketBrandLockup extends StatelessWidget {
  const MarketBrandLockup({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final markSize = compact ? 32.0 : 38.0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        MarketBrandMark(size: markSize),
        SizedBox(width: compact ? 9 : 11),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '喜',
                    style: TextStyle(
                      color: MarketColors.textPrimary,
                      fontSize: compact ? 16 : 18,
                      height: 1.05,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
                  TextSpan(
                    text: 'AI',
                    style: TextStyle(
                      color: MarketColors.accent,
                      fontSize: compact ? 16 : 18,
                      height: 1.05,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 3),
            Text(
              '行情 · 智能研判',
              style: TextStyle(
                color: MarketColors.textMuted,
                fontSize: compact ? 8.5 : 9.5,
                height: 1,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _MarketBrandPainter extends CustomPainter {
  const _MarketBrandPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // 右上角的微光让深色底不显得沉重。
    canvas.drawCircle(
      Offset(w * 0.78, h * 0.2),
      w * 0.28,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0x6677A2FF), Color(0x0077A2FF)],
        ).createShader(
          Rect.fromCircle(
            center: Offset(w * 0.78, h * 0.2),
            radius: w * 0.28,
          ),
        ),
    );

    // 抽象“A”：既是 AI，也像持续抬升的价格轨迹。
    final a = Path()
      ..moveTo(w * 0.23, h * 0.77)
      ..lineTo(w * 0.46, h * 0.24)
      ..quadraticBezierTo(w * 0.5, h * 0.16, w * 0.54, h * 0.24)
      ..lineTo(w * 0.77, h * 0.77)
      ..lineTo(w * 0.63, h * 0.77)
      ..lineTo(w * 0.56, h * 0.59)
      ..lineTo(w * 0.44, h * 0.59)
      ..lineTo(w * 0.37, h * 0.77)
      ..close();
    canvas.drawPath(a, Paint()..color = Colors.white.withValues(alpha: 0.97));

    // 金色横梁与右侧上扬节点，形成金融品牌识别。
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.39, h * 0.57, w * 0.22, h * 0.055),
        Radius.circular(w * 0.03),
      ),
      Paint()..color = const Color(0xFFE0B25C),
    );
    final trail = Path()
      ..moveTo(w * 0.66, h * 0.34)
      ..lineTo(w * 0.72, h * 0.29)
      ..lineTo(w * 0.78, h * 0.32);
    canvas.drawPath(
      trail,
      Paint()
        ..color = const Color(0xFFE0B25C)
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.035
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawCircle(
      Offset(w * 0.78, h * 0.32),
      w * 0.04,
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant _MarketBrandPainter oldDelegate) => false;
}
