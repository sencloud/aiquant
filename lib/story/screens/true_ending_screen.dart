import 'package:flutter/material.dart';

import '../night_kit.dart';
import '../night_theme.dart';

/// 三条线都走完后的第十个结局：不是大团圆，是把话说完。
class TrueEndingScreen extends StatelessWidget {
  const TrueEndingScreen({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const NightBackdrop(rain: false),
        SafeArea(
          child: Column(
            children: [
              NightBar(
                title: '天亮以前',
                subtitle: '真结局 · 三条线都走完',
                onBack: onClose,
                actions: const [
                  PixelTag('TRUE', color: NightColors.amber),
                ],
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(24, 26, 24, 30),
                  children: [
                    Text('第 8 天 · 05:58',
                        style: NightType.micro.copyWith(
                          color: NightColors.amber,
                          letterSpacing: 2,
                        )),
                    const SizedBox(height: 30),
                    Text('第一班车进站的时候，\n雨已经停了。',
                        style: NightType.display.copyWith(
                          fontSize: 28,
                          height: 1.5,
                          letterSpacing: 2,
                        )),
                    const SizedBox(height: 26),
                    Text(
                      '你在站台看见林夏的相机、苏予的两杯黑咖啡、陈野的取景器。\n\n'
                      '他们没有走过来。你也没有。\n\n'
                      '通讯录还在。你没有删掉任何一个名字，也没有把哪一句说出口的话收回来。\n\n'
                      '七天以前，你以为自己只是来临海出差。七天以后，你带走了一卷没有冲洗的胶卷、'
                      '一杯凉掉的黑咖啡，和一段没有剪进片子的镜头。\n\n'
                      '这不是一个「得到」的故事。\n'
                      '但你在天亮以前，把话说完了一次。',
                      style: NightType.read.copyWith(
                        fontSize: 15,
                        height: 2.0,
                        color: NightColors.paper,
                      ),
                    ),
                    const SizedBox(height: 28),
                    Container(
                      width: 42,
                      height: 1,
                      color: NightColors.amber.withValues(alpha: 0.7),
                    ),
                    const SizedBox(height: 18),
                    Text('「喜爱，并不是一定要得到。」',
                        style: NightType.title.copyWith(
                          color: NightColors.amber,
                          fontSize: 16,
                          height: 1.7,
                        )),
                    const SizedBox(height: 34),
                    PixelButton(
                      label: '回到通讯录',
                      icon: Icons.arrow_back_rounded,
                      onPressed: onClose,
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: Text('结局 10 / 10 · 天亮以前',
                          style: NightType.micro.copyWith(letterSpacing: 1.6)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
