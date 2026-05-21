import 'package:flutter/material.dart';

import '../../../models/strategy.dart';
import '../../../theme/app_theme.dart';
import 'top_tag_chip.dart';

/// 顶部「策略之王」入口：紧凑下拉 tag。
///
/// 点击后弹底部表，呈现已挂载的策略气泡列表（默认含 ETF 组合轮动）。
/// 用户在气泡里点「立即运行」会调用 [onRun] 把策略 prompt 发给 AI 助理。
class StrategyPicker extends StatelessWidget {
  const StrategyPicker({
    super.key,
    required this.onRun,
    this.disabled = false,
  });

  /// 用户点击某个策略的「立即运行」按钮 → 由父级调用 chat.sendMessage。
  final ValueChanged<Strategy> onRun;
  final bool disabled;

  Future<void> _openSheet(BuildContext context) async {
    final picked = await showModalBottomSheet<Strategy>(
      context: context,
      backgroundColor: AppColors.bgSurface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => const _StrategySheet(),
    );
    if (picked != null) onRun(picked);
  }

  @override
  Widget build(BuildContext context) {
    return TopTagChip(
      icon: Icons.workspace_premium,
      label: '策略之王',
      accent: AppColors.amber,
      active: false,
      disabled: disabled,
      onTap: () => _openSheet(context),
    );
  }
}

class _StrategySheet extends StatelessWidget {
  const _StrategySheet();

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: h * 0.82),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SheetHeader(
            icon: Icons.workspace_premium,
            title: '策略之王',
            subtitle: '挂载策略 · 一键由 AI 助理调用 Tushare 行情执行并产出报告。',
            onClose: () => Navigator.of(context).maybePop(),
          ),
          Divider(height: 1, color: AppColors.borderDim),
          Flexible(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
              itemCount: Strategies.all.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final s = Strategies.all[i];
                return _StrategyBubble(
                  strategy: s,
                  onRun: () => Navigator.of(context).pop(s),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// 单个策略卡片（气泡），包含图标 / 标题 / 副标题 / 4 条 highlight / 运行按钮。
class _StrategyBubble extends StatelessWidget {
  const _StrategyBubble({required this.strategy, required this.onRun});

  final Strategy strategy;
  final VoidCallback onRun;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgRaised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: strategy.color.withValues(alpha: 0.45)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: strategy.color,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(strategy.icon, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      strategy.name,
                      style: const TextStyle(
                        color: AppColors.amber,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      strategy.tagline,
                      style: TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...strategy.highlights.map(
            (h) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 5, right: 6),
                    child: Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        color: strategy.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      h,
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Spacer(),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: strategy.color,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  textStyle: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w800),
                ),
                icon: const Icon(Icons.play_arrow_rounded, size: 16),
                label: const Text('立即运行'),
                onPressed: onRun,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onClose,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.amber),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.amber,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 11,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '关闭',
            onPressed: onClose,
            icon: Icon(Icons.close, size: 18, color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }
}
