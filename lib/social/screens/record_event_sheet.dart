import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../theme/app_theme.dart';
import '../../widgets/wk_kit.dart';
import '../social_state.dart';

/// 「记一件事」。三秒能做完是它的硬指标：一句话 + 最多三个数。
///
/// 这一步做完，「说一句」才有地方落 —— 由头制是这套东西的地基，不因为圈子
/// 下线而变。
Future<void> showRecordEventSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.bgSurface,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + AppSpace.xl),
      child: const _RecordEventSheet(),
    ),
  );
}

class _RecordEventSheet extends StatefulWidget {
  const _RecordEventSheet();

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
    context.read<SocialState>().recordEvent(title: title, facts: facts);
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
          const Text('记一件事', style: AppType.title),
          const SizedBox(height: AppSpace.sm),
          Text('事是话的由头 —— 先有事，才有话。',
              style: AppType.caption.copyWith(color: AppColors.textTertiary)),
          const SizedBox(height: AppSpace.lg),
          TextField(
            key: const ValueKey('event-title'),
            controller: _title,
            autofocus: true,
            style: AppType.body,
            decoration: const InputDecoration(
              labelText: '发生了什么',
              hintText: '今天盘后看了 300 的成交结构',
            ),
          ),
          const SizedBox(height: AppSpace.md),
          TextField(
            key: const ValueKey('event-facts'),
            controller: _facts,
            style: AppType.body,
            decoration: const InputDecoration(
              labelText: '几个数（可选，用逗号分开）',
              hintText: '成交额 3200 亿, 北向 +18 亿',
            ),
          ),
          const SizedBox(height: AppSpace.lg),
          WkPrimaryButton(label: '记下来', onPressed: _save),
        ],
      ),
    );
  }
}
