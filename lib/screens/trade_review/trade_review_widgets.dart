import 'package:flutter/material.dart';

import '../../models/trade_review.dart';
import '../../theme/app_theme.dart';

Color tradeResultColor(double value) {
  if (value > 0.000001) return AppColors.positive;
  if (value < -0.000001) return AppColors.negative;
  return AppColors.textPrimary;
}

String formatTradeMoney(double value, {String currency = 'CNY'}) {
  final sign = value > 0
      ? '+'
      : value < 0
          ? '-'
          : '';
  final symbol = switch (currency) {
    'HKD' => 'HK\$',
    'USD' => '\$',
    _ => '¥',
  };
  final amount = value.abs() >= 1000
      ? _thousands(value.abs(), 2)
      : value.abs().toStringAsFixed(2);
  return '$sign$symbol$amount';
}

String formatTradeAmount(double value, {String currency = 'CNY'}) {
  final symbol = switch (currency) {
    'HKD' => 'HK\$',
    'USD' => '\$',
    _ => '¥',
  };
  return '$symbol${_thousands(value.abs(), 2)}';
}

String _thousands(double value, int digits) {
  final fixed = value.toStringAsFixed(digits);
  final parts = fixed.split('.');
  final whole = parts.first;
  final buffer = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) buffer.write(',');
    buffer.write(whole[i]);
  }
  return parts.length == 1 ? buffer.toString() : '$buffer.${parts.last}';
}

String formatTradePercent(double value) =>
    '${(value * 100).toStringAsFixed(1)}%';

String formatProfitLossRatio(double value) =>
    value.isFinite ? '${value.toStringAsFixed(2)} : 1' : '∞ : 1';

String formatTradeDate(DateTime date) =>
    '${date.year}.${date.month.toString().padLeft(2, '0')}.'
    '${date.day.toString().padLeft(2, '0')}';

String formatTradeMinute(DateTime date) =>
    '${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')} '
    '${date.hour.toString().padLeft(2, '0')}:'
    '${date.minute.toString().padLeft(2, '0')}';

String formatHoldingHours(double hours) {
  if (hours <= 0) return '不到 1 小时';
  if (hours < 24) return '${hours.toStringAsFixed(1)} 小时';
  return '${(hours / 24).toStringAsFixed(1)} 天';
}

class TradeSectionTitle extends StatelessWidget {
  const TradeSectionTitle({
    super.key,
    required this.title,
    this.caption,
    this.trailing,
  });

  final String title;
  final String? caption;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.lg,
        AppSpace.xl,
        AppSpace.lg,
        AppSpace.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppType.title.copyWith(
                    fontSize: 18,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (caption != null) ...[
                  const SizedBox(height: AppSpace.xs),
                  Text(
                    caption!,
                    style: AppType.caption.copyWith(
                      color: AppColors.textSecondary,
                      height: 1.55,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class TradeInsightList extends StatelessWidget {
  const TradeInsightList({
    super.key,
    required this.items,
    required this.emptyText,
    required this.icon,
    required this.tone,
  });

  final List<TradeInsight> items;
  final String emptyText;
  final IconData icon;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Container(
        color: AppColors.bgSurface,
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Text(
          emptyText,
          style: AppType.body.copyWith(color: AppColors.textSecondary),
        ),
      );
    }
    return ColoredBox(
      color: AppColors.bgSurface,
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            _InsightBlock(item: items[i], icon: icon, tone: tone),
            if (i != items.length - 1)
              Divider(
                height: 1,
                thickness: 0.5,
                indent: AppSpace.lg + 36,
                color: AppColors.borderDim,
              ),
          ],
        ],
      ),
    );
  }
}

class _InsightBlock extends StatelessWidget {
  const _InsightBlock({
    required this.item,
    required this.icon,
    required this.tone,
  });

  final TradeInsight item;
  final IconData icon;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpace.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: tone.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: Icon(icon, size: 20, color: tone),
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: AppType.body.copyWith(
                    fontWeight: FontWeight.w600,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: AppSpace.sm),
                Text(
                  item.body,
                  style: AppType.caption.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.7,
                  ),
                ),
                if (item.evidence.isNotEmpty) ...[
                  const SizedBox(height: AppSpace.md),
                  for (final line in item.evidence)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpace.xs),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 4,
                            height: 4,
                            margin: const EdgeInsets.only(top: 7, right: 7),
                            decoration: BoxDecoration(
                              color: tone.withValues(alpha: 0.72),
                              shape: BoxShape.circle,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              line,
                              style: AppType.micro.copyWith(
                                color: AppColors.textSecondary,
                                height: 1.55,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
