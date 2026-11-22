import 'package:flutter/material.dart';

import '../../models/trade_review.dart';
import '../../theme/app_theme.dart';
import '../../widgets/wk_kit.dart';
import 'trade_review_widgets.dart';

class TradeReportScreen extends StatelessWidget {
  const TradeReportScreen({
    super.key,
    required this.report,
  });

  final TradeReviewReport report;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: AppBar(
        title: const Text('交易复盘'),
        actions: [
          IconButton(
            key: const ValueKey('trade-report-close'),
            tooltip: '返回首页',
            onPressed: () {
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _Hero(report: report)),
            if (report.warnings.isNotEmpty)
              SliverToBoxAdapter(
                child: _WarningBlock(warnings: report.warnings),
              ),
            const SliverToBoxAdapter(
              child: TradeSectionTitle(
                title: '价格结果',
                caption: '只统计能与截图中的买入配对、已经形成闭环的卖出。',
              ),
            ),
            SliverToBoxAdapter(child: _Metrics(report: report)),
            const SliverToBoxAdapter(
              child: TradeSectionTitle(
                title: '你的交易逻辑',
                caption: '这些是成交行为呈现出的规律，不等同于你当时的主观意图。',
              ),
            ),
            SliverToBoxAdapter(
              child: TradeInsightList(
                items: report.logic,
                emptyText: '成交行不足，暂时无法归纳出稳定的交易逻辑。',
                icon: Icons.route_outlined,
                tone: AppColors.amber,
              ),
            ),
            const SliverToBoxAdapter(
              child: TradeSectionTitle(
                title: '交易中的问题',
                caption: '先看能由成交记录直接证明的问题，不推测截图之外的心理活动。',
              ),
            ),
            SliverToBoxAdapter(
              child: TradeInsightList(
                items: report.problems,
                emptyText: '当前样本没有识别出明显异常，但样本有限，不代表执行可靠。',
                icon: Icons.warning_amber_rounded,
                tone: AppColors.positive,
              ),
            ),
            const SliverToBoxAdapter(
              child: TradeSectionTitle(
                title: '下一步怎么改',
                caption: '从下一批交易就能执行的规则开始，不设置无法验证的目标。',
              ),
            ),
            SliverToBoxAdapter(
              child: TradeInsightList(
                items: report.improvements,
                emptyText: '先补充更完整的成交记录，再制定与样本匹配的改进规则。',
                icon: Icons.tips_and_updates_outlined,
                tone: AppColors.negative,
              ),
            ),
            const SliverToBoxAdapter(
              child: TradeSectionTitle(
                title: '复盘边界',
                caption: '把可证明的结论与交易意图分开，避免过度推断。',
              ),
            ),
            SliverToBoxAdapter(child: _Boundary(report: report)),
            const SliverToBoxAdapter(
              child: TradeSectionTitle(
                title: '成交明细',
                caption: '按发生时间排列。数据来自截图识别后的人工确认。',
              ),
            ),
            SliverToBoxAdapter(child: _TradeDetails(report: report)),
            const SliverToBoxAdapter(child: SizedBox(height: AppSpace.xxl)),
          ],
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.report});

  final TradeReviewReport report;

  @override
  Widget build(BuildContext context) {
    final pnl = report.metrics.realizedPnl;
    return Container(
      color: AppColors.bgSurface,
      padding: const EdgeInsets.fromLTRB(
        AppSpace.lg,
        AppSpace.xl,
        AppSpace.lg,
        AppSpace.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              WkTag(
                report.brokerHint.isEmpty ? '成交记录' : report.brokerHint,
                tone: AppColors.amber,
                filled: true,
              ),
              const Spacer(),
              Text(
                formatTradeDate(report.createdAt),
                style: AppType.micro.copyWith(color: AppColors.textTertiary),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.xl),
          Text(
            report.title,
            style: AppType.display.copyWith(
              fontSize: 23,
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
          const SizedBox(height: AppSpace.sm),
          Text(
            '${report.buyCount} 买 · ${report.sellCount} 卖 · '
            '${report.metrics.matchedSellCount} 笔已配对卖出',
            style: AppType.caption.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpace.xl),
          Text(
            '已实现盈亏',
            style: AppType.caption.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpace.xs),
          Text(
            formatTradeMoney(pnl, currency: report.currency),
            key: const ValueKey('trade-report-pnl'),
            style: AppType.display.copyWith(
              color: tradeResultColor(pnl),
              fontFamilyFallback: AppType.numericFallback,
              fontSize: 36,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.8,
            ),
          ),
          const SizedBox(height: AppSpace.sm),
          Text(
            report.metrics.matchedSellCount == 0
                ? '截图中还没有可配对的卖出，暂不计算已实现结果。'
                : '已扣除买卖两侧手续费；未平仓持仓的浮动盈亏不计入。',
            style: AppType.micro.copyWith(
              color: AppColors.textSecondary,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }
}

class _WarningBlock extends StatelessWidget {
  const _WarningBlock({required this.warnings});

  final List<String> warnings;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpace.md,
        AppSpace.md,
        AppSpace.md,
        0,
      ),
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F3EA),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 19,
            color: AppColors.amber,
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '读结论前先看这里',
                  style: AppType.caption.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpace.sm),
                for (final warning in warnings)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpace.xs),
                    child: Text(
                      '• $warning',
                      style: AppType.micro.copyWith(
                        color: AppColors.textSecondary,
                        height: 1.6,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Metrics extends StatelessWidget {
  const _Metrics({required this.report});

  final TradeReviewReport report;

  @override
  Widget build(BuildContext context) {
    final m = report.metrics;
    final items = [
      _MetricData(
        '胜率',
        formatTradePercent(m.winRate),
        '${m.winningSellCount} 胜 / ${m.losingSellCount} 负',
      ),
      _MetricData(
        '盈亏比',
        formatProfitLossRatio(m.profitLossRatio),
        '平均盈利 ÷ 平均亏损',
      ),
      _MetricData(
        '单笔期望',
        formatTradeMoney(m.expectancy, currency: report.currency),
        '每笔已配对卖出的平均结果',
        color: tradeResultColor(m.expectancy),
      ),
      _MetricData(
        '手续费',
        formatTradeAmount(m.totalFees, currency: report.currency),
        '买卖两侧合计',
      ),
      _MetricData(
        '平均持仓',
        formatHoldingHours(m.averageHoldingHours),
        '按成交数量加权',
      ),
      _MetricData(
        '换手金额',
        formatTradeAmount(m.turnover, currency: report.currency),
        '${m.tradingDayCount} 个交易日',
      ),
    ];
    return Container(
      color: AppColors.bgSurface,
      padding: const EdgeInsets.all(AppSpace.lg),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = (constraints.maxWidth - AppSpace.md) / 2;
          return Wrap(
            spacing: AppSpace.md,
            runSpacing: AppSpace.md,
            children: [
              for (final item in items)
                SizedBox(
                  width: width,
                  child: _MetricTile(data: item),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _MetricData {
  const _MetricData(
    this.label,
    this.value,
    this.caption, {
    this.color,
  });

  final String label;
  final String value;
  final String caption;
  final Color? color;
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.data});

  final _MetricData data;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 104),
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: AppColors.bgRaised,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            data.label,
            style: AppType.caption.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpace.sm),
          Text(
            data.value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppType.title.copyWith(
              color: data.color ?? AppColors.textPrimary,
              fontSize: 19,
              fontFamilyFallback: AppType.numericFallback,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpace.xs),
          Text(
            data.caption,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppType.micro.copyWith(
              color: AppColors.textTertiary,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _Boundary extends StatelessWidget {
  const _Boundary({required this.report});

  final TradeReviewReport report;

  @override
  Widget build(BuildContext context) {
    final m = report.metrics;
    return Container(
      color: AppColors.bgSurface,
      padding: const EdgeInsets.all(AppSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _BoundaryLine(
            label: '盈利交易持仓',
            value: formatHoldingHours(m.averageWinningHoldingHours),
          ),
          Divider(
            height: AppSpace.xl,
            thickness: 0.5,
            color: AppColors.borderDim,
          ),
          _BoundaryLine(
            label: '亏损交易持仓',
            value: formatHoldingHours(m.averageLosingHoldingHours),
          ),
          Divider(
            height: AppSpace.xl,
            thickness: 0.5,
            color: AppColors.borderDim,
          ),
          _BoundaryLine(
            label: '连续亏损',
            value: '${m.maxLossStreak} 笔',
          ),
          const SizedBox(height: AppSpace.lg),
          const WkNote(
            title: '无法从截图判断的部分',
            text: '截图不含账户总资金，因此不判断仓位比例；也不含单笔风险预算，'
                '因此不推断止损金额。截图之外的入场理由、消息来源、'
                '临场情绪和计划变更，都没有被当作事实。',
          ),
        ],
      ),
    );
  }
}

class _BoundaryLine extends StatelessWidget {
  const _BoundaryLine({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: AppType.body.copyWith(color: AppColors.textSecondary),
          ),
        ),
        Text(
          value,
          style: AppType.body.copyWith(
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _TradeDetails extends StatelessWidget {
  const _TradeDetails({required this.report});

  final TradeReviewReport report;

  @override
  Widget build(BuildContext context) {
    if (report.trades.isEmpty) {
      return const SizedBox(
        height: 160,
        child: WkEmpty(
          icon: Icons.receipt_long_outlined,
          title: '没有可展示的成交行',
          hint: '返回首页，重新上传一张包含日期、方向、数量和价格的成交截图。',
        ),
      );
    }
    return WkGroup(
      children: [
        for (final trade in report.trades)
          _TradeDetailRow(trade: trade, currency: report.currency),
      ],
    );
  }
}

class _TradeDetailRow extends StatelessWidget {
  const _TradeDetailRow({required this.trade, required this.currency});

  final ParsedTrade trade;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final tone =
        trade.side == TradeSide.buy ? AppColors.positive : AppColors.negative;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.lg,
        AppSpace.md,
        AppSpace.lg,
        AppSpace.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tone.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Text(
              trade.side.label,
              style: AppType.micro.copyWith(
                color: tone,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  trade.instrumentLabel,
                  style: AppType.body.copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: AppSpace.xs),
                Text(
                  '${formatTradeMinute(trade.occurredAt)} · '
                  '${_quantity(trade.quantity)} @ '
                  '${trade.price.toStringAsFixed(2)}',
                  style: AppType.micro.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.5,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          Text(
            trade.fee > 0
                ? '费 ${formatTradeAmount(trade.fee, currency: currency)}'
                : '无手续费',
            style: AppType.micro.copyWith(color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }

  static String _quantity(double value) {
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(2);
  }
}
