import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/topic/topic_state.dart';
import '../../services/analytics.dart';
import '../../state/auth_state.dart';
import '../../theme/app_theme.dart';
import 'splash_backdrop.dart';

/// 开屏页。
///
/// 它做两件事：
///   1. 给冷启动一个体面的门面 —— 至少停 [minDuration]（默认 2 秒）；
///   2. **等登录态校验真的结束**。
///
/// 第二件事是这个页面存在的一半理由。`AuthState` 是懒创建的：谁先读它，它才
/// 开始 `bootstrap()`。开屏如果不读不等，等开屏结束、`AuthGate` 拿到手时
/// bootstrapping 还是 true，就会退回它自己的「还没就绪」占位屏 —— 也就是用户
/// 看到的那个「第二个空标题页」。所以这里既读它（触发 bootstrap），也等它。
/// 网络差到超过 [maxWait] 就直接进 App，不拿开屏锁人。
///
/// 版式（见 DESIGN.md「Motion」）：没有图标。整屏是一片夜空 —— 竖向多段渐变
/// （随主题：喜爱钱暖墨 → 金 → 桃色天光；喜爱钓鱼深湖青 → 黎明；还没选主题用
/// 中性夜色），地平线辉光、围着题字的三道轨道细线、下方几道起伏细线、错落闪烁
/// 的星光，全部由 [SplashBackdropPainter] 一支画笔画。中间是衬线大字「喜爱」
/// 和口号「喜爱什么，就有什么」；底部一根发丝线代替加载文字。
///
/// 第一帧只有中性渐变，与原生启动屏（iOS LaunchImage / Android
/// splash_gradient，同一套色值）一致，所以冷启动不跳；随后 0.7s 内渐变过渡到
/// 主题色、星光与细线依次出现、题字收字距淡入。系统「减少动态效果」打开时
/// 直接显示最终静帧。
class SplashScreen extends StatefulWidget {
  const SplashScreen({
    super.key,
    required this.onDone,
    this.minDuration = _defaultMinDuration,
    this.maxWait = _defaultMaxWait,
  });

  /// 默认停 2 秒。设计走查可用 `--dart-define=SPLASH_MS=100` 缩短，
  /// 正常构建不要动它。
  static const _defaultMinDuration = Duration(
      milliseconds: int.fromEnvironment('SPLASH_MS', defaultValue: 2000));

  /// 硬上限：登录态校验拖太久（网络差时 `/me` 最长能等 30 秒）也不锁人。
  static const _defaultMaxWait = Duration(
      milliseconds: int.fromEnvironment('SPLASH_MAX_MS', defaultValue: 4500));

  /// 停顿结束后的回调。
  final VoidCallback onDone;

  /// 最短停留时间。低于这个时长也要等满。
  final Duration minDuration;

  /// 最长停留时间。到点无论如何进 App。
  final Duration maxWait;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  /// 品牌口号。全 App 统一一句，不随主题变。
  static const slogan = '喜爱什么，就有什么';

  /// 题字中心在屏高的位置（略高于正中，接近黄金分割）。
  static const focusY = 0.43;

  /// 入场节奏（毫秒，未压缩）。最后一段在 [_introEndMs] 放完。
  static const _introEndMs = 1450.0;

  /// 一支时钟驱动全部动效：只往前走一次（不 repeat），开屏最长也就 [maxWait]，
  /// 测试里的 pumpAndSettle 也能收住。
  static const _clockSpan = Duration(seconds: 10);

  /// 最短停留比入场还短时（设计走查 SPLASH_MS=100 之类）按比例压缩，
  /// 保证在停留时间内放完。
  late final double _scale = () {
    final cap = widget.minDuration.inMilliseconds * 0.8;
    return cap < _introEndMs ? cap / _introEndMs : 1.0;
  }();

  late final AnimationController _clock =
      AnimationController(vsync: this, duration: _clockSpan)..forward();

  bool _still = false;
  Timer? _ceiling;

  /// 最短停留是否已经走满。
  bool _minElapsed = false;
  bool _finished = false;
  AuthState? _auth;
  late final DateTime _started = DateTime.now();

  /// 目标色组：已选主题用它的，首启（还没选）用中性夜色。
  late SplashPalette _target = SplashPalette.neutral;

  @override
  void initState() {
    super.initState();
    Analytics.instance.track(Analytics.evAppOpen);

    Timer(widget.minDuration, () {
      if (!mounted) return;
      setState(() => _minElapsed = true);
      _maybeFinish();
    });

    // 兜底：超过上限直接进 App。
    _ceiling = Timer(widget.maxWait, _finish);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 读一次即触发 AuthState.bootstrap()（provider 是懒创建的）。
    final auth = context.read<AuthState>();
    if (!identical(auth, _auth)) {
      _auth?.removeListener(_maybeFinish);
      _auth = auth..addListener(_maybeFinish);
    }
    _target = SplashPalette.forTopic(_topicId());
    _still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (_still) {
      _clock.stop();
    } else if (!_clock.isAnimating && _clock.value < 1) {
      _clock.forward();
    }
  }

  String? _topicId() {
    try {
      final topics = Provider.of<TopicState>(context, listen: false);
      return topics.needsPick ? null : topics.currentId;
    } on ProviderNotFoundException {
      return identical(AppColors.topic, TopicPalette.fishing) ? 'fishing' : 'money';
    }
  }

  @override
  void dispose() {
    _ceiling?.cancel();
    _auth?.removeListener(_maybeFinish);
    _clock.dispose();
    super.dispose();
  }

  /// 两个条件都满足才收工：停够时间 + 登录态校验结束。
  void _maybeFinish() {
    if (_finished || !mounted || !_minElapsed) return;
    if (_auth?.bootstrapping ?? false) return;
    _finish();
  }

  void _finish() {
    if (_finished || !mounted) return;
    _finished = true;
    Analytics.instance.track(Analytics.evSplashDone, {
      'ms': DateTime.now().difference(_started).inMilliseconds,
      'waited_for_auth': _auth?.bootstrapping ?? false,
    });
    widget.onDone();
  }

  /// [startMs, endMs]（未压缩）这一段的进度。
  double _phase(double ms, double startMs, double endMs,
      [Curve curve = Curves.easeOutCubic]) {
    final a = startMs * _scale, b = endMs * _scale;
    final t = ((ms - a) / (b - a)).clamp(0.0, 1.0);
    return curve.transform(t);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SplashPalette.neutral.stops[2],
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: AnimatedBuilder(
          animation: _clock,
          builder: (context, _) {
            final elapsed = _clock.value * _clockSpan.inMilliseconds;
            final ms = _still ? double.infinity : elapsed;
            final seconds = _still ? 0.0 : elapsed / 1000;

            final bg = _phase(ms, 0, 700, Curves.easeInOutCubic);
            final palette = SplashPalette.lerp(SplashPalette.neutral, _target, bg);
            final title = _phase(ms, 380, 1180);
            final rule = _phase(ms, 700, 1300);
            final sub = _phase(ms, 820, 1450);
            final bar = _phase(ms, 1000, 1400);
            // 发丝线：停够时间就走满；还在等登录态就轻轻呼吸。
            final waiting = _minElapsed && (_auth?.bootstrapping ?? false);
            final progress = _still
                ? 1.0
                : Curves.easeInOut.transform(
                    (elapsed / widget.minDuration.inMilliseconds).clamp(0.0, 1.0));

            return LayoutBuilder(builder: (context, box) {
              final h = box.maxHeight;
              return Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      key: const Key('splash-backdrop'),
                      painter: SplashBackdropPainter(
                        palette: palette,
                        clock: seconds,
                        ambient: bg,
                        stars: _phase(ms, 120, 1300, Curves.linear),
                        lines: _phase(ms, 200, 1400, Curves.easeInOutCubic),
                        focusY: focusY,
                      ),
                    ),
                  ),
                  Positioned(
                    left: AppSpace.xl,
                    right: AppSpace.xl,
                    top: h * focusY - 44,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _Title(palette: palette, progress: title),
                        const SizedBox(height: AppSpace.lg),
                        _Rule(color: palette.line, progress: rule),
                        const SizedBox(height: AppSpace.lg),
                        Opacity(
                          opacity: sub,
                          child: Transform.translate(
                            offset: Offset(0, (1 - sub) * 8),
                            child: Padding(
                              // 字距会在最后一个字后面也留一份，左边补齐才真居中。
                              padding: const EdgeInsets.only(left: 4),
                              child: Text(
                                slogan,
                                key: const Key('splash-slogan'),
                                textAlign: TextAlign.center,
                                style: AppType.read.copyWith(
                                  fontSize: 15,
                                  height: 1.4,
                                  letterSpacing: 4,
                                  fontWeight: FontWeight.w400,
                                  color: palette.slogan.withValues(alpha: 0.86),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: MediaQuery.paddingOf(context).bottom + 44,
                    child: Semantics(
                      label: waiting ? '网络有点慢，马上就好' : '正在加载',
                      child: Opacity(
                        opacity: bar *
                            (waiting
                                ? 0.55 + 0.45 * (0.5 + 0.5 * math.sin(seconds * 4))
                                : 1),
                        child: _Hairline(color: palette.line, progress: progress),
                      ),
                    ),
                  ),
                ],
              );
            });
          },
        ),
      ),
    );
  }
}

/// 题字「喜爱」：衬线大字、上下双色渐变，入场时字距从疏收到定稿、淡入上浮。
class _Title extends StatelessWidget {
  const _Title({required this.palette, required this.progress});

  final SplashPalette palette;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final spacing = 30 - 12 * progress;
    return Opacity(
      opacity: progress,
      child: Transform.translate(
        offset: Offset(0, (1 - progress) * 14),
        child: ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (r) => LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [palette.titleTop, palette.titleBottom],
          ).createShader(r),
          child: Padding(
            padding: EdgeInsets.only(left: spacing),
            child: Text(
              '喜爱',
              key: const Key('splash-name'),
              textAlign: TextAlign.center,
              style: AppType.display.copyWith(
                fontSize: 54,
                height: 1.15,
                fontWeight: FontWeight.w500,
                letterSpacing: spacing,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 题字下的分隔：两段渐隐细线夹一粒菱形，从中间展开。
class _Rule extends StatelessWidget {
  const _Rule({required this.color, required this.progress});

  final Color color;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final arm = 40 * progress;
    Widget line(bool left) => Container(
          width: arm,
          height: 0.8,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: left
                  ? [color.withValues(alpha: 0), color.withValues(alpha: 0.7)]
                  : [color.withValues(alpha: 0.7), color.withValues(alpha: 0)],
            ),
          ),
        );
    return Opacity(
      opacity: progress,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          line(true),
          const SizedBox(width: 8),
          Transform.rotate(
            angle: math.pi / 4,
            child: Container(
              width: 3.6,
              height: 3.6,
              color: color.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(width: 8),
          line(false),
        ],
      ),
    );
  }
}

/// 底部发丝线：替代「正在加载…」文字，从中间向两边走满。
class _Hairline extends StatelessWidget {
  const _Hairline({required this.color, required this.progress});

  final Color color;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 96,
        height: 1,
        child: Stack(
          children: [
            Positioned.fill(
              child: ColoredBox(color: color.withValues(alpha: 0.14)),
            ),
            Center(
              child: FractionallySizedBox(
                key: const Key('splash-progress'),
                widthFactor: progress,
                heightFactor: 1,
                child: ColoredBox(color: color.withValues(alpha: 0.62)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
