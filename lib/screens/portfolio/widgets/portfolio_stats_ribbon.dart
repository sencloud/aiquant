import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../state/portfolio_state.dart';
import '../../../theme/app_theme.dart';

/// Hero stats row: market value, unrealized P&L, today's change.
class PortfolioStatsRibbon extends StatelessWidget {
  const PortfolioStatsRibbon({super.key});

  @override
  Widget build(BuildContext context) {
    final ps = context.watch<PortfolioState>();
    final s = ps.currentSummary;
    final cur = s?.portfolio.currency ?? 'CNY';

    return Container(
      height: 76,
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        border: Border(top: BorderSide(color: AppColors.borderDim)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _hero(
              label: '组合市值',
              value: _fmtMoney(s?.totalMarketValue),
              suffix: cur,
              valueSize: 16,
              valueColor: AppColors.textPrimary,
            ),
          ),
          _sep(),
          Expanded(
            child: _signedHero(
              label: '未实现盈亏',
              amount: s?.totalUnrealizedPnl ?? 0,
              percent: s?.totalUnrealizedPnlPercent ?? 0,
            ),
          ),
          _sep(),
          Expanded(
            child: _signedHero(
              label: '今日变化',
              amount: s?.totalDayChange ?? 0,
              percent: s?.totalDayChangePercent ?? 0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sep() => Container(
        width: 1,
        height: 56,
        color: AppColors.borderDim,
      );

  Widget _hero({
    required String label,
    required String value,
    String? suffix,
    double valueSize = 18,
    Color? valueColor,
    Widget? subtitle,
  }) {
    valueColor ??= AppColors.textPrimary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: TextStyle(
                fontSize: 10,
                color: AppColors.textTertiary,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6),
          ),
          const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: valueSize,
                    fontWeight: FontWeight.w800,
                    color: valueColor,
                  ),
                ),
              ),
              if (suffix != null) ...[
                const SizedBox(width: 4),
                Text(
                  suffix,
                  style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textTertiary,
                      fontWeight: FontWeight.w700),
                ),
              ]
            ],
          ),
          if (subtitle != null) ...[const SizedBox(height: 2), subtitle],
        ],
      ),
    );
  }

  Widget _signedHero({
    required String label,
    required double amount,
    required double percent,
  }) {
    final color = amount > 0
        ? AppColors.positive
        : (amount < 0 ? AppColors.negative : AppColors.textPrimary);
    return _hero(
      label: label,
      value: _fmtSignedMoney(amount),
      valueSize: 15,
      valueColor: color,
      subtitle: Text(
        '${amount >= 0 ? "▲" : "▼"} ${percent.toStringAsFixed(2)}%',
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  static String _fmtMoney(double? v) {
    if (v == null) return '--';
    return _fmtCny(v);
  }

  static String _fmtSignedMoney(double v) {
    final sign = v > 0 ? '+' : (v < 0 ? '-' : '');
    return '$sign${_fmtCny(v.abs())}';
  }

  /// 中国财经 App 习惯：>= 1 亿 → "X.XX 亿"；>= 1 万 → "X.XX 万"；
  /// 否则按千分位显示（最多两位小数）。这样 Hero 区不会出现 264,123.45
  /// 之类被截断为 "264,12..." 的尴尬情况。
  static String _fmtCny(double v) {
    final abs = v.abs();
    if (abs >= 1e8) {
      return '${(v / 1e8).toStringAsFixed(2)} 亿';
    }
    if (abs >= 1e4) {
      return '${(v / 1e4).toStringAsFixed(2)} 万';
    }
    return NumberFormat('#,##0.00').format(v);
  }
}
