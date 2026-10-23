import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'night_theme.dart';

/// 夜空底：一条渐变、几颗固定的星、几道雨。没有随机数，走查截图稳定。
class NightBackdrop extends StatelessWidget {
  const NightBackdrop({super.key, this.rain = true, this.stars = true});

  final bool rain;
  final bool stars;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _NightSkyPainter(rain: rain, stars: stars),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _NightSkyPainter extends CustomPainter {
  const _NightSkyPainter({required this.rain, required this.stars});

  final bool rain;
  final bool stars;

  static const _stars = <Offset>[
    Offset(0.08, 0.12),
    Offset(0.17, 0.28),
    Offset(0.26, 0.08),
    Offset(0.38, 0.19),
    Offset(0.47, 0.06),
    Offset(0.58, 0.24),
    Offset(0.66, 0.11),
    Offset(0.76, 0.31),
    Offset(0.84, 0.07),
    Offset(0.92, 0.22),
    Offset(0.13, 0.44),
    Offset(0.71, 0.46),
  ];

  static const _rain = <Offset>[
    Offset(0.10, 0.30),
    Offset(0.22, 0.62),
    Offset(0.34, 0.38),
    Offset(0.46, 0.72),
    Offset(0.59, 0.44),
    Offset(0.72, 0.66),
    Offset(0.86, 0.36),
    Offset(0.94, 0.58),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF080A10),
            Color(0xFF0E1118),
            Color(0xFF151B27),
            Color(0xFF1E2638),
          ],
          stops: [0, 0.42, 0.76, 1],
        ).createShader(rect),
    );

    if (stars) {
      for (var i = 0; i < _stars.length; i++) {
        final p = _stars[i];
        final r = i % 4 == 0 ? 1.4 : 1.0;
        canvas.drawRect(
          Rect.fromCenter(
            center: Offset(p.dx * size.width, p.dy * size.height),
            width: r,
            height: r,
          ),
          Paint()
            ..color = Colors.white.withValues(alpha: i % 3 == 0 ? 0.38 : 0.2),
        );
      }
    }

    if (rain) {
      final paint = Paint()
        ..color = NightColors.rain.withValues(alpha: 0.10)
        ..strokeWidth = 1;
      for (final p in _rain) {
        final x = p.dx * size.width;
        final y = p.dy * size.height;
        canvas.drawLine(
          Offset(x, y),
          Offset(x - size.width * 0.018, y + size.height * 0.075),
          paint,
        );
      }
    }

    // 地平线的一条暖光，像城市在下面呼吸。
    final horizon = size.height * 0.82;
    canvas.drawRect(
      Rect.fromLTWH(0, horizon, size.width, 1),
      Paint()..color = NightColors.amber.withValues(alpha: 0.12),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, horizon + 1, size.width, size.height - horizon),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            NightColors.amber.withValues(alpha: 0.06),
            Colors.transparent,
          ],
        ).createShader(
            Rect.fromLTWH(0, horizon, size.width, size.height - horizon)),
    );
  }

  @override
  bool shouldRepaint(_NightSkyPainter old) =>
      old.rain != rain || old.stars != stars;
}

/// 顶部栏：左边返回，中间标题 + 一行小字，右边动作。
class NightBar extends StatelessWidget {
  const NightBar({
    super.key,
    required this.title,
    this.subtitle,
    this.onBack,
    this.actions = const [],
  });

  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Container(
        height: 54,
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: NightColors.borderSoft, width: 1),
          ),
        ),
        child: Stack(
          children: [
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 58),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: NightType.title),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: NightType.micro),
                    ],
                  ],
                ),
              ),
            ),
            if (onBack != null)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 48,
                child: IconButton(
                  onPressed: onBack,
                  padding: EdgeInsets.zero,
                  splashRadius: 20,
                  icon: const Icon(Icons.arrow_back_ios_new_rounded,
                      size: 18, color: NightColors.paper),
                ),
              ),
            if (actions.isNotEmpty)
              Positioned(
                right: 8,
                top: 0,
                bottom: 0,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: actions,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class PixelButton extends StatelessWidget {
  const PixelButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.filled = true,
    this.height = 48,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool filled;
  final double height;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final fg = filled
        ? NightColors.ink
        : (enabled ? NightColors.paper : NightColors.faint);
    final bg = filled
        ? (enabled ? NightColors.amber : NightColors.surfaceRaised)
        : Colors.transparent;
    return SizedBox(
      height: height,
      width: double.infinity,
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: BorderSide(
            color: filled
                ? Colors.transparent
                : (enabled ? NightColors.border : NightColors.borderSoft),
          ),
        ),
        child: InkWell(
          onTap: onPressed,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 17, color: fg),
                const SizedBox(width: 7),
              ],
              Text(
                label,
                style: NightType.title.copyWith(
                  color: fg,
                  fontSize: 14,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PixelTag extends StatelessWidget {
  const PixelTag(
    this.text, {
    super.key,
    this.color = NightColors.muted,
  });

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Text(
        text,
        style: NightType.micro.copyWith(color: color, letterSpacing: 0.8),
      ),
    );
  }
}

class HeartRow extends StatelessWidget {
  const HeartRow({
    super.key,
    required this.hearts,
    this.max = 5,
    this.size = 15,
    this.semanticLabel = '心级',
  });

  final int hearts;
  final int max;
  final double size;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$semanticLabel $hearts / $max',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < max; i++)
            Padding(
              padding: const EdgeInsets.only(right: 2),
              child: Icon(
                i < hearts
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                size: size,
                color: i < hearts ? NightColors.heart : NightColors.border,
              ),
            ),
        ],
      ),
    );
  }
}

class PixelPanel extends StatelessWidget {
  const PixelPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.color = NightColors.surface,
    this.borderColor = NightColors.border,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: borderColor, width: 1),
      ),
      child: child,
    );
  }
}

class NightNote extends StatelessWidget {
  const NightNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: const BoxDecoration(
        border: Border(
          left: BorderSide(color: NightColors.amberDim, width: 2),
          top: BorderSide(color: NightColors.borderSoft),
          right: BorderSide(color: NightColors.borderSoft),
          bottom: BorderSide(color: NightColors.borderSoft),
        ),
        color: NightColors.surface,
      ),
      child: Text(text, style: NightType.caption.copyWith(height: 1.65)),
    );
  }
}

class NightBottomNav extends StatelessWidget {
  const NightBottomNav({
    super.key,
    required this.index,
    required this.onSelect,
  });

  final int index;
  final ValueChanged<int> onSelect;

  static const _items = <(String, IconData)>[
    ('通讯录', Icons.contacts_rounded),
    ('动态', Icons.auto_awesome_mosaic_rounded),
    ('我', Icons.person_outline_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: NightColors.bg,
        border: Border(top: BorderSide(color: NightColors.borderSoft)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 58,
          child: Row(
            children: [
              for (var i = 0; i < _items.length; i++)
                Expanded(
                  child: InkWell(
                    onTap: () => onSelect(i),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _items[i].$2,
                          size: 21,
                          color: index == i
                              ? NightColors.amber
                              : NightColors.faint,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _items[i].$1,
                          style: NightType.micro.copyWith(
                            color: index == i
                                ? NightColors.amber
                                : NightColors.faint,
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Container(
                          width: 18,
                          height: 1,
                          color: index == i
                              ? NightColors.amber
                              : Colors.transparent,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class TypingIndicator extends StatefulWidget {
  const TypingIndicator({super.key});

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctl,
      builder: (context, _) {
        final n = 1 + (_ctl.value * 3).floor().clamp(0, 2);
        return Text(
          '${'·' * n}${' ' * (3 - n)}',
          style: NightType.mono.copyWith(
            color: NightColors.amber,
            letterSpacing: 3,
          ),
        );
      },
    );
  }
}

/// 简单的「心级变化」句式：不显示数字，只显示方向。
String heartDeltaLabel(int before, int after) {
  final d = after - before;
  if (d > 0) return 'TA 靠近了一点';
  if (d < 0) return 'TA 退后了一点';
  return '今晚停在这里';
}

/// 用一条细线画一个小四芒星，给「未接来电」和空状态用。
class NightSpark extends StatelessWidget {
  const NightSpark({super.key, this.size = 12, this.color = NightColors.amber});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _SparkPainter(color),
    );
  }
}

class _SparkPainter extends CustomPainter {
  const _SparkPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(c.dx, 0), Offset(c.dx, size.height), paint);
    canvas.drawLine(Offset(0, c.dy), Offset(size.width, c.dy), paint);
    final d = r * math.sqrt1_2;
    canvas.drawLine(
        Offset(c.dx - d, c.dy - d), Offset(c.dx + d, c.dy + d), paint);
    canvas.drawLine(
        Offset(c.dx + d, c.dy - d), Offset(c.dx - d, c.dy + d), paint);
  }

  @override
  bool shouldRepaint(_SparkPainter old) => old.color != color;
}
