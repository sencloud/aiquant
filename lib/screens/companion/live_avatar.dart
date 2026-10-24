import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/companion_look.dart';
import '../../models/companion_mood.dart';
import '../../theme/app_theme.dart';

/// 「会呼吸的她」。
///
/// 没有 Live2D，也不假装有：在一张二次元立绘上做三件真实且便宜的事 ——
/// 呼吸（缩放 + 上下浮动）、随机眨眼（眼睑遮罩）、情绪（倾角 / 光晕 / 小标）。
/// 所有动作都能被「减少动态效果」关掉。
class LiveAvatar extends StatefulWidget {
  const LiveAvatar({
    super.key,
    required this.look,
    this.mood = AvatarMood.calm,
    this.width = 88,
    this.height = 88,
    this.radius = 20,
    this.glow = true,
    this.onTap,
  });

  final CompanionLook look;
  final AvatarMood mood;
  final double width;
  final double height;
  final double radius;
  final bool glow;
  final VoidCallback? onTap;

  @override
  State<LiveAvatar> createState() => _LiveAvatarState();
}

class _LiveAvatarState extends State<LiveAvatar>
    with TickerProviderStateMixin {
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4200),
  )..repeat(reverse: true);

  late final AnimationController _reaction = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  );

  bool _blink = false;
  Timer? _nextBlink;
  Timer? _blinkOff;

  @override
  void initState() {
    super.initState();
    _scheduleBlink();
  }

  void _scheduleBlink() {
    final wait = 2600 + math.Random().nextInt(3200);
    _nextBlink = Timer(Duration(milliseconds: wait), () {
      if (!mounted) return;
      setState(() => _blink = true);
      _blinkOff = Timer(const Duration(milliseconds: 95), () {
        if (!mounted) return;
        setState(() => _blink = false);
        _scheduleBlink();
      });
    });
  }

  @override
  void didUpdateWidget(covariant LiveAvatar old) {
    super.didUpdateWidget(old);
    if (old.mood != widget.mood) {
      _reaction.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _nextBlink?.cancel();
    _blinkOff?.cancel();
    _breath.dispose();
    _reaction.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final mood = widget.mood;
    final tilt = switch (mood) {
      AvatarMood.happy => -0.015,
      AvatarMood.shy => 0.03,
      AvatarMood.thinking => -0.02,
      AvatarMood.listening => 0.0,
      AvatarMood.sad => 0.02,
      _ => 0.0,
    };
    final aura = switch (mood) {
      AvatarMood.happy => const Color(0xFFE8A35C),
      AvatarMood.shy => const Color(0xFFD98A9A),
      AvatarMood.thinking => const Color(0xFF7C8FB5),
      AvatarMood.listening => const Color(0xFF9E6322),
      AvatarMood.sad => const Color(0xFF6F7A88),
      _ => const Color(0xFF9E6322),
    };

    final avatar = AnimatedBuilder(
      animation: Listenable.merge([_breath, _reaction]),
      builder: (context, child) {
        final b = reduce ? 0.5 : _breath.value;
        final scale = 1 + 0.012 * math.sin((b - 0.5) * math.pi);
        final dy = -1.6 * math.sin((b - 0.5) * math.pi);
        final pop = 1 + 0.03 * math.sin(_reaction.value * math.pi);
        return Transform.translate(
          offset: Offset(0, dy),
          child: Transform.rotate(
            angle: tilt,
            child: Transform.scale(
              scale: scale * pop,
              child: child,
            ),
          ),
        );
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            widget.look.asset,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) =>
                ColoredBox(color: AppColors.accentSoft),
          ),
          IgnorePointer(
            child: AnimatedOpacity(
              opacity: _blink ? 1 : 0,
              duration: const Duration(milliseconds: 70),
              child: const _Eyelids(),
            ),
          ),
          if (mood == AvatarMood.thinking)
            const Positioned(
              right: 8,
              top: 8,
              child: _ThinkingDots(),
            ),
          if (mood == AvatarMood.happy || mood == AvatarMood.shy)
            Positioned(
              right: 6,
              top: 6,
              child: Icon(
                mood == AvatarMood.happy
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                size: 14,
                color: Colors.white.withValues(alpha: 0.92),
              ),
            ),
        ],
      ),
    );

    final content = ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: avatar,
      ),
    );

    return GestureDetector(
      onTap: widget.onTap,
      child: widget.glow
          ? Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(widget.radius + 6),
                gradient: RadialGradient(
                  colors: [
                    aura.withValues(alpha: 0.22),
                    aura.withValues(alpha: 0),
                  ],
                ),
              ),
              padding: const EdgeInsets.all(6),
              child: content,
            )
          : content,
    );
  }
}

/// 两个眼睑：比真实眼睛略高一点，闭上时像一条弧线。位置按立绘的构图取。
class _Eyelids extends StatelessWidget {
  const _Eyelids();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      final h = box.maxHeight;
      Widget lid(double cx) => Positioned(
            left: w * cx - w * 0.055,
            top: h * 0.335,
            child: Container(
              width: w * 0.11,
              height: h * 0.028,
              decoration: BoxDecoration(
                color: const Color(0xFFF1D2B8),
                borderRadius: BorderRadius.circular(h * 0.02),
                border: Border(
                  bottom: BorderSide(
                    color: const Color(0xFF5A3B2E).withValues(alpha: 0.75),
                    width: math.max(0.8, h * 0.006),
                  ),
                ),
              ),
            ),
          );
      return Stack(children: [lid(0.425), lid(0.575)]);
    });
  }
}

class _ThinkingDots extends StatefulWidget {
  const _ThinkingDots();

  @override
  State<_ThinkingDots> createState() => _ThinkingDotsState();
}

class _ThinkingDotsState extends State<_ThinkingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final n = (_c.value * 3).floor() % 3;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.28),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '·' * (n + 1),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              height: 1.0,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      },
    );
  }
}
