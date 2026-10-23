import 'package:flutter/material.dart';

import '../night_kit.dart';
import '../night_theme.dart';

class StoryIntroScreen extends StatelessWidget {
  const StoryIntroScreen({
    super.key,
    required this.onEnter,
    required this.onExit,
  });

  final VoidCallback onEnter;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const NightBackdrop(),
        SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: MediaQuery.sizeOf(context).height - 90,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('喜爱 · 二次元试用',
                          style: NightType.micro.copyWith(
                            color: NightColors.amber,
                            letterSpacing: 1.6,
                          )),
                      const Spacer(),
                      const Text('临海 · 七日', style: NightType.micro),
                    ],
                  ),
                  const SizedBox(height: 54),
                  Text('天亮以前',
                      style: NightType.display.copyWith(
                        fontSize: 42,
                        letterSpacing: 5,
                        height: 1.1,
                      )),
                  const SizedBox(height: 12),
                  Container(
                    width: 92,
                    height: 1,
                    color: NightColors.amber.withValues(alpha: 0.7),
                  ),
                  const SizedBox(height: 14),
                  Text('你只在临海待七天。',
                      style: NightType.body.copyWith(
                        fontSize: 17,
                        color: NightColors.paper,
                      )),
                  const SizedBox(height: 6),
                  Text('第八天清晨，第一班车。\n夜里睡不着，通讯录里多了六个名字。\n其中三个，是未接来电。',
                      style: NightType.read.copyWith(height: 1.9)),
                  const SizedBox(height: 34),
                  const NightNote(
                    '这是一个虚构故事。角色由 AI 扮演，所有角色均为成年人。\n'
                    '故事里的关系不会延续到现实。你可以随时退出。',
                  ),
                  const SizedBox(height: 28),
                  PixelButton(
                    label: '进入临海',
                    icon: Icons.nightlight_round,
                    onPressed: onEnter,
                  ),
                  const SizedBox(height: 10),
                  Center(
                    child: TextButton(
                      onPressed: onExit,
                      child: Text('退出',
                          style: NightType.caption.copyWith(
                            color: NightColors.faint,
                            letterSpacing: 2,
                          )),
                    ),
                  ),
                  const SizedBox(height: 42),
                  Center(
                    child: Text('00:47 · 旧公寓 · 雨',
                        style: NightType.micro.copyWith(letterSpacing: 2)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
