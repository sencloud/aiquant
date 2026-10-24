import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../services/analytics.dart';
import '../../state/auth_state.dart';
import '../../theme/app_theme.dart';

/// 开屏页。
///
/// 1.7.0 之后 App 只剩一位伴侣，开屏就只做一件事：让她先出现，然后安静地
/// 让位给对话。没有星空、没有轨道线 —— 一张写真、名字、一句「陪伴是长情的
/// 告白」，底部一根细线等登录态校验结束。
///
/// 计时逻辑与旧版一致：至少停 [minDuration]，同时等 AuthState.bootstrap；
/// 超过 [maxWait] 强制进 App。
class SplashScreen extends StatefulWidget {
  const SplashScreen({
    super.key,
    required this.onDone,
    this.minDuration = _defaultMinDuration,
    this.maxWait = _defaultMaxWait,
  });

  static const _defaultMinDuration = Duration(
      milliseconds: int.fromEnvironment('SPLASH_MS', defaultValue: 1600));
  static const _defaultMaxWait = Duration(
      milliseconds: int.fromEnvironment('SPLASH_MAX_MS', defaultValue: 4500));

  final VoidCallback onDone;
  final Duration minDuration;
  final Duration maxWait;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  static const slogan = '陪伴是长情的告白';

  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..forward();

  Timer? _ceiling;
  bool _minElapsed = false;
  bool _finished = false;
  bool _still = false;
  AuthState? _auth;
  late final DateTime _started = DateTime.now();

  @override
  void initState() {
    super.initState();
    Analytics.instance.track(Analytics.evAppOpen);
    Timer(widget.minDuration, () {
      if (!mounted) return;
      setState(() => _minElapsed = true);
      _maybeFinish();
    });
    _ceiling = Timer(widget.maxWait, _finish);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = context.read<AuthState>();
    if (!identical(auth, _auth)) {
      _auth?.removeListener(_maybeFinish);
      _auth = auth..addListener(_maybeFinish);
    }
    _still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (_still) {
      _clock.stop();
    } else if (!_clock.isAnimating && _clock.value < 1) {
      _clock.forward();
    }
  }

  @override
  void dispose() {
    _ceiling?.cancel();
    _auth?.removeListener(_maybeFinish);
    _clock.dispose();
    super.dispose();
  }

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
    return Scaffold(
      backgroundColor: const Color(0xFFF4EEE4),
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark,
        child: AnimatedBuilder(
          animation: _clock,
          builder: (context, _) {
            final t = _still ? 1.0 : _clock.value;
            final photo = Curves.easeOutCubic
                .transform((t / 0.75).clamp(0.0, 1.0));
            final text = Curves.easeOutCubic
                .transform(((t - 0.25) / 0.65).clamp(0.0, 1.0));
            return Stack(
              children: [
                const Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFFF8F3EA), Color(0xFFEADCC8)],
                      ),
                    ),
                  ),
                ),
                // 左上角一团暖气，像清晨的窗光。
                Positioned(
                  left: -120,
                  top: -140,
                  child: Container(
                    width: 420,
                    height: 420,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          const Color(0xFF9E6322).withValues(alpha: 0.16),
                          const Color(0xFF9E6322).withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Opacity(
                        opacity: photo,
                        child: Transform.translate(
                          offset: Offset(0, (1 - photo) * 16),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(32),
                            child: Image.asset(
                              'assets/portraits/xiai.jpg',
                              width: 132,
                              height: 132,
                              fit: BoxFit.cover,
                              gaplessPlayback: true,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpace.xl),
                      Opacity(
                        opacity: text,
                        child: Transform.translate(
                          offset: Offset(0, (1 - text) * 10),
                          child: Text(
                            '喜爱',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 34,
                              letterSpacing: 8,
                              height: 1.2,
                              fontWeight: FontWeight.w600,
                              fontFamilyFallback: AppType.sansFallback,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpace.md),
                      Opacity(
                        opacity: text,
                        child: Text(
                          slogan,
                          style: AppType.read.copyWith(
                            fontSize: 15,
                            letterSpacing: 2.5,
                            color: const Color(0xFF7A6A58),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 56,
                  child: Center(
                    child: _LoadingHairline(
                      progress: _still
                          ? 1
                          : (t * 1.2).clamp(0.0, 1.0),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _LoadingHairline extends StatelessWidget {
  const _LoadingHairline({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      height: 2,
      decoration: BoxDecoration(
        color: const Color(0xFF9E6322).withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(1),
      ),
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: progress,
        child: Container(
          height: 2,
          decoration: BoxDecoration(
            color: const Color(0xFF9E6322),
            borderRadius: BorderRadius.circular(1),
          ),
        ),
      ),
    );
  }
}
