import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../night_kit.dart';
import '../night_theme.dart';
import '../story_state.dart';

class NightEndScreen extends StatefulWidget {
  const NightEndScreen({super.key});

  @override
  State<NightEndScreen> createState() => _NightEndScreenState();
}

class _NightEndScreenState extends State<NightEndScreen> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final story = context.watch<StoryState>();
    final night = story.currentNight;
    final character = story.activeCharacter;
    if (night == null || character == null) {
      return const SizedBox.shrink();
    }

    final route = story.season.routeOf(character.id);
    final next = route != null && night.number < route.nights.length
        ? route.nights[night.number]
        : null;
    final last = next == null;

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
                Row(
                  children: [
                    Text('第 ${night.number} 夜 · 完',
                        style: NightType.micro.copyWith(
                          color: NightColors.amber,
                          letterSpacing: 2,
                        )),
                    const Spacer(),
                    HeartRow(hearts: story.hearts, size: 14),
                  ],
                ),
                const SizedBox(height: 42),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('“${night.closing}”',
                          style: NightType.display.copyWith(
                            fontSize: 25,
                            height: 1.65,
                            letterSpacing: 1.2,
                          )),
                      const SizedBox(height: 24),
                      Container(
                        width: 42,
                        height: 1,
                        color: NightColors.amber.withValues(alpha: 0.7),
                      ),
                      const SizedBox(height: 18),
                      Text(character.name,
                          style: NightType.title.copyWith(
                            color: NightColors.amber,
                          )),
                      const SizedBox(height: 6),
                      Text(
                        last
                            ? '天快亮了。'
                            : '下一夜：第 ${night.number + 1} 夜 · ${next.title}',
                        style: NightType.caption.copyWith(height: 1.6),
                      ),
                    ],
                  ),
                ),
                PixelButton(
                  label: last ? '走到天亮' : '收下这一夜',
                  icon:
                      last ? Icons.wb_twilight_rounded : Icons.nightlight_round,
                  onPressed: _busy
                      ? null
                      : () async {
                          setState(() => _busy = true);
                          await story.endNight();
                          if (mounted) setState(() => _busy = false);
                        },
                ),
                const SizedBox(height: 10),
                Center(
                  child: Text(
                    last ? '天亮以前，把话说完。' : '不用急。TA 会等你。',
                    style: NightType.micro.copyWith(letterSpacing: 1.2),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
