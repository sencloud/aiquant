import 'package:flutter/material.dart';

import '../market_theme.dart';

class AiMascotButton extends StatelessWidget {
  const AiMascotButton({
    super.key,
    required this.onPressed,
    this.size = 34,
  });

  final VoidCallback? onPressed;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '问问喜AI',
      child: Semantics(
        button: true,
        label: '问问喜AI',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(10),
            child: Ink(
              width: size,
              height: size,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF2962FF), Color(0xFF6D8DFF)],
                ),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.72),
                ),
              ),
              child: const CustomPaint(
                painter: _AiMascotPainter(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AiMascotAvatar extends StatelessWidget {
  const AiMascotAvatar({super.key, this.size = 38});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: MarketColors.accentSoft,
        shape: BoxShape.circle,
        border: Border.all(
          color: MarketColors.accent.withValues(alpha: 0.24),
        ),
      ),
      child: const CustomPaint(
        painter: _AiMascotPainter(showTile: false),
      ),
    );
  }
}

class _AiMascotPainter extends CustomPainter {
  const _AiMascotPainter({this.showTile = true});

  final bool showTile;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 34;
    canvas.save();
    canvas.scale(scale);
    canvas.translate((34 - 34) / 2, (34 - 34) / 2);

    final white = Paint()..color = Colors.white;
    final ink = Paint()
      ..color = const Color(0xFF1746D1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round;
    final spark = Paint()..color = const Color(0xFFFFCF4A);

    // 小天线和侧边耳机。
    canvas.drawLine(const Offset(15, 10), const Offset(13, 6), ink);
    canvas.drawCircle(const Offset(12.5, 5.2), 1.8, spark);
    canvas.drawLine(const Offset(23, 14), const Offset(27, 16), ink);
    canvas.drawCircle(const Offset(28, 16.2), 2.1, spark);

    // 圆角机器人脸。
    final face = RRect.fromRectAndRadius(
      const Rect.fromLTWH(7, 8, 20, 18),
      const Radius.circular(8),
    );
    canvas.drawRRect(face, white);
    canvas.drawRRect(face, ink);

    // 眼睛与微笑。
    canvas.drawCircle(
        const Offset(13.5, 16), 1.35, Paint()..color = MarketColors.accent);
    canvas.drawCircle(
        const Offset(20.5, 16), 1.35, Paint()..color = MarketColors.accent);
    final smile = Path()
      ..moveTo(14, 20)
      ..quadraticBezierTo(17, 22.3, 20, 20);
    canvas.drawPath(smile, ink);

    // 数据小点，让图标更像行情助手而不是普通表情。
    canvas.drawCircle(const Offset(11.2, 24.2), 1.1, spark);
    canvas.drawCircle(const Offset(16.2, 24.8), 1.1, spark);
    canvas.drawCircle(const Offset(21.2, 24.2), 1.1, spark);

    if (showTile) {
      final glint = Paint()
        ..color = Colors.white.withValues(alpha: 0.5)
        ..strokeWidth = 1
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(const Offset(27, 23), const Offset(29, 23), glint);
      canvas.drawLine(const Offset(28, 22), const Offset(28, 24), glint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _AiMascotPainter old) =>
      old.showTile != showTile;
}
