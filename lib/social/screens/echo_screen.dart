import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../theme/app_theme.dart';
import '../../widgets/wk_kit.dart';
import '../social_state.dart';
import '../social_widgets.dart';
import 'speak_screen.dart';

/// 回声：说不出口的，投给以后。
///
/// 回声不是定时消息 —— 第一版支持「明天早上 9:00」这类时间条件，
/// 「等他下次来」这种**行为条件**要等服务端的投递器（见设计文档 §8.3）。
/// 条件到之前随时可以撤回（规矩 07）。
class EchoScreen extends StatelessWidget {
  const EchoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SocialState>();
    final inFlight = state.inFlight;
    final arrived = state.arrived.where((p) => p.isEcho).toList(growable: false);

    return WkPage(
      title: '回声',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSpace.gutter, AppSpace.sm, AppSpace.gutter, AppSpace.xxl),
        children: [
          const Text('说不出口的，投给以后。', style: AppType.display),
          const SizedBox(height: AppSpace.sm),
          Text('回声等的不是定时器，是一个条件 —— 他下次来、豆子喝完、明天早上。'
              '条件到之前，你可以随时收回。',
              style: AppType.read.copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: AppSpace.xl),
          Row(
            children: [
              const Text('在路上', style: AppType.section),
              const Spacer(),
              Text('${inFlight.length} 条',
                  style: AppType.micro.copyWith(color: AppColors.textTertiary)),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          if (inFlight.isEmpty)
            const WkNote(text: '还没有在路上。')
          else
            for (final p in inFlight)
              SocialPostTile(
                key: ValueKey('echo-${p.id}'),
                post: p,
                onWithdraw: (post) => state.withdraw(post.id),
              ),
          const SizedBox(height: AppSpace.xl),
          Row(
            children: [
              const Text('到了', style: AppType.section),
              const Spacer(),
              Text('${arrived.length} 条',
                  style: AppType.micro.copyWith(color: AppColors.textTertiary)),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          if (arrived.isEmpty)
            const WkNote(text: '还没有到了的回声。到了的会在这里，也会出现在那件事下面。')
          else
            for (final p in arrived)
              SocialPostTile(key: ValueKey('arrived-${p.id}'), post: p),
          const SizedBox(height: AppSpace.xl),
          WkPrimaryButton(
            label: '投一条回声',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => const SpeakScreen(echoFirst: true))),
          ),
          const SizedBox(height: AppSpace.sm),
          Text('投出去的当晚不一定有回复 —— 这里本来就不承诺「马上」。',
              textAlign: TextAlign.center,
              style: AppType.micro.copyWith(color: AppColors.textTertiary)),
        ],
      ),
    );
  }
}
