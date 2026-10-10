import 'package:flutter/material.dart';

import '../../models/falsification.dart';
import '../../models/falsification_index.dart';
import '../../theme/app_theme.dart';
import '../../widgets/wk_kit.dart';

/// 结论配色。遵循「纸上墨金」：淘汰用墨色灰（不用红绿，红绿留给涨跌），
/// 仍在验证用品牌墨金，可交易用信息蓝作强调，样本不足用警示色。
Color verdictColor(String verdict) => switch (verdict) {
      'reject' => AppColors.textSecondary,
      'pending' => AppColors.amber,
      'tradable' => AppColors.info,
      'insufficient' => AppColors.warning,
      _ => AppColors.textTertiary, // finding / 未知
    };

/// 策略家族 → 图标（通讯录里的「头像」）。family_key 优先，旧资产按中文名猜。
IconData familyIcon(ArchiveEntry e) {
  switch (e.familyKey) {
    case 'trend':
      return Icons.trending_up_rounded;
    case 'breakout':
      return Icons.open_in_full_rounded;
    case 'reversal':
      return Icons.swap_vert_rounded;
    case 'oscillator':
      return Icons.waves_rounded;
    case 'bands':
      return Icons.view_stream_rounded;
    case 'level':
      return Icons.horizontal_rule_rounded;
    case 'volatility':
      return Icons.ssid_chart_rounded;
    case 'volume':
      return Icons.bar_chart_rounded;
    case 'pattern':
      return Icons.auto_graph_rounded;
    case 'research':
      return Icons.science_rounded;
  }
  final f = ArchiveIndex.normalizeFamily(e.family);
  if (f.contains('趋势')) return Icons.trending_up_rounded;
  if (f.contains('突破')) return Icons.open_in_full_rounded;
  if (f.contains('反转') || f.contains('回归')) return Icons.swap_vert_rounded;
  if (f.contains('离场') || f.contains('止损')) return Icons.logout_rounded;
  if (f.contains('参数') || f.contains('稳健')) return Icons.tune_rounded;
  if (f.contains('因子') || f.contains('选股')) return Icons.filter_alt_rounded;
  return Icons.insights_rounded;
}

String freqLabel(String f) {
  if (f.isEmpty) return '';
  if (f == '1d') return '日线';
  return f.replaceAll('min', ' 分');
}

/// 通讯录头像：圆角方块，家族图标 + 结论色。
class ArchiveAvatar extends StatelessWidget {
  const ArchiveAvatar({super.key, required this.entry, this.size = 40});

  final ArchiveEntry entry;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = verdictColor(entry.verdict);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Icon(familyIcon(entry), size: size * 0.55, color: c),
    );
  }
}

/// 档案的一行：头像 → 名字 + 死在哪一关 / headline → 结论标签 + 品种周期。
class ArchiveRow extends StatelessWidget {
  const ArchiveRow({
    super.key,
    required this.entry,
    required this.gates,
    required this.onTap,
  });

  final ArchiveEntry entry;
  final List<FalsificationGate> gates;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final failed = entry.failedGateName(gates);
    final sub = switch (entry.verdict) {
      'reject' when failed.isNotEmpty => '死在$failed · ${entry.headline}',
      _ => entry.headline,
    };
    final where = [
      entry.name.isNotEmpty ? entry.name : entry.symbol,
      freqLabel(entry.freq)
    ].where((s) => s.isNotEmpty).join(' ');
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: 10),
          child: Row(
            children: [
              ArchiveAvatar(entry: entry),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(entry.strategy,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppType.body.copyWith(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w600)),
                        ),
                        if (entry.scaleMarginal) ...[
                          const SizedBox(width: AppSpace.xs),
                          const WkTag('勉强', tone: AppColors.warning),
                        ],
                        if (entry.needsRerun) ...[
                          const SizedBox(width: AppSpace.xs),
                          const WkTag('待重判', tone: AppColors.amber),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.caption
                            .copyWith(color: AppColors.textTertiary)),
                  ],
                ),
              ),
              const SizedBox(width: AppSpace.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  WkTag(entry.verdictLabel,
                      tone: verdictColor(entry.verdict), filled: true),
                  if (where.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(where,
                        style: AppType.micro.copyWith(
                            color: AppColors.textTertiary,
                            fontFamilyFallback: AppType.numericFallback)),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 顶部固定入口的彩色方块图标（通讯录里「新的朋友」那种）。
class EntryIcon extends StatelessWidget {
  const EntryIcon({super.key, required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Icon(icon, size: 22, color: Colors.white),
    );
  }
}

/// 顶部入口行：彩色方块 + 标题 + 右侧计数 / 价格 + 箭头。
class EntryRow extends StatelessWidget {
  const EntryRow({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    this.value,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: 10),
          child: Row(
            children: [
              EntryIcon(icon: icon, color: color),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Text(title,
                    style: AppType.body.copyWith(color: AppColors.textPrimary)),
              ),
              if (value != null)
                Text(value!,
                    style: AppType.caption.copyWith(
                        color: AppColors.textTertiary,
                        fontFamilyFallback: AppType.numericFallback)),
              const SizedBox(width: AppSpace.xs),
              Icon(Icons.chevron_right_rounded,
                  size: 20, color: AppColors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}
