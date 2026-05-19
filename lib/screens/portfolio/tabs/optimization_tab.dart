import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/portfolio.dart';
import '../../../state/portfolio_state.dart';
import '../../../theme/app_theme.dart';
import '../../assistant/assistant_screen.dart';

/// "优化 / Optimization" tab.
///
/// 功能（v2）:
///  1. 顶部两个动作卡：「解套策略」「止盈计划」—— 跳到 AI 助理 + 携带组合
///     上下文，让模型针对下一交易日给出可执行步骤。
///  2. 权重对比卡：每个标的渲染「当前 vs 建议（反向波动）」双进度条 + Δ
///     差值徽章；底部"AI 给我优化建议"按钮直接走助理对话。
///  3. 简短说明卡：解释"建议权重"的来源以及和服务端模型的关系。
///
/// 注：仍然是纯客户端启发式，建议权重 = 反向波动 (1/|σ|+0.5) 归一化；与
/// 真正的协方差优化拉开差距，但作为"是否过度集中 + 是否欠配防守标的"的
/// 直觉提示足够直观。深度优化交给 AI 对话。
class OptimizationTab extends StatelessWidget {
  const OptimizationTab({super.key});

  @override
  Widget build(BuildContext context) {
    final ps = context.watch<PortfolioState>();
    final s = ps.currentSummary;
    if (s == null || s.holdings.isEmpty) {
      return const _Empty('加入品种后这里会展示组合权重的优化建议。');
    }
    final suggested = _inverseVolWeights(s.holdings);
    final current = _currentWeights(s);

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _ActionCard(summary: s),
        const SizedBox(height: 12),
        _WeightCompareCard(
          summary: s,
          current: current,
          suggested: suggested,
        ),
        const SizedBox(height: 12),
        _ExplainCard(),
      ],
    );
  }

  Map<String, double> _inverseVolWeights(List<PortfolioAsset> holdings) {
    final invs = <String, double>{};
    for (final h in holdings) {
      final sigma = (h.dayChangePercent ?? 1.5).abs();
      invs[h.symbol] = 1.0 / (sigma + 0.5);
    }
    final total = invs.values.fold<double>(0, (sum, v) => sum + v);
    if (total == 0) {
      final n = holdings.length;
      if (n == 0) return const {};
      final w = 100.0 / n;
      return {for (final h in holdings) h.symbol: w};
    }
    return {
      for (final e in invs.entries) e.key: e.value / total * 100,
    };
  }

  Map<String, double> _currentWeights(PortfolioSummary s) {
    if (s.totalMarketValue <= 0) return const {};
    return {
      for (final h in s.holdings) h.symbol: h.marketValue / s.totalMarketValue * 100,
    };
  }
}

/// 跳到 AI 助理并自动发送一条预设 prompt + 携带当前组合上下文。
///
/// 抽公共逻辑：解套/止盈/权重三个按钮共用，仅 prompt 不同。
void _askAssistant(BuildContext context, String prompt) {
  // HomeScreen 把 4 个 tab 放在 IndexedStack 里，没有公开 setIndex；
  // 这里直接 push 一个新的 AssistantScreen 实例，最直接、不引入跨 tab 控制。
  // 进入新页面时通过 launch 参数自动塞 prompt + 自动发送 + 携带组合。
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => AssistantScreen(
      launch: AssistantLaunch(
        initialMessage: prompt,
        attachPortfolio: true,
        autoSend: true,
      ),
    ),
  ));
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({required this.summary});
  final PortfolioSummary summary;

  @override
  Widget build(BuildContext context) {
    final losers = summary.holdings.where((h) => h.unrealizedPnl < 0).length;
    final gainers = summary.holdings.where((h) => h.unrealizedPnl > 0).length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _Title('AI 实战建议'),
            const SizedBox(height: 4),
            Text(
              '基于当前组合 ${summary.holdings.length} 只标的（亏损 $losers · 盈利 $gainers），'
              '让助理生成下一交易日的可执行计划。',
              style: TextStyle(
                  color: AppColors.textSecondary, fontSize: 11, height: 1.5),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _ActionTile(
                    icon: Icons.healing_outlined,
                    color: AppColors.danger,
                    title: '解套策略',
                    subtitle: '亏损头寸下一交易日操作',
                    enabled: losers > 0,
                    onTap: () => _askAssistant(
                      context,
                      _kUnstuckPrompt,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ActionTile(
                    icon: Icons.flag_outlined,
                    color: AppColors.positive,
                    title: '止盈计划',
                    subtitle: '盈利头寸分批兑现节奏',
                    enabled: gainers > 0,
                    onTap: () => _askAssistant(
                      context,
                      _kTakeProfitPrompt,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onTap,
  });
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: enabled
          ? color.withValues(alpha: 0.10)
          : AppColors.bgRaised.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: enabled
                  ? color.withValues(alpha: 0.40)
                  : AppColors.borderDim,
            ),
          ),
          child: Row(
            children: [
              Icon(icon,
                  color:
                      enabled ? color : AppColors.textTertiary, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: enabled ? color : AppColors.textTertiary,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios,
                  size: 11,
                  color:
                      enabled ? color : AppColors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

class _WeightCompareCard extends StatelessWidget {
  const _WeightCompareCard({
    required this.summary,
    required this.current,
    required this.suggested,
  });
  final PortfolioSummary summary;
  final Map<String, double> current;
  final Map<String, double> suggested;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _Title('权重对比（当前 vs 建议）'),
            const SizedBox(height: 6),
            Row(
              children: [
                const _LegendDot(color: AppColors.amber, text: '当前'),
                const SizedBox(width: 12),
                const _LegendDot(color: AppColors.info, text: '建议（反向波动）'),
                const Spacer(),
                Text('Δ = 建议 - 当前',
                    style: TextStyle(
                        color: AppColors.textTertiary, fontSize: 10)),
              ],
            ),
            const SizedBox(height: 6),
            for (final h in summary.holdings)
              _WeightRow(
                label: '${h.symbol}  ${h.name}',
                current: current[h.symbol] ?? 0,
                suggested: suggested[h.symbol] ?? 0,
              ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.auto_awesome, size: 14),
                label: const Text('让 AI 出权重优化建议'),
                onPressed: () => _askAssistant(context, _kRebalancePrompt),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WeightRow extends StatelessWidget {
  const _WeightRow({
    required this.label,
    required this.current,
    required this.suggested,
  });
  final String label;
  final double current;
  final double suggested;

  @override
  Widget build(BuildContext context) {
    final delta = suggested - current;
    final deltaColor = delta.abs() < 0.5
        ? AppColors.textTertiary
        : delta > 0
            ? AppColors.positive
            : AppColors.danger;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: AppColors.textPrimary, fontSize: 11),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: deltaColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(2)}%',
                  style: TextStyle(
                    color: deltaColor,
                    fontFamily: 'monospace',
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          _DualBar(current: current, suggested: suggested),
        ],
      ),
    );
  }
}

/// 双进度条：上 = 当前权重（金黄），下 = 建议权重（蓝），同一基准 50%
/// 满槽，避免某一只权重很小时条几乎看不见。
class _DualBar extends StatelessWidget {
  const _DualBar({required this.current, required this.suggested});
  final double current;
  final double suggested;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _bar(current, AppColors.amber, '当前 ${current.toStringAsFixed(2)}%'),
        const SizedBox(height: 3),
        _bar(suggested, AppColors.info, '建议 ${suggested.toStringAsFixed(2)}%'),
      ],
    );
  }

  Widget _bar(double pct, Color color, String label) {
    final clamped = pct.clamp(0, 50) / 50.0;
    return Stack(
      children: [
        Container(
          height: 14,
          decoration: BoxDecoration(
            color: AppColors.bgRaised,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        FractionallySizedBox(
          widthFactor: clamped.toDouble(),
          child: Container(
            height: 14,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
        Positioned(
          left: 6,
          top: 0,
          bottom: 0,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.text});
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(text,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 10)),
      ],
    );
  }
}

class _ExplainCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _Title('说明'),
            const SizedBox(height: 8),
            Text(
              '· 客户端给出的「建议权重」用 1/|σ| 反向波动近似，'
              '把波动小的标的权重抬升，对冲集中度风险。\n'
              '· 真正的 Markowitz / Black-Litterman 等方法依赖历史协方差，'
              '建议在助理对话中要求 AI 结合行业、相关性、宏观环境给出实操建议。\n'
              '· 「解套策略」「止盈计划」按钮会自动把当前组合发给助理，'
              '建议在交易日开盘前查看，明确补仓点 / 止盈位 / 仓位调整方向。',
              style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                  height: 1.6),
            ),
          ],
        ),
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
          color: AppColors.amber,
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6));
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
            padding: const EdgeInsets.all(28),
            child: Text(text,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 12))),
      );
}

// ── prompts ────────────────────────────────────────────────────────────

const _kUnstuckPrompt = '''
请基于已附带的当前组合，针对所有亏损（盈亏 < 0）的头寸，给出"下一交易日"的解套策略。
要求：
1. 按亏损金额从大到小逐一标的分析；
2. 每只输出：成本/现价/跌幅、原因（结合行业 + 财报/新闻关键词，必要时调用 search 工具）、
   下一交易日具体动作（继续持有 / 分批补仓位价 / 止损价 / 换股标的及理由）；
3. 末尾给一份"开盘前 60 分钟操作清单"（最多 5 条），可执行、有时间节点。
不要鸡汤、不要免责声明，输出简体中文 markdown。''';

const _kTakeProfitPrompt = '''
请基于已附带的当前组合，针对所有盈利（盈亏 > 0）的头寸，给出"下一交易日"的止盈计划。
要求：
1. 每只输出：成本/现价/盈利幅度、当前位置在区间中的位置（必要时调用 K 线/技术指标工具）、
   止盈节奏（一次性 / 分批：触发价 + 比例）、是否换仓到防守标的；
2. 区分"短期获利兑现"与"长期持有但锁定 N% 浮盈"两种节奏，给出明确的卖出价和数量；
3. 末尾输出"未来 5 个交易日的检查清单"（按日列出关键价位 / 公告日期）。
不要鸡汤、不要免责声明，输出简体中文 markdown。''';

const _kRebalancePrompt = '''
请基于已附带的当前组合，给出权重再平衡建议。
要求：
1. 先指出"过度集中 / 单一行业占比过高"的风险点（按权重 + 行业聚类）；
2. 然后给出 3 套可选目标权重方案：
   A. 防守型：偏向低波动 + 高股息；
   B. 进攻型：偏向当前景气度高的行业龙头；
   C. 平衡型：等权 + 行业上限；
3. 每套方案输出每只标的的目标权重 %、相对当前的增减 %、可执行的"加仓 / 减仓"具体股数（按 100 股取整）；
4. 给出执行顺序（先卖什么、后买什么），避免单边占用现金。
输出简体中文 markdown。''';
