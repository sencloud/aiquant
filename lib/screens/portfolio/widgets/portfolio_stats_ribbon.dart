import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../models/portfolio.dart';
import '../../../state/portfolio_state.dart';
import '../../../theme/app_theme.dart';

/// Hero stats row: market value, unrealized P&L, today's change, positions.
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
            flex: 26,
            child: _hero(
              label: '组合市值',
              value: _fmtMoney(s?.totalMarketValue),
              suffix: cur,
              valueSize: 18,
              valueColor: AppColors.textPrimary,
            ),
          ),
          _sep(),
          Expanded(
            flex: 22,
            child: _signedHero(
              label: '未实现盈亏',
              amount: s?.totalUnrealizedPnl ?? 0,
              percent: s?.totalUnrealizedPnlPercent ?? 0,
            ),
          ),
          _sep(),
          Expanded(
            flex: 22,
            child: _signedHero(
              label: '今日变化',
              amount: s?.totalDayChange ?? 0,
              percent: s?.totalDayChangePercent ?? 0,
            ),
          ),
          _sep(),
          Expanded(
            flex: 30,
            child: _stats(s),
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
      valueSize: 16,
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

  Widget _stats(PortfolioSummary? s) {
    final n = s?.positions ?? 0;
    final g = s?.gainers ?? 0;
    final l = s?.losers ?? 0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '持仓',
            style: TextStyle(
                fontSize: 10,
                color: AppColors.textTertiary,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 10,
            runSpacing: 4,
            children: [
              _chip('共 $n 只', AppColors.amber),
              _chip('涨 $g', AppColors.positive),
              _chip('跌 $l', AppColors.negative),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          border: Border.all(color: color),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(
          text,
          style: TextStyle(
              color: color, fontSize: 10, fontWeight: FontWeight.w700),
        ),
      );

  static String _fmtMoney(double? v) {
    if (v == null) return '--';
    return NumberFormat('#,##0.00').format(v);
  }

  static String _fmtSignedMoney(double v) {
    final f = NumberFormat('#,##0.00').format(v.abs());
    final sign = v > 0 ? '+' : (v < 0 ? '-' : '');
    return '$sign$f';
  }
}
