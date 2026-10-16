import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../theme/app_theme.dart';
import '../../widgets/wk_kit.dart';
import '../social_state.dart';

/// 见面礼：这里的认识，从一样东西开始。
///
/// 第一版收到东西的是**你自己这一侧**（真人池还没开），所以文案不许写
/// 「他收到了」—— 只写东西先放在了哪儿。
class GiftScreen extends StatefulWidget {
  const GiftScreen({super.key});

  @override
  State<GiftScreen> createState() => _GiftScreenState();
}

class _GiftScreenState extends State<GiftScreen> {
  static const _kinds = <(String, String)>[
    ('一个想法', '你今天想通的那件事'),
    ('一张截图', '盘面、财报、一张图'),
    ('一段话', '十五秒，说清一件事'),
    ('一份记录', '你的一笔交易与它的理由'),
  ];

  int _kind = 0;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SocialState>();

    return WkPage(
      title: '送一样东西',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSpace.md, AppSpace.md, AppSpace.md, AppSpace.xxl),
        children: [
          const Text('这里的认识，从一样东西开始。', style: AppType.title),
          const SizedBox(height: AppSpace.sm),
          Text('不读通讯录，也不推「你可能认识的人」。想让谁认识你，先给他一样东西。',
              style: AppType.caption
                  .copyWith(color: AppColors.textSecondary, height: 1.6)),
          const SizedBox(height: AppSpace.xl),
          const Text('送什么', style: AppType.section),
          const SizedBox(height: AppSpace.sm),
          WkGroup(
            children: [
              for (var i = 0; i < _kinds.length; i++)
                WkRow(
                  key: ValueKey('gift-kind-$i'),
                  icon: Icons.card_giftcard_rounded,
                  title: _kinds[i].$1,
                  subtitle: _kinds[i].$2,
                  trailing: _kind == i
                      ? Icon(Icons.check_rounded,
                          size: 18, color: AppColors.amber)
                      : null,
                  onTap: () => setState(() => _kind = i),
                ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          const WkNote(
            text: '真人池还没开：东西先放在「我」这一侧，不进任何人的手机。'
                '等真人进来，他们看到的是你放在那里的一样东西，不是一句「你好」。',
          ),
          const SizedBox(height: AppSpace.lg),
          const Text('附一句话', style: AppType.section),
          const SizedBox(height: AppSpace.sm),
          Container(
            padding: const EdgeInsets.all(AppSpace.md),
            decoration: BoxDecoration(
              color: AppColors.bgSurface,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: TextField(
              key: const ValueKey('gift-note'),
              controller: _note,
              maxLines: 3,
              minLines: 2,
              style: AppType.read,
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: '为什么留这个 —— 一句话就够。',
              ),
            ),
          ),
          const SizedBox(height: AppSpace.xl),
          WkPrimaryButton(
            label: '送出去',
            onPressed: () {
              state.sendGift(
                title: _kinds[_kind].$1,
                toName: '先放在这里',
                note: _note.text,
              );
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('放进去了。收到的人可以不回 —— 送的时候你就知道。')));
            },
          ),
          const SizedBox(height: AppSpace.sm),
          Text('送的时候别去想他会不会回 —— 喜爱，并不是一定要得到。',
              textAlign: TextAlign.center,
              style: AppType.micro.copyWith(color: AppColors.textTertiary)),
        ],
      ),
    );
  }
}
