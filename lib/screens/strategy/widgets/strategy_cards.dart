import 'package:flutter/material.dart';

import '../../../models/strategy_snapshot.dart';
import '../../../theme/app_theme.dart';

// ── 共用小工具 ──────────────────────────────────────────────────────────

/// 金额格式化：¥50,457.94（负数带负号）。
String money(double v, {int digits = 2}) {
  final neg = v < 0;
  final parts = v.abs().toStringAsFixed(digits).split('.');
  final intPart = parts[0];
  final buf = StringBuffer();
  for (var i = 0; i < intPart.length; i++) {
    if (i > 0 && (intPart.length - i) % 3 == 0) buf.write(',');
    buf.write(intPart[i]);
  }
  final dec = parts.length > 1 ? '.${parts[1]}' : '';
  return '${neg ? '-' : ''}¥$buf$dec';
}

String pct(double v, {int digits = 2}) =>
    '${v >= 0 ? '+' : ''}${(v * 100).toStringAsFixed(digits)}%';

/// 涨跌/盈亏配色：中国惯例，红涨绿跌。
Color pnlColor(double v) {
  if (v > 0) return AppColors.positive;
  if (v < 0) return AppColors.negative;
  return AppColors.textSecondary;
}

/// 所有卡片共用的容器样式。
class StrategyCard extends StatelessWidget {
  const StrategyCard({
    super.key,
    required this.title,
    this.trailing,
    required this.children,
  });

  final String title;
  final Widget? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderDim),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
              const Spacer(),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

/// 一行「标签 + 数值」。
class StatRow extends StatelessWidget {
  const StatRow(this.label, this.value, {super.key, this.valueColor, this.hint});

  final String label;
  final String value;
  final Color? valueColor;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Text(label,
              style: TextStyle(
                  color: AppColors.textSecondary, fontSize: 12.5)),
          if (hint != null) ...[
            const SizedBox(width: 4),
            Text(hint!,
                style: TextStyle(
                    color: AppColors.textTertiary, fontSize: 10.5)),
          ],
          const Spacer(),
          Text(value,
              style: TextStyle(
                color: valueColor ?? AppColors.textPrimary,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              )),
        ],
      ),
    );
  }
}

// ── 数据过期横幅 ────────────────────────────────────────────────────────

/// 策略唯一的「可执行输出」是调仓指令，一旦过期就可能让人按旧名单下单，
/// 所以过期必须显眼，不能只藏在角落。
class StaleBanner extends StatelessWidget {
  const StaleBanner({super.key, required this.dataAsOf, required this.staleDays});

  final String dataAsOf;
  final int staleDays;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.55)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, size: 16, color: AppColors.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '数据截至 $dataAsOf，已落后 $staleDays 个交易日。\n'
              '下面的调仓指令可能已经过期，请先确认最新一期信号再操作。',
              style: TextStyle(
                  color: AppColors.textPrimary, fontSize: 11.5, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 头部：策略身份 ──────────────────────────────────────────────────────

class StrategyHeaderCard extends StatelessWidget {
  const StrategyHeaderCard({
    super.key,
    required this.meta,
    required this.dataAsOf,
  });

  final StrategyMeta meta;
  final String dataAsOf;

  @override
  Widget build(BuildContext context) {
    return StrategyCard(
      title: '主策略',
      trailing: _dataBadge(),
      children: [
        Text(
          meta.name,
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 19,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          meta.subtitle,
          style: TextStyle(
              color: AppColors.textSecondary, fontSize: 12, height: 1.6),
        ),
      ],
    );
  }

  Widget _dataBadge() {
    if (dataAsOf.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.bgRaised,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderDim),
      ),
      child: Text(
        '数据截至 $dataAsOf',
        style: TextStyle(color: AppColors.textSecondary, fontSize: 10.5),
      ),
    );
  }
}

// ── 本期要不要动手 ──────────────────────────────────────────────────────

class ActionCard extends StatelessWidget {
  const ActionCard({
    super.key,
    required this.action,
    this.onTapTarget,
    this.onAskAI,
  });

  final StrategyAction action;

  /// 点某只标的 → 带着策略上下文去问 AI。
  final void Function(StrategyTarget target)? onTapTarget;

  /// 点「让 AI 核对这份策略」→ 整体级别的提问。
  final VoidCallback? onAskAI;

  @override
  Widget build(BuildContext context) {
    return StrategyCard(
      title: '本期要不要动手',
      trailing: action.execDate.isEmpty
          ? null
          : Text(
              '${action.execDate} 开盘执行',
              style: TextStyle(
                  color: AppColors.textTertiary, fontSize: 10.5),
            ),
      children: [
        if (_isExecToday()) _execTodayBanner(),
        _statusLine(),
        if (action.signalDate.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            '信号日 ${action.signalDate}',
            style: TextStyle(
                color: AppColors.textTertiary, fontSize: 10.5),
          ),
        ],
        const SizedBox(height: 12),
        Text('本期目标名单',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 11.5)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [for (final t in action.target) _targetChip(t)],
        ),
        if (action.changed && (action.added.isNotEmpty || action.removed.isNotEmpty))
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: _changes(),
          ),
        if (action.orders.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text('调仓清单',
              style:
                  TextStyle(color: AppColors.textSecondary, fontSize: 11.5)),
          const SizedBox(height: 6),
          for (final o in action.orders) _orderRow(o),
        ],
        if (action.note.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            action.note,
            style: TextStyle(
                color: AppColors.textTertiary, fontSize: 11, height: 1.5),
          ),
        ],
        if (onAskAI != null) ...[
          const SizedBox(height: 12),
          _AskButton(
            label: '让 AI 核对这份策略',
            onTap: onAskAI!,
          ),
        ],
      ],
    );
  }

  Widget _statusLine() {
    if (action.target.isEmpty) {
      return Text('暂无目标名单',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 15));
    }
    final need = action.changed;
    return Row(
      children: [
        Icon(
          need ? Icons.swap_horiz : Icons.check_circle_outline,
          size: 20,
          color: need ? AppColors.amber : AppColors.negative,
        ),
        const SizedBox(width: 8),
        Text(
          need ? '需要调仓' : '本期无需调仓',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  /// 执行日当天给一条醒目提示：这是整个 App 里唯一"今天必须做点什么"的时刻。
  bool _isExecToday() {
    if (action.execDate.isEmpty) return false;
    final bj = DateTime.now().toUtc().add(const Duration(hours: 8));
    final today = '${bj.year}-${bj.month.toString().padLeft(2, '0')}'
        '-${bj.day.toString().padLeft(2, '0')}';
    return action.execDate == today;
  }

  Widget _execTodayBanner() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.amber.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.amber.withValues(alpha: 0.6)),
        ),
        child: Row(
          children: [
            const Icon(Icons.today, size: 15, color: AppColors.amber),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                action.changed
                    ? '今天开盘执行本期调仓，清单见下方'
                    : '今天是执行日，但本期名单未变，不需要操作',
                style: TextStyle(
                    color: AppColors.textPrimary, fontSize: 11.5, height: 1.4),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _targetChip(StrategyTarget t) {
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.bgRaised,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderDim),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            t.name.isEmpty ? t.code : t.name,
            style: TextStyle(color: AppColors.textPrimary, fontSize: 12),
          ),
          if (onTapTarget != null) ...[
            const SizedBox(width: 4),
            Icon(Icons.north_east, size: 11, color: AppColors.textTertiary),
          ],
        ],
      ),
    );
    if (onTapTarget == null) return chip;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => onTapTarget!(t),
      child: chip,
    );
  }

  Widget _changes() {
    Widget line(String label, List<StrategyTarget> items, Color color) {
      if (items.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: RichText(
          text: TextSpan(
            style: const TextStyle(fontSize: 11.5, height: 1.5),
            children: [
              TextSpan(
                  text: '$label ',
                  style: TextStyle(color: AppColors.textSecondary)),
              TextSpan(
                text: items
                    .map((t) => t.name.isEmpty ? t.code : t.name)
                    .join('、'),
                style: TextStyle(color: color),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        line('新进', action.added, AppColors.positive),
        line('剔除', action.removed, AppColors.negative),
      ],
    );
  }

  Widget _orderRow(StrategyOrder o) {
    final color = o.isBuy ? AppColors.positive : AppColors.negative;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(o.isBuy ? '买' : '卖',
                style: TextStyle(color: color, fontSize: 10.5)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              o.name.isEmpty ? o.code : o.name,
              style: TextStyle(
                  color: AppColors.textPrimary, fontSize: 12.5),
            ),
          ),
          Text(
            '${o.shares} 股 @ ${o.price.toStringAsFixed(2)}',
            style: TextStyle(
                color: AppColors.textSecondary, fontSize: 11.5),
          ),
          const SizedBox(width: 10),
          Text(money(o.amount),
              style: TextStyle(
                  color: AppColors.textPrimary, fontSize: 11.5)),
        ],
      ),
    );
  }
}

// ── 实盘 ────────────────────────────────────────────────────────────────

class LiveCard extends StatelessWidget {
  const LiveCard({super.key, required this.live, this.onTapPosition});

  final StrategyLive live;

  /// 点持仓 → 带着成本价去问 AI。
  final void Function(StrategyPosition position)? onTapPosition;

  @override
  Widget build(BuildContext context) {
    final inception = live.inception.isEmpty ? '' : ' · ${live.inception} 起';
    return StrategyCard(
      title: '实盘账户',
      trailing: live.asOf.isEmpty
          ? null
          : Text('截至 ${live.asOf}',
              style: TextStyle(
                  color: AppColors.textTertiary, fontSize: 10.5)),
      children: [
        Text(
          '本金 ${money(live.capital, digits: 0)}$inception',
          style: TextStyle(
              color: AppColors.textTertiary, fontSize: 10.5),
        ),
        if (live.divergence) ...[
          const SizedBox(height: 8),
          const _DivergenceHint(),
        ],
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              money(live.total),
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 24,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(width: 10),
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                '${money(live.pnl)}（${pct(live.pnlPct)}）',
                style: TextStyle(
                  color: pnlColor(live.pnl),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        StatRow('持仓市值', money(live.marketValue)),
        StatRow('可用资金', money(live.cash)),
        StatRow('仓位', '${(live.positionPct * 100).toStringAsFixed(1)}%'),
        if (live.positions.isNotEmpty) ...[
          const SizedBox(height: 12),
          Divider(height: 1, color: AppColors.borderDim),
          const SizedBox(height: 8),
          for (final p in live.positions) _positionRow(p),
        ],
        const SizedBox(height: 10),
        Text(
          '已实现 ${money(live.realized)} · 累计费用 ${money(live.fees)}'
          '${live.dividends != 0 ? ' · 分红 ${money(live.dividends)}' : ''}',
          style: TextStyle(
              color: AppColors.textTertiary, fontSize: 10.5, height: 1.5),
        ),
      ],
    );
  }

  Widget _positionRow(StrategyPosition p) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(p.name.isEmpty ? p.code : p.name,
                        style: TextStyle(
                            color: AppColors.textPrimary, fontSize: 12.5)),
                    if (!p.inTarget) ...[
                      const SizedBox(width: 6),
                      const Text('非本期名单',
                          style: TextStyle(
                              color: AppColors.warning, fontSize: 9.5)),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${p.shares} 股 · 成本 ${p.avgCost.toStringAsFixed(2)}'
                  ' → ${p.price.toStringAsFixed(2)}',
                  style: TextStyle(
                      color: AppColors.textTertiary, fontSize: 10.5),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(money(p.marketValue),
                  style: TextStyle(
                      color: AppColors.textPrimary, fontSize: 12.5)),
              const SizedBox(height: 2),
              Text(pct(p.pnlPct),
                  style: TextStyle(color: pnlColor(p.pnl), fontSize: 11)),
            ],
          ),
        ],
      ),
    );
    if (onTapPosition == null) return row;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => onTapPosition!(p),
      child: row,
    );
  }
}

/// 卡片底部的「问 AI」按钮：样式统一，避免各卡片各写一套。
class _AskButton extends StatelessWidget {
  const _AskButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.amber.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.auto_awesome, size: 14, color: AppColors.amber),
              const SizedBox(width: 6),
              Text(label,
                  style: const TextStyle(color: AppColors.amber, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}

class _DivergenceHint extends StatelessWidget {
  const _DivergenceHint();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 14, color: AppColors.warning),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '实盘持仓与本期目标名单不一致，说明中间人工调过仓',
              style: TextStyle(
                  color: AppColors.textPrimary, fontSize: 10.5, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
