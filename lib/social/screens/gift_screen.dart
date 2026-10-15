import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/topic/topic_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/wk_kit.dart';
import '../social_feed.dart';
import '../social_state.dart';

/// 见面礼：这里的认识，从一样东西开始。
///
/// 第一版收到东西的是**圈**（和你自己的记录）：真人池还没开，
/// 所以文案不许写「他收到了」——只写东西进了哪个圈、谁将来会看到。
class GiftScreen extends StatefulWidget {
  const GiftScreen({super.key});

  @override
  State<GiftScreen> createState() => _GiftScreenState();
}

class _GiftScreenState extends State<GiftScreen> {
  static const _kinds = <(String, String)>[
    ('一个钓点', '你常去的、愿意说的那一个'),
    ('一支豆子', '分他 50g，附上烘焙日'),
    ('一张照片', '你拍的水面、猫、营地'),
    ('一段话', '十五秒，说清一件事'),
  ];

  int _kind = 0;
  int _to = 0;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pack = context.watch<TopicState>().current;
    final state = context.watch<SocialState>();
    final residents = residentsOf(pack);
    final toName = residents.isEmpty ? '${pack.name}这个圈' : residents[_to % residents.length].name;

    return WkPage(
      title: '送一样东西',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSpace.gutter, AppSpace.sm, AppSpace.gutter, AppSpace.xxl),
        children: [
          const Text('这里的认识，从一样东西开始。', style: AppType.display),
          const SizedBox(height: AppSpace.sm),
          Text('不读通讯录，也不推「你可能认识的人」。想让谁认识你，先给他一样东西。',
              style: AppType.read.copyWith(color: AppColors.textSecondary)),
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
                          size: 16, color: AppColors.amber)
                      : null,
                  onTap: () => setState(() => _kind = i),
                ),
            ],
          ),
          const SizedBox(height: AppSpace.lg),
          const Text('送给谁', style: AppType.section),
          const SizedBox(height: AppSpace.sm),
          if (residents.isEmpty)
            WkNote(text: '你的圈里还没有 AI 居民 —— 东西会先放在「${pack.name}」里。')
          else
            WkGroup(
              children: [
                for (var i = 0; i < residents.length; i++)
                  WkRow(
                    key: ValueKey('gift-to-$i'),
                    icon: Icons.smart_toy_outlined,
                    title: '${residents[i].name} · AI 居民',
                    subtitle: residents[i].blurb,
                    trailing: _to % residents.length == i
                        ? Icon(Icons.check_rounded,
                            size: 16, color: AppColors.amber)
                        : null,
                    onTap: () => setState(() => _to = i),
                  ),
              ],
            ),
          const SizedBox(height: AppSpace.sm),
          const WkNote(
            text: '现在的规矩：东西先放进圈里（真人池还没开）。真人进来之后，'
                '他们看到的是你放在那里的一样东西，不是一句「你好」。',
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
                hintText: '北岸那个湾，走船道二十分钟。我用 4.5 的竿。',
              ),
            ),
          ),
          const SizedBox(height: AppSpace.xl),
          WkPrimaryButton(
            label: '送出去',
            onPressed: () {
              state.sendGift(
                title: _kinds[_kind].$1,
                toName: toName,
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
