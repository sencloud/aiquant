import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/analytics.dart';
import '../../theme/app_theme.dart';

/// 开屏页。
///
/// 存在的理由有两层：一是给冷启动一个体面的门面，二是**把初始化停顿显性
/// 化** —— 至少停 1 秒（[minDuration]），让登录态校验、Hive 打开、网络预热
/// 这些必须在首屏之前完成的事有个交代，而不是先闪一帧半成品页面再跳走。
///
/// 这一秒不是死等：底部那行状态文字按阶段推进，用户看到的是「正在发生什么」。
class SplashScreen extends StatefulWidget {
  const SplashScreen({
    super.key,
    required this.onDone,
    this.minDuration = _defaultMinDuration,
  });

  /// 默认停顿 1 秒。仅设计走查时用 `--dart-define=SPLASH_MS=4000` 拉长，
  /// 好把这一屏截清楚；正常构建不要动它。
  static const _defaultMinDuration = Duration(
      milliseconds: int.fromEnvironment('SPLASH_MS', defaultValue: 1000));

  /// 停顿结束后的回调。
  final VoidCallback onDone;

  /// 最短停留时间。低于这个时长也要等满。
  final Duration minDuration;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 620),
  )..forward();

  final List<String> _steps = const [
    '正在打开本地档案…',
    '正在校验登录状态…',
    '正在预热行情连接…',
  ];
  int _step = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    final started = DateTime.now();
    Analytics.instance.track(Analytics.evAppOpen);

    // 状态文字按三等份推进，读完刚好一秒。
    final tick = widget.minDuration.inMilliseconds ~/ _steps.length;
    _timer = Timer.periodic(Duration(milliseconds: tick), (t) {
      if (!mounted) return t.cancel();
      if (_step < _steps.length - 1) {
        setState(() => _step++);
      } else {
        t.cancel();
      }
    });

    Timer(widget.minDuration, () {
      if (!mounted) return;
      Analytics.instance.track(Analytics.evSplashDone, {
        'ms': DateTime.now().difference(started).inMilliseconds,
      });
      widget.onDone();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ease = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      // SizedBox.expand 不能省：body 给下来的是宽松约束，Column 会收缩到最宽
      // 子节点的宽度并贴左，整页看起来会偏掉。撑满之后居中才是真的居中。
      body: SizedBox.expand(
        child: SafeArea(
          child: Column(
            children: [
              const Spacer(flex: 5),
              FadeTransition(
                opacity: ease,
                child: SlideTransition(
                  position: Tween(
                    begin: const Offset(0, 0.06),
                    end: Offset.zero,
                  ).animate(ease),
                  child: Column(
                    children: [
                      Text(
                        '喜爱',
                        style: AppType.display.copyWith(
                          fontSize: 46,
                          height: 1.1,
                          letterSpacing: 6,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: AppSpace.md),
                      Text(
                        '喜 AI · 策略证伪台',
                        style: AppType.caption.copyWith(
                          color: AppColors.textSecondary,
                          letterSpacing: 2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(flex: 4),
              // 一句话把产品立场写在开屏上：这里不卖策略，只做证伪。
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.xxl),
                child: FadeTransition(
                  opacity: ease,
                  child: Text(
                    '不是策略生成器，是策略证伪器',
                    textAlign: TextAlign.center,
                    style: AppType.caption.copyWith(
                        color: AppColors.textTertiary, letterSpacing: 1),
                  ),
                ),
              ),
              const SizedBox(height: AppSpace.xl),
              SizedBox(
                height: 16,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 240),
                  child: Text(
                    _steps[_step],
                    key: ValueKey(_step),
                    style:
                        AppType.micro.copyWith(color: AppColors.textTertiary),
                  ),
                ),
              ),
              const SizedBox(height: AppSpace.xxl),
            ],
          ),
        ),
      ),
    );
  }
}
