import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/topic/topic_pack.dart';
import '../../theme/app_theme.dart';
import '../../widgets/wk_kit.dart';
import '../social_state.dart';

/// 「记一件事」。三秒能做完是它的硬指标：一句话 + 最多三个数。
/// 这一步做完，「说一句」才有地方落。
Future<void> showRecordEventSheet(BuildContext context, TopicPack pack) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.bgBase,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + AppSpace.xl),
      child: _RecordEventSheet(pack: pack),
    ),
  );
}

class _RecordEventSheet extends StatefulWidget {
  const _RecordEventSheet({required this.pack});

  final TopicPack pack;

  @override
  State<_RecordEventSheet> createState() => _RecordEventSheetState();
}

class _RecordEventSheetState extends State<_RecordEventSheet> {
  final _title = TextEditingController();
  final _facts = TextEditingController();

  @override
  void dispose() {
    _title.dispose();
    _facts.dispose();
    super.dispose();
  }

  void _save() {
    final title = _title.text.trim();
    if (title.isEmpty) return;
    final facts = _facts.text
        .split(RegExp(r'[,，、]'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    context.read<SocialState>().recordEvent(
          circleId: widget.pack.id,
          circleName: widget.pack.name,
          circleMark: widget.pack.mark,
          title: title,
          facts: facts,
        );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpace.gutter, 0, AppSpace.gutter, AppSpace.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('记一件事', style: AppType.display.copyWith(fontSize: 22)),
          const SizedBox(height: AppSpace.sm),
          Text('记在「${widget.pack.name}」里。事是话的由头 —— 先有事，才有话。',
              style: AppType.caption.copyWith(color: AppColors.textTertiary)),
          const SizedBox(height: AppSpace.lg),
          TextField(
            key: const ValueKey('event-title'),
            controller: _title,
            autofocus: true,
            style: AppType.body,
            decoration: const InputDecoration(
              labelText: '发生了什么',
              hintText: '登记了一条渔获：翘嘴 42cm',
            ),
          ),
          const SizedBox(height: AppSpace.md),
          TextField(
            key: const ValueKey('event-facts'),
            controller: _facts,
            style: AppType.body,
            decoration: const InputDecoration(
              labelText: '几个数（可选，用逗号分开）',
              hintText: '水温 24℃, 水域 北岸支流',
            ),
          ),
          const SizedBox(height: AppSpace.lg),
          WkPrimaryButton(label: '记下来', onPressed: _save),
        ],
      ),
    );
  }
}
