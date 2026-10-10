import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/falsification.dart';
import '../../theme/app_theme.dart';
import '../../widgets/wk_kit.dart';

/// 一条证伪记录的详情。
///
/// 一页读完：结论 → 关键数字 → 分年 → 为什么失败 → 怎么复现。
/// 「为什么失败」是本页的重点：alpha-radar 的经验是，最有价值的产出是
/// 「什么不行、为什么不行」，而不是一条好看的曲线。
class FalsificationDetailScreen extends StatelessWidget {
  const FalsificationDetailScreen({super.key, required this.entry});

  final ArchiveEntry entry;

  Color get _tone => switch (entry.verdict) {
        'reject' => AppColors.danger,
        'pending' => AppColors.warning,
        _ => AppColors.textSecondary,
      };

  @override
  Widget build(BuildContext context) {
    return WkPage(
      title: entry.strategy,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSpace.gutter, AppSpace.lg, AppSpace.gutter, AppSpace.xxl),
        children: [
          Row(
            children: [
              WkTag(entry.verdictLabel, tone: _tone, filled: true),
              const SizedBox(width: AppSpace.sm),
              WkTag(entry.family),
              const Spacer(),
              Text('${entry.symbol} · ${_freqLabel(entry.freq)}',
                  style: AppType.micro.copyWith(
                      color: AppColors.textTertiary,
                      fontFamilyFallback: AppType.numericFallback)),
            ],
          ),
          const SizedBox(height: AppSpace.lg),
          Text(entry.headline,
              style: AppType.display.copyWith(
                  fontSize: 22, height: 1.5, color: AppColors.textPrimary)),
          if (entry.source.isNotEmpty) ...[
            const SizedBox(height: AppSpace.md),
            Text('策略出处：${entry.source}',
                style: AppType.caption.copyWith(color: AppColors.textTertiary)),
          ],
          const SizedBox(height: AppSpace.lg),
          _MetricsGrid(metrics: entry.metrics),
          if (entry.yearly.isNotEmpty) ...[
            const SizedBox(height: AppSpace.lg),
            _YearlyCard(title: '分年盈亏', points: entry.yearly),
          ],
          const SizedBox(height: AppSpace.lg),
          WkGroup(
            header: '为什么是这个结论',
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpace.lg),
                child: Text(entry.mechanism,
                    style: AppType.read
                        .copyWith(color: AppColors.textSecondary)),
              ),
            ],
          ),
          if (entry.command.isNotEmpty) ...[
            const SizedBox(height: AppSpace.lg),
            _CommandCard(command: entry.command),
          ],
          const SizedBox(height: AppSpace.lg),
          const WkNote(
            title: '口径',
            text: '含成本回测：期货每边 1 跳滑点 + 双边手续费；A 股佣金 + 卖出'
                '印花税 + 最低 5 元，并强制 T+1。分年结果是必报项 —— 只报总收益'
                '的策略在这里一律不算数。',
          ),
        ],
      ),
    );
  }

  static String _freqLabel(String f) =>
      f == '1d' ? '日线' : f.replaceAll('min', ' 分');
}

/// 关键数字。四格排一行，窄屏自动换成两行。
class _MetricsGrid extends StatelessWidget {
  const _MetricsGrid({required this.metrics});

  final ArchiveMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final cells = <Widget>[
      WkStat(
        value: metrics.trades == 0 ? '—' : '${metrics.trades}',
        label: '笔数',
      ),
      WkStat(
        value: metrics.pf == 0 ? '—' : metrics.pf.toStringAsFixed(3),
        label: 'PF 盈利因子',
        color: metrics.pf > 1 ? AppColors.positive : AppColors.negative,
      ),
      WkStat(
        value: metrics.avgPoints == 0
            ? '—'
            : '${metrics.avgPoints > 0 ? '+' : ''}'
                '${metrics.avgPoints.toStringAsFixed(2)}',
        label: '每手均点（含成本）',
        color: metrics.avgPoints >= 0
            ? AppColors.positive
            : AppColors.negative,
      ),
      WkStat(
        value: metrics.years == 0
            ? '—'
            : '${metrics.positiveYears}/${metrics.years}',
        label: '正年数',
        color: metrics.years > 0 && metrics.positiveYears * 2 >= metrics.years
            ? AppColors.positive
            : AppColors.negative,
      ),
    ];
    return WkGroup(
      header: '关键数字',
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: LayoutBuilder(
            builder: (context, box) {
              // 固定两列：四个数挤在一行时，「1.050」这类五位数字会顶到格宽
              // 边界并折行，读起来像坏了。手机上两列本来就是更舒服的读法。
              const cols = 2;
              return Wrap(
                spacing: AppSpace.lg,
                runSpacing: AppSpace.lg,
                children: [
                  for (final c in cells)
                    SizedBox(
                        width: (box.maxWidth - AppSpace.lg * (cols - 1)) / cols,
                        child: c),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

/// 分年柱：正红负绿（A 股惯例），长度按绝对值归一。
class _YearlyCard extends StatelessWidget {
  const _YearlyCard({required this.title, required this.points});

  final String title;
  final List<YearPnl> points;

  @override
  Widget build(BuildContext context) {
    final maxAbs = points.fold<double>(
        0, (m, p) => p.pnl.abs() > m ? p.pnl.abs() : m);
    final denom = maxAbs <= 0 ? 1.0 : maxAbs;

    return WkGroup(
      header: title,
      footer: '只看总收益没有意义：本工程的「有效」几乎全部来自单一年份。',
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: Column(
            children: [
              for (final p in points)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpace.sm),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 42,
                        child: Text(p.year,
                            style: AppType.caption.copyWith(
                                color: AppColors.textSecondary,
                                fontFamilyFallback: AppType.numericFallback)),
                      ),
                      Expanded(
                        child: ClipRRect(
                          borderRadius:
                              BorderRadius.circular(AppRadius.pill),
                          child: Container(
                            height: 12,
                            color: AppColors.bgRaised,
                            child: FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor:
                                  (p.pnl.abs() / denom).clamp(0.02, 1.0),
                              child: Container(
                                color: p.pnl >= 0
                                    ? AppColors.positive
                                    : AppColors.negative,
                              ),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 84,
                        child: Text(
                          '${p.pnl >= 0 ? '+' : '−'}'
                          '${p.pnl.abs().toStringAsFixed(0)}',
                          textAlign: TextAlign.right,
                          style: AppType.caption.copyWith(
                            color: p.pnl >= 0
                                ? AppColors.positive
                                : AppColors.negative,
                            fontFamilyFallback: AppType.numericFallback,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 可复现命令。能一条命令跑回来的结论，才值得相信。
class _CommandCard extends StatelessWidget {
  const _CommandCard({required this.command});

  final String command;

  @override
  Widget build(BuildContext context) {
    return WkGroup(
      header: '怎么复现',
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpace.md),
                decoration: BoxDecoration(
                  color: AppColors.bgRaised,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: SelectableText(
                  command,
                  style: AppType.caption.copyWith(
                    color: AppColors.textPrimary,
                    height: 1.6,
                    fontFamilyFallback: AppType.numericFallback,
                  ),
                ),
              ),
              const SizedBox(height: AppSpace.sm),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: command));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('命令已复制')),
                    );
                  },
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  label: const Text('复制命令'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

