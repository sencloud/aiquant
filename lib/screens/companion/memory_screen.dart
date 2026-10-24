import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/companion_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/wk_kit.dart';

/// 「她记得的事」：只列你明确说过、她没有删掉的事；可逐条删除。
class MemoryScreen extends StatelessWidget {
  const MemoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<CompanionState>();
    return WkPage(
      title: '她记得的事',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSpace.md, AppSpace.md, AppSpace.md, AppSpace.xxl),
        children: [
          Text('这些是你明确说过的。她不会猜，也不会从别处补。',
              style: AppType.caption
                  .copyWith(color: AppColors.textSecondary, height: 1.6)),
          const SizedBox(height: AppSpace.md),
          if (c.memories.isEmpty)
            const WkNote(text: '她还没记住什么。聊几句「我喜欢…」「我最近…」她就会记下。')
          else
            WkGroup(
              children: [
                for (final m in c.memories)
                  WkRow(
                    title: m,
                    trailing: IconButton(
                      tooltip: '删掉这条',
                      icon: Icon(Icons.close_rounded,
                          size: 18, color: AppColors.textTertiary),
                      onPressed: () => c.removeMemory(m),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
