import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../theme/app_theme.dart';
import '../../widgets/wk_kit.dart';
import '../social_feed.dart';
import '../social_models.dart';
import '../social_state.dart';
import '../social_widgets.dart';
import 'record_event_sheet.dart';

/// 「说一句」：本产品的签名交互。
///
/// 一条话从「发送」变成「**挂靠 + 定时**」：
///   * 必须先选由头；没有由头就没有入口，页面会解释为什么；
///   * 可以选择「什么时候递给他」—— 选了就是一条回声。
class SpeakScreen extends StatefulWidget {
  const SpeakScreen({super.key, this.initial, this.echoFirst = false});

  /// 从某条事进来时，默认选中它。
  final SocialTarget? initial;

  /// 从「投一条回声」进来时，默认选中「明天早上」。
  final bool echoFirst;

  @override
  State<SpeakScreen> createState() => _SpeakScreenState();
}

class _SpeakScreenState extends State<SpeakScreen> {
  late SocialTarget? _target = widget.initial;
  late int _when = widget.echoFirst ? 1 : 0;
  final _text = TextEditingController();

  static const _whenOptions = <String>['现在', '明天早上 9:00'];

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _send() {
    final state = context.read<SocialState>();
    final now = DateTime.now();
    final deliverAt = _when == 0
        ? null
        : DateTime(now.year, now.month, now.day, 9)
            .add(const Duration(days: 1));
    final post = state.speak(
      target: _target,
      text: _text.text,
      deliverAt: deliverAt,
      deliveryNote: deliverAt == null ? '' : '明天早上 9:00 递出去',
    );
    if (post == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('先选一个由头 —— 这里没有「在吗」。')));
      return;
    }
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(deliverAt == null
            ? '挂上去了。谁在看那件事，谁就看得见。'
            : '投出去了。明天早上 9:00 递出去，在那之前你都能收回。')));
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SocialState>();
    final feed = buildToday(state);
    final targets = <SocialTarget>[
      if (widget.initial != null) widget.initial!,
      for (final e in feed.events) e.target,
    ];

    return WkPage(
      title: '说一句',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSpace.md, AppSpace.md, AppSpace.md, AppSpace.xxl),
        children: [
          const Text('这句话挂在什么上？', style: AppType.title),
          const SizedBox(height: AppSpace.sm),
          Text('每句话都得有个由头。选了由头，这句话就会跟着那件事走。',
              style: AppType.caption
                  .copyWith(color: AppColors.textSecondary, height: 1.6)),
          const SizedBox(height: AppSpace.lg),
          for (final t in targets)
            SocialTargetTile(
              key: ValueKey('target-${t.id}'),
              target: t,
              selected: _target?.id == t.id,
              onTap: () => setState(() => _target = t),
            ),
          if (targets.isEmpty)
            const WkNote(text: '今天还没有可以挂的事。先记一件事，再回来说这句。'),
          const SocialTargetTile(
            key: ValueKey('target-none'),
            target: null,
            selected: false,
            disabled: true,
            onTap: _noop,
          ),
          const SizedBox(height: AppSpace.md),
          Container(
            padding: const EdgeInsets.all(AppSpace.md),
            decoration: BoxDecoration(
              color: AppColors.bgSurface,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: TextField(
              key: const ValueKey('speak-text'),
              controller: _text,
              maxLines: 4,
              minLines: 3,
              style: AppType.read,
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: '今天这波放量，你是怎么看出来的？',
              ),
            ),
          ),
          const SizedBox(height: AppSpace.lg),
          Row(
            children: [
              const Text('什么时候递出去', style: AppType.section),
              const Spacer(),
              Text('不选就是现在',
                  style: AppType.micro.copyWith(color: AppColors.textTertiary)),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          Wrap(
            spacing: AppSpace.sm,
            children: [
              for (var i = 0; i < _whenOptions.length; i++)
                ChoiceChip(
                  key: ValueKey('when-$i'),
                  label: Text(_whenOptions[i]),
                  selected: _when == i,
                  onSelected: (_) => setState(() => _when = i),
                ),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          Text('没有已读，也没有「正在输入」。到点之前你都能收回。',
              style: AppType.micro.copyWith(color: AppColors.textTertiary)),
          const SizedBox(height: AppSpace.xl),
          WkPrimaryButton(label: '投出去', onPressed: _send),
          const SizedBox(height: AppSpace.sm),
          Center(
            child: WkTagButton(
              label: '先记一件事',
              onTap: () => showRecordEventSheet(context),
            ),
          ),
        ],
      ),
    );
  }

  static void _noop() {}
}
