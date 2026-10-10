import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/analytics.dart';
import '../../state/auth_state.dart';
import '../../theme/app_theme.dart';

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
///
/// 停顿不是死等：底部状态文字按阶段推进；网络差到超过 [maxWait] 就直接进 App，
/// 不拿开屏锁人。
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
  Timer? _tick;
  Timer? _ceiling;

  /// 最短停留是否已经走满。
  bool _minElapsed = false;
  bool _finished = false;
  AuthState? _auth;
  late final DateTime _started = DateTime.now();

  @override
  void initState() {
    super.initState();
    Analytics.instance.track(Analytics.evAppOpen);

    // 状态文字在最短停留内推进完；之后如果还在等登录态，会换成「网络有点慢」。
    final tick = widget.minDuration.inMilliseconds ~/ _steps.length;
    _tick = Timer.periodic(Duration(milliseconds: tick), (t) {
      if (!mounted) return t.cancel();
      if (_step < _steps.length - 1) {
        setState(() => _step++);
      } else {
        t.cancel();
      }
    });

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
  }

  @override
  void dispose() {
    _tick?.cancel();
    _ceiling?.cancel();
    _auth?.removeListener(_maybeFinish);
    _c.dispose();
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

  @override
  Widget build(BuildContext context) {
    final ease = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
    // 时间走满了还在等，说明真的是网络慢 —— 如实说，别让它看着像卡住。
    final waiting = _minElapsed && (_auth?.bootstrapping ?? false);
    final status = waiting ? '网络有点慢，马上就好…' : _steps[_step];

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
                    status,
                    key: ValueKey(status),
                    style: AppType.micro.copyWith(color: AppColors.textTertiary),
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
