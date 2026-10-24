import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/companion_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/wk_kit.dart';

/// 「她记得的喜欢」：勾几个，或者自己写。
///
/// 这里选的东西会随每一轮对话发给服务端，拼进她的 system prompt；她不会
/// 假装知道你没勾过的事。
Future<void> showInterestsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.bgSurface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
    ),
    builder: (_) => const _InterestsSheet(),
  );
}

class _InterestsSheet extends StatefulWidget {
  const _InterestsSheet();

  @override
  State<_InterestsSheet> createState() => _InterestsSheetState();
}

class _InterestsSheetState extends State<_InterestsSheet> {
  late final List<String> _picked =
      List<String>.from(context.read<CompanionState>().interests);
  final _custom = TextEditingController();

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  void _toggle(String v) {
    setState(() {
      if (_picked.contains(v)) {
        _picked.remove(v);
      } else if (_picked.length < 8) {
        _picked.add(v);
      }
    });
  }

  void _addCustom() {
    final v = _custom.text.trim();
    if (v.isEmpty) return;
    if (!_picked.contains(v) && _picked.length < 8) {
      setState(() => _picked.add(v));
    }
    _custom.clear();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            AppSpace.lg,
            AppSpace.lg,
            AppSpace.lg,
            AppSpace.lg + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('她记得的喜欢', style: AppType.title),
                const Spacer(),
                Text('${_picked.length}/8',
                    style: AppType.micro
                        .copyWith(color: AppColors.textTertiary)),
              ],
            ),
            const SizedBox(height: AppSpace.xs),
            Text('她只聊你勾过的事，不会假装知道你的持仓、去过哪里。',
                style: AppType.caption
                    .copyWith(color: AppColors.textSecondary, height: 1.5)),
            const SizedBox(height: AppSpace.md),
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.sm,
              children: [
                for (final v in CompanionState.presets)
                  ChoiceChip(
                    key: ValueKey('interest-$v'),
                    label: Text(v),
                    selected: _picked.contains(v),
                    onSelected: (_) => _toggle(v),
                  ),
              ],
            ),
            if (_picked.isNotEmpty) ...[
              const SizedBox(height: AppSpace.md),
              Text('她会记住：${_picked.join(' · ')}',
                  style:
                      AppType.caption.copyWith(color: AppColors.textSecondary)),
            ],
            const SizedBox(height: AppSpace.md),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _custom,
                    style: AppType.body,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _addCustom(),
                    decoration: const InputDecoration(
                      hintText: '还有别的？比如：看展、养猫',
                    ),
                  ),
                ),
                const SizedBox(width: AppSpace.sm),
                TextButton(onPressed: _addCustom, child: const Text('加上')),
              ],
            ),
            const SizedBox(height: AppSpace.lg),
            WkPrimaryButton(
              key: const ValueKey('interests-save'),
              label: '记下来',
              onPressed: () async {
                await context.read<CompanionState>().setInterests(_picked);
                if (!context.mounted) return;
                Navigator.of(context).pop();
              },
            ),
          ],
        ),
      ),
    );
  }
}
