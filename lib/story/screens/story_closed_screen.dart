import 'package:flutter/material.dart';

import '../night_kit.dart';
import '../night_theme.dart';

/// 远程总开关关掉 / 整季下线时的页面。
class StoryClosedScreen extends StatelessWidget {
  const StoryClosedScreen({
    super.key,
    required this.notice,
    required this.onRetry,
    required this.onExit,
  });

  final String notice;
  final VoidCallback onRetry;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const NightBackdrop(rain: false),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 26, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('喜爱 · 天亮以前',
                    style: NightType.micro.copyWith(
                      color: NightColors.amber,
                      letterSpacing: 2,
                    )),
                const Spacer(),
                Text('今晚不营业。',
                    style: NightType.display.copyWith(
                      fontSize: 30,
                      letterSpacing: 3,
                    )),
                const SizedBox(height: 14),
                Text(
                  notice.trim().isEmpty ? '通讯录暂时关上了。等天亮一点，再来看看。' : notice,
                  style: NightType.read.copyWith(
                    color: NightColors.paper,
                    height: 1.9,
                  ),
                ),
                const SizedBox(height: 28),
                PixelButton(
                  label: '再试一次',
                  icon: Icons.refresh_rounded,
                  onPressed: onRetry,
                ),
                const SizedBox(height: 8),
                PixelButton(
                  label: '退出',
                  filled: false,
                  onPressed: onExit,
                ),
                const Spacer(),
                Center(
                  child: Text('00:00 · 通讯录已收起',
                      style: NightType.micro.copyWith(letterSpacing: 2)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
