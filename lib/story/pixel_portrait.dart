import 'package:flutter/material.dart';

import 'night_theme.dart';
import 'story_models.dart';

/// 六位居民的二次元像素立绘。
///
/// 这是「美术终稿」之前的可运行版本：全部由代码画，不读写真、不读 AI 图，
/// 所以不会出现「主角二次元、配角写实」的混搭。等像素美术的三视图到位后，
/// 只需要把这个 painter 换成 `Image.asset`，页面不用动。
class PixelPortrait extends StatelessWidget {
  const PixelPortrait({
    super.key,
    required this.character,
    this.expression = PixelExpression.calm,
    this.scanlines = true,
  });

  final StoryCharacter character;
  final PixelExpression expression;
  final bool scanlines;

  @override
  Widget build(BuildContext context) {
    final asset = character.artAssetFor(expression);
    if (asset == null) {
      return RepaintBoundary(child: _painted());
    }
    return RepaintBoundary(
      child: Image.asset(
        asset,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.none,
        errorBuilder: (_, __, ___) => _painted(),
      ),
    );
  }

  Widget _painted() {
    return CustomPaint(
      painter: _PixelPortraitPainter(
        character: character,
        expression: expression,
        scanlines: scanlines,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class PixelAvatar extends StatelessWidget {
  const PixelAvatar({
    super.key,
    required this.character,
    this.size = 56,
    this.expression,
    this.radius = 2,
  });

  final StoryCharacter character;
  final double size;
  final PixelExpression? expression;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: FittedBox(
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: 64,
            height: 88,
            child: PixelPortrait(
              character: character,
              expression: expression ?? character.expressions.first,
              scanlines: false,
            ),
          ),
        ),
      ),
    );
  }
}

class _PixelPortraitPainter extends CustomPainter {
  const _PixelPortraitPainter({
    required this.character,
    required this.expression,
    required this.scanlines,
  });

  final StoryCharacter character;
  final PixelExpression expression;
  final bool scanlines;

  static const _ink = Color(0xFF1C1617);
  static const _white = Color(0xFFF8F1E7);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 64, size.height / 88);

    _background(canvas);
    _hairBack(canvas);
    _body(canvas);
    _neck(canvas);
    _head(canvas);
    _hairFront(canvas);
    _ears(canvas);
    _brows(canvas);
    _eyes(canvas);
    _noseMouth(canvas);
    _accessory(canvas);
    _rimLight(canvas);
    if (scanlines) _scanlines(canvas);

    canvas.restore();
  }

  void _background(Canvas canvas) {
    const rect = Rect.fromLTWH(0, 0, 64, 88);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [character.bgA, character.bgB],
        ).createShader(rect),
    );

    final glow = Rect.fromCircle(center: const Offset(46, 18), radius: 28);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white.withValues(alpha: 0.16),
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(glow),
    );

    // 几颗固定的星屑，和夜空底同一套语言。
    for (final p in const [
      Offset(8, 10),
      Offset(52, 14),
      Offset(12, 34),
      Offset(58, 42),
      Offset(7, 58),
    ]) {
      _rect(canvas, p.dx, p.dy, 1, 1, Colors.white.withValues(alpha: 0.18));
    }

    _rect(canvas, 0, 70, 64, 18, Colors.black.withValues(alpha: 0.18));
  }

  void _hairBack(Canvas canvas) {
    final dark = _shade(character.hair, 0.68);
    final mid = character.hair;
    final light = Color.lerp(character.hair, Colors.white, 0.16)!;

    switch (character.hairStyle) {
      case PixelHairStyle.long:
        _poly(
            canvas,
            const [
              Offset(14, 14),
              Offset(50, 14),
              Offset(55, 30),
              Offset(55, 86),
              Offset(9, 86),
              Offset(9, 30),
            ],
            dark);
        _poly(
            canvas,
            const [
              Offset(18, 18),
              Offset(46, 18),
              Offset(50, 32),
              Offset(50, 80),
              Offset(14, 80),
              Offset(14, 32),
            ],
            mid);
        _rect(canvas, 11, 38, 7, 44, mid);
        _rect(canvas, 46, 38, 7, 44, mid);
        _rect(canvas, 16, 24, 3, 34, light.withValues(alpha: 0.55));
        _rect(canvas, 46, 30, 2, 30, light.withValues(alpha: 0.5));
        break;
      case PixelHairStyle.bob:
        _poly(
            canvas,
            const [
              Offset(14, 14),
              Offset(50, 14),
              Offset(54, 26),
              Offset(54, 56),
              Offset(10, 56),
              Offset(10, 26),
            ],
            dark);
        _poly(
            canvas,
            const [
              Offset(18, 18),
              Offset(46, 18),
              Offset(49, 30),
              Offset(49, 50),
              Offset(15, 50),
              Offset(15, 30),
            ],
            mid);
        _rect(canvas, 12, 32, 6, 22, mid);
        _rect(canvas, 46, 32, 6, 22, mid);
        _rect(canvas, 17, 22, 2, 18, light.withValues(alpha: 0.5));
        break;
      case PixelHairStyle.curly:
        _poly(
            canvas,
            const [
              Offset(12, 16),
              Offset(52, 16),
              Offset(56, 30),
              Offset(54, 64),
              Offset(10, 64),
              Offset(8, 30),
            ],
            dark);
        _poly(
            canvas,
            const [
              Offset(16, 20),
              Offset(48, 20),
              Offset(51, 32),
              Offset(49, 56),
              Offset(15, 56),
              Offset(13, 32),
            ],
            mid);
        for (final p in const [
          Offset(9, 24),
          Offset(48, 24),
          Offset(8, 36),
          Offset(50, 36),
          Offset(11, 48),
          Offset(47, 48),
          Offset(14, 58),
          Offset(42, 58),
        ]) {
          _rect(canvas, p.dx, p.dy, 7, 8, mid);
        }
        _rect(canvas, 18, 24, 2, 16, light.withValues(alpha: 0.55));
        break;
      case PixelHairStyle.short:
        _poly(
            canvas,
            const [
              Offset(15, 14),
              Offset(49, 14),
              Offset(52, 24),
              Offset(51, 42),
              Offset(13, 42),
              Offset(12, 24),
            ],
            dark);
        _poly(
            canvas,
            const [
              Offset(18, 18),
              Offset(46, 18),
              Offset(48, 26),
              Offset(47, 38),
              Offset(17, 38),
              Offset(16, 26),
            ],
            mid);
        _rect(canvas, 14, 24, 3, 18, mid);
        _rect(canvas, 47, 24, 3, 18, mid);
        break;
      case PixelHairStyle.buzz:
        _poly(
            canvas,
            const [
              Offset(18, 15),
              Offset(46, 15),
              Offset(48, 22),
              Offset(47, 30),
              Offset(17, 30),
              Offset(16, 22),
            ],
            dark);
        _rect(canvas, 20, 17, 24, 5, mid);
        _rect(canvas, 18, 22, 2, 7, mid);
        _rect(canvas, 44, 22, 2, 7, mid);
        break;
      case PixelHairStyle.wavy:
        _poly(
            canvas,
            const [
              Offset(14, 14),
              Offset(50, 14),
              Offset(54, 22),
              Offset(52, 30),
              Offset(56, 38),
              Offset(53, 48),
              Offset(56, 58),
              Offset(52, 70),
              Offset(55, 86),
              Offset(9, 86),
              Offset(12, 70),
              Offset(8, 58),
              Offset(11, 48),
              Offset(8, 38),
              Offset(12, 30),
              Offset(10, 22),
            ],
            dark);
        _poly(
            canvas,
            const [
              Offset(18, 18),
              Offset(46, 18),
              Offset(49, 28),
              Offset(47, 36),
              Offset(51, 44),
              Offset(48, 54),
              Offset(51, 64),
              Offset(46, 76),
              Offset(18, 76),
              Offset(13, 64),
              Offset(16, 54),
              Offset(13, 44),
              Offset(17, 36),
              Offset(15, 28),
            ],
            mid);
        _rect(canvas, 15, 28, 3, 30, light.withValues(alpha: 0.5));
        _rect(canvas, 47, 34, 2, 26, light.withValues(alpha: 0.45));
        break;
    }
  }

  void _body(Canvas canvas) {
    final shade = _shade(character.jacket, 0.72);
    final light = Color.lerp(character.jacket, Colors.white, 0.18)!;

    _poly(
        canvas,
        const [
          Offset(7, 88),
          Offset(9, 70),
          Offset(18, 62),
          Offset(28, 59),
          Offset(36, 59),
          Offset(46, 62),
          Offset(55, 70),
          Offset(57, 88),
        ],
        character.jacket);

    // 内搭 / 衬衫
    _poly(
        canvas,
        const [
          Offset(27, 62),
          Offset(37, 62),
          Offset(40, 88),
          Offset(24, 88),
        ],
        const Color(0xFFF2E6D7));

    // 领口
    _poly(
        canvas,
        const [
          Offset(27, 62),
          Offset(32, 62),
          Offset(31, 70),
          Offset(26, 68),
        ],
        shade);
    _poly(
        canvas,
        const [
          Offset(32, 62),
          Offset(37, 62),
          Offset(38, 68),
          Offset(33, 70),
        ],
        shade);

    // 衣褶
    _rect(canvas, 19, 70, 3, 16, light.withValues(alpha: 0.35));
    _rect(canvas, 43, 72, 2, 14, shade.withValues(alpha: 0.55));
  }

  void _neck(Canvas canvas) {
    _rect(canvas, 28, 46, 8, 11, _shade(character.skin, 0.88));
    _rect(canvas, 28, 46, 8, 2, _shade(character.skin, 0.78));
  }

  void _head(Canvas canvas) {
    final skin = character.skin;
    _poly(
        canvas,
        const [
          Offset(23, 14),
          Offset(41, 14),
          Offset(45, 18),
          Offset(46, 26),
          Offset(45, 34),
          Offset(43, 40),
          Offset(39, 45),
          Offset(32, 47),
          Offset(25, 45),
          Offset(21, 40),
          Offset(19, 34),
          Offset(18, 26),
          Offset(19, 18),
        ],
        skin);

    _rect(canvas, 17, 32, 3, 7, _shade(skin, 0.88));
    _rect(canvas, 44, 32, 3, 7, _shade(skin, 0.88));
    _rect(canvas, 18, 33, 1, 5, _shade(skin, 0.75));
    _rect(canvas, 45, 33, 1, 5, _shade(skin, 0.75));

    // 下巴只留一条很轻的高光，不做「胡子」式的整块阴影。
    _rect(canvas, 29, 38, 6, 1, Colors.white.withValues(alpha: 0.10));

    // 额头高光
    _rect(canvas, 29, 19, 7, 2, Colors.white.withValues(alpha: 0.12));
  }

  void _hairFront(Canvas canvas) {
    final mid = character.hair;
    final dark = _shade(character.hair, 0.72);

    switch (character.hairStyle) {
      case PixelHairStyle.long:
        _poly(
            canvas,
            const [
              Offset(18, 14),
              Offset(46, 14),
              Offset(46, 24),
              Offset(43, 27),
              Offset(39, 24),
              Offset(35, 27),
              Offset(31, 24),
              Offset(27, 27),
              Offset(23, 24),
              Offset(20, 27),
              Offset(18, 24),
            ],
            mid);
        _poly(
            canvas,
            const [
              Offset(18, 14),
              Offset(30, 14),
              Offset(28, 26),
              Offset(24, 25),
              Offset(20, 21),
            ],
            _shade(mid, 0.92));
        _rect(canvas, 19, 24, 3, 18, mid);
        _rect(canvas, 44, 24, 2, 12, mid);
        _rect(canvas, 23, 17, 4, 2, Color.lerp(mid, Colors.white, 0.2)!);
        break;
      case PixelHairStyle.bob:
        _poly(
            canvas,
            const [
              Offset(18, 16),
              Offset(46, 16),
              Offset(46, 26),
              Offset(40, 28),
              Offset(38, 22),
              Offset(31, 25),
              Offset(26, 22),
              Offset(24, 28),
              Offset(18, 26),
            ],
            mid);
        _rect(canvas, 19, 24, 3, 8, mid);
        _rect(canvas, 43, 24, 3, 8, mid);
        _rect(canvas, 24, 18, 5, 2, Color.lerp(mid, Colors.white, 0.18)!);
        break;
      case PixelHairStyle.curly:
        for (final p in const [
          Offset(18, 15),
          Offset(28, 14),
          Offset(38, 15),
          Offset(24, 20),
          Offset(34, 20),
        ]) {
          _rect(canvas, p.dx, p.dy, 9, 8, mid);
        }
        _rect(canvas, 18, 23, 4, 6, mid);
        _rect(canvas, 43, 23, 4, 6, mid);
        _rect(canvas, 25, 16, 4, 2, Color.lerp(mid, Colors.white, 0.22)!);
        break;
      case PixelHairStyle.short:
        _poly(
            canvas,
            const [
              Offset(18, 16),
              Offset(46, 16),
              Offset(45, 25),
              Offset(39, 23),
              Offset(36, 28),
              Offset(29, 23),
              Offset(24, 28),
              Offset(19, 25),
            ],
            mid);
        _rect(canvas, 18, 24, 3, 9, mid);
        _rect(canvas, 44, 24, 3, 9, mid);
        break;
      case PixelHairStyle.buzz:
        _rect(canvas, 21, 16, 22, 4, dark);
        _rect(canvas, 20, 19, 3, 3, mid);
        _rect(canvas, 42, 19, 3, 3, mid);
        break;
      case PixelHairStyle.wavy:
        _poly(
            canvas,
            const [
              Offset(18, 16),
              Offset(30, 16),
              Offset(28, 26),
              Offset(36, 18),
              Offset(46, 17),
              Offset(45, 28),
              Offset(37, 27),
              Offset(33, 30),
              Offset(23, 28),
              Offset(18, 24),
            ],
            mid);
        _rect(canvas, 45, 25, 3, 14, mid);
        _rect(canvas, 22, 18, 4, 2, Color.lerp(mid, Colors.white, 0.2)!);
        break;
    }
  }

  void _ears(Canvas canvas) {
    // 耳朵在头发前面露一点，只在短发 / 板寸时明显。
    if (character.hairStyle == PixelHairStyle.short ||
        character.hairStyle == PixelHairStyle.buzz) {
      _rect(canvas, 17, 33, 2, 6, _shade(character.skin, 0.86));
      _rect(canvas, 45, 33, 2, 6, _shade(character.skin, 0.86));
    }
  }

  void _brows(Canvas canvas) {
    final brow = _shade(character.hair, 0.62);
    switch (expression) {
      case PixelExpression.smirk:
        _rect(canvas, 22, 24, 8, 1, brow);
        _rect(canvas, 34, 23, 8, 1, brow);
        break;
      case PixelExpression.hurt:
        _rect(canvas, 22, 24, 8, 1, brow);
        _rect(canvas, 23, 25, 6, 1, brow);
        _rect(canvas, 34, 24, 8, 1, brow);
        _rect(canvas, 35, 25, 6, 1, brow);
        break;
      default:
        _rect(canvas, 22, 24, 8, 1, brow);
        _rect(canvas, 34, 24, 8, 1, brow);
    }
  }

  void _eyes(Canvas canvas) {
    const xLeft = 22.0;
    const xRight = 33.0;
    final y = expression == PixelExpression.hurt ? 30.0 : 29.0;

    if (expression == PixelExpression.smile) {
      // 弯弯的闭眼
      for (final x in [xLeft, xRight]) {
        _rect(canvas, x + 1, y + 3, 7, 1, _ink);
        _rect(canvas, x, y + 2, 1, 1, _ink);
        _rect(canvas, x + 8, y + 2, 1, 1, _ink);
      }
      return;
    }

    final h = expression == PixelExpression.soft ? 6.0 : 7.0;
    for (final x in [xLeft, xRight]) {
      _rect(canvas, x, y, 9, h, _white);
      _rect(canvas, x, y, 9, 1, _ink);
      _rect(canvas, x, y + h - 1, 9, 1, _ink.withValues(alpha: 0.55));

      var irisX = x + 2;
      if (expression == PixelExpression.away) {
        irisX = x + (x == xLeft ? 3 : 1);
      }
      _rect(canvas, irisX, y + 1, 5, h - 2, character.eye);
      _rect(canvas, irisX + 1, y + 2, 3, h - 3, _shade(character.eye, 0.6));
      _rect(canvas, irisX + 1, y + 1, 2, 2, _white);
      _rect(canvas, irisX + 4, y + h - 3, 1, 1, _white.withValues(alpha: 0.75));

      // 睫毛：外眼角一撇 + 下眼睑一条淡线
      _rect(canvas, x + (x == xLeft ? 0 : 7), y, 2, 1, _ink);
      _rect(canvas, x + 1, y + h, 7, 1, _ink.withValues(alpha: 0.30));
    }
  }

  void _noseMouth(Canvas canvas) {
    _rect(canvas, 31, 37, 1, 1, _shade(character.skin, 0.78));

    // 一点腮红：没有它，像素脸会像面具。
    _rect(canvas, 20, 37, 4, 1, NightColors.heart.withValues(alpha: 0.28));
    _rect(canvas, 41, 37, 4, 1, NightColors.heart.withValues(alpha: 0.28));

    const lip = Color(0xFFC97B70);
    switch (expression) {
      case PixelExpression.smile:
        _rect(canvas, 29, 41, 6, 1, lip);
        _rect(canvas, 28, 40, 1, 1, lip);
        _rect(canvas, 35, 40, 1, 1, lip);
        break;
      case PixelExpression.soft:
        _rect(canvas, 29, 41, 3, 1, lip);
        _rect(canvas, 32, 42, 2, 1, lip);
        break;
      case PixelExpression.hurt:
        _rect(canvas, 29, 42, 2, 1, lip);
        _rect(canvas, 33, 42, 2, 1, lip);
        _rect(canvas, 31, 41, 2, 1, lip);
        break;
      case PixelExpression.smirk:
        _rect(canvas, 29, 41, 5, 1, lip);
        _rect(canvas, 34, 40, 1, 1, lip);
        break;
      default:
        _rect(canvas, 30, 41, 4, 1, lip);
    }
  }

  void _accessory(Canvas canvas) {
    switch (character.accessory) {
      case PixelAccessory.catEars:
        // 猫耳耳机：耳朵 + 头梁 + 耳罩。
        _poly(
            canvas,
            const [
              Offset(16, 13),
              Offset(22, 7),
              Offset(24, 15),
            ],
            _shade(character.hair, 0.72));
        _poly(
            canvas,
            const [
              Offset(18, 12),
              Offset(21, 9),
              Offset(22, 14),
            ],
            character.accent.withValues(alpha: 0.65));
        _poly(
            canvas,
            const [
              Offset(40, 15),
              Offset(44, 7),
              Offset(49, 13),
            ],
            _shade(character.hair, 0.72));
        _poly(
            canvas,
            const [
              Offset(42, 14),
              Offset(44, 9),
              Offset(47, 12),
            ],
            character.accent.withValues(alpha: 0.65));
        _rect(canvas, 22, 12, 20, 2, _shade(character.hair, 0.55));
        _rect(canvas, 14, 30, 4, 8, character.accent);
        _rect(canvas, 46, 30, 4, 8, character.accent);
        _rect(canvas, 15, 32, 2, 4, _shade(character.accent, 0.7));
        _rect(canvas, 47, 32, 2, 4, _shade(character.accent, 0.7));
        break;
      case PixelAccessory.mole:
        _rect(canvas, 43, 43, 1, 1, _ink.withValues(alpha: 0.8));
        break;
      case PixelAccessory.hairClips:
        _rect(canvas, 19, 23, 5, 2, character.accent);
        _rect(canvas, 25, 20, 3, 2, NightColors.heart.withValues(alpha: 0.8));
        break;
      case PixelAccessory.watch:
        _rect(canvas, 13, 74, 6, 3, character.accent);
        _rect(canvas, 15, 73, 2, 1, NightColors.paper);
        break;
      case PixelAccessory.cameraStrap:
        canvas.drawLine(
          const Offset(21, 61),
          const Offset(44, 86),
          Paint()
            ..color = _shade(character.hair, 0.55)
            ..strokeWidth = 2,
        );
        _rect(canvas, 42, 69, 9, 7, _ink);
        _rect(canvas, 44, 71, 4, 3, _shade(character.accent, 0.8));
        _rect(canvas, 46, 72, 1, 1, NightColors.paper);
        break;
      case PixelAccessory.apron:
        _poly(
            canvas,
            const [
              Offset(25, 63),
              Offset(39, 63),
              Offset(43, 88),
              Offset(21, 88),
            ],
            character.accent.withValues(alpha: 0.75));
        _rect(canvas, 27, 62, 2, 7, _shade(character.accent, 0.65));
        _rect(canvas, 35, 62, 2, 7, _shade(character.accent, 0.65));
        break;
    }
  }

  void _rimLight(Canvas canvas) {
    final light = character.accent.withValues(alpha: 0.32);
    _rect(canvas, 15, 28, 1, 26, light);
    _rect(canvas, 48, 32, 1, 22, light);
  }

  void _scanlines(Canvas canvas) {
    for (double y = 0; y < 88; y += 3) {
      _rect(canvas, 0, y, 64, 1, Colors.black.withValues(alpha: 0.045));
    }
  }

  void _rect(
      Canvas canvas, double x, double y, double w, double h, Color color) {
    canvas.drawRect(
      Rect.fromLTWH(x, y, w, h),
      Paint()
        ..color = color
        ..isAntiAlias = false,
    );
  }

  void _poly(Canvas canvas, List<Offset> points, Color color) {
    final path = Path()..addPolygon(points, true);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..isAntiAlias = false,
    );
  }

  Color _shade(Color color, double factor) {
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withLightness((hsl.lightness * factor).clamp(0.0, 1.0))
        .toColor();
  }

  @override
  bool shouldRepaint(_PixelPortraitPainter old) {
    return old.character.id != character.id ||
        old.expression != expression ||
        old.scanlines != scanlines;
  }
}
