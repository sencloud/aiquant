import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../state/portfolio_state.dart';
import '../../../theme/app_theme.dart';

/// "规划" tab — quick goal-based what-if planner. The user enters a target
/// horizon and an annual return assumption; we project the current market
/// value forward at compound interest. Lightweight version of PlanningView.
class PlanningTab extends StatefulWidget {
  const PlanningTab({super.key});

  @override
  State<PlanningTab> createState() => _PlanningTabState();
}

class _PlanningTabState extends State<PlanningTab> {
  double _annualReturn = 8;
  double _years = 10;
  double _monthlyContrib = 1000;

  @override
  Widget build(BuildContext context) {
    final ps = context.watch<PortfolioState>();
    final s = ps.currentSummary;
    if (s == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text('选择一个组合后即可使用规划工具。',
              style: TextStyle(color: AppColors.textSecondary)),
        ),
      );
    }
    final fmt = NumberFormat('#,##0.00');
    final start = s.totalMarketValue;
    final monthlyRate = math.pow(1 + _annualReturn / 100, 1 / 12) - 1;
    final months = (_years * 12).round();
    double future = start;
    for (int i = 0; i < months; i++) {
      future = future * (1 + monthlyRate) + _monthlyContrib;
    }
    final contrib = _monthlyContrib * months;
    final earned = future - start - contrib;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _T('未来值规划'),
                const SizedBox(height: 8),
                _slider('年化收益率假设',
                    '${_annualReturn.toStringAsFixed(1)}%',
                    _annualReturn, -10, 30, 80, (v) {
                  setState(() => _annualReturn = v);
                }),
                _slider('投资期限', '${_years.toStringAsFixed(0)} 年',
                    _years, 1, 40, 39, (v) {
                  setState(() => _years = v);
                }),
                _slider(
                    '每月新增投入',
                    '${fmt.format(_monthlyContrib)} ${s.portfolio.currency}',
                    _monthlyContrib, 0, 50000, 100, (v) {
                  setState(() => _monthlyContrib = v);
                }),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _T('预测结果'),
                const SizedBox(height: 8),
                _row('当前市值', fmt.format(start), s.portfolio.currency),
                _row('累计追加投入', fmt.format(contrib), s.portfolio.currency),
                _row('累计收益', fmt.format(earned), s.portfolio.currency,
                    color: earned >= 0 ? AppColors.positive : AppColors.negative),
                Divider(color: AppColors.borderDim, height: 24),
                _row('${_years.toStringAsFixed(0)} 年后价值',
                    fmt.format(future), s.portfolio.currency,
                    big: true),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _T('提示'),
                const SizedBox(height: 6),
                Text(
                    '· 此处为简化的复利模拟，未考虑税费、汇率与黑天鹅事件；\n'
                    '· 用作长期投资规划参考，实际收益受市场波动影响很大。',
                    style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                        height: 1.6)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _slider(String label, String value, double v, double min,
      double max, int divisions, ValueChanged<double> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                  child: Text(label,
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 11))),
              Text(value,
                  style: const TextStyle(
                      color: AppColors.amber,
                      fontWeight: FontWeight.w800,
                      fontSize: 12)),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: AppColors.amber,
              inactiveTrackColor: AppColors.borderDim,
              thumbColor: AppColors.amber,
              overlayColor: AppColors.amber.withValues(alpha: 0.15),
              trackHeight: 2.5,
            ),
            child: Slider(
                value: v,
                min: min,
                max: max,
                divisions: divisions,
                onChanged: onChanged),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value, String suffix,
      {bool big = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Text(label,
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 12)),
          ),
          Text(value,
              style: TextStyle(
                  color: color ?? AppColors.textPrimary,
                  fontFamily: 'monospace',
                  fontSize: big ? 18 : 13,
                  fontWeight: FontWeight.w800)),
          const SizedBox(width: 4),
          Text(suffix,
              style: TextStyle(
                  color: AppColors.textTertiary, fontSize: 11)),
        ],
      ),
    );
  }
}

class _T extends StatelessWidget {
  const _T(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
          color: AppColors.amber,
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6));
}
