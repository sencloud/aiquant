import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../services/backtest/etf_short_term.dart';
import '../../../theme/app_theme.dart';

/// 短线策略的交易明细表：日期 / 标的 / 操作 / 份额 / 价格 / 手续费。
///
/// 买入类（买入/补仓）琥珀色，卖出类（止损/到期/动量转负/期末平仓）
/// 按盈亏语义着色——由于明细行没有持仓成本快照，颜色只区分买卖方向：
/// 买入 = 琥珀，卖出 = 红色（卖出即兑现，A 股红涨习惯）。
class TradeLog extends StatelessWidget {
  const TradeLog({super.key, required this.result});

  final ShortTermResult result;

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('yyyy-MM-dd');
    final money = NumberFormat('#,##0.00');
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderDim),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(children: [
              const Text('交易明细',
                  style: TextStyle(
                      color: AppColors.amber,
                      fontSize: 12,
                      fontWeight: FontWeight.w800)),
              const SizedBox(width: 10),
              Text('${result.trades.length} 笔',
                  style: TextStyle(
                      color: AppColors.textTertiary, fontSize: 10.5)),
              const Spacer(),
              Text(
                '期初 ${money.format(result.initialCapital)} → '
                '期末 ${money.format(result.finalEquity)}',
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 11),
              ),
            ]),
          ),
          Divider(height: 1, color: AppColors.borderDim),
          // 表头
          Container(
            color: AppColors.bgRaised,
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 8),
            child: Row(children: [
              Expanded(
                  flex: 3,
                  child: _th('日期')),
              Expanded(
                  flex: 2,
                  child: _th('标的')),
              Expanded(
                  flex: 2,
                  child: _th('操作')),
              Expanded(
                  flex: 2,
                  child: _tr2('份额')),
              Expanded(
                  flex: 2,
                  child: _tr2('价格')),
              Expanded(
                  flex: 2,
                  child: _tr2('手续费')),
            ]),
          ),
          for (final t in result.trades)
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 7),
              decoration: BoxDecoration(
                border: Border(
                    bottom: BorderSide(color: AppColors.borderDim)),
              ),
              child: Row(children: [
                Expanded(
                    flex: 3,
                    child: Text(fmt.format(t.date),
                        style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11.5))),
                Expanded(
                    flex: 2,
                    child: Text(t.symbol,
                        style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600))),
                Expanded(
                    flex: 2,
                    child: Text(t.action,
                        style: TextStyle(
                            color: _actionColor(t.action),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600))),
                Expanded(
                    flex: 2,
                    child: _tdr('${t.shares}')),
                Expanded(
                    flex: 2,
                    child: _tdr(t.price.toStringAsFixed(3))),
                Expanded(
                    flex: 2,
                    child: _tdr(t.fee.toStringAsFixed(2))),
              ]),
            ),
        ],
      ),
    );
  }

  Color _actionColor(String action) {
    if (action == '买入' || action == '补仓') return AppColors.amber;
    return AppColors.positive; // 卖出 = 兑现（红）
  }

  Widget _th(String s) => Text(s,
      style: TextStyle(
          color: AppColors.textTertiary,
          fontSize: 10.5,
          fontWeight: FontWeight.w600));

  Widget _tr2(String s) => Text(s,
      textAlign: TextAlign.right,
      style: TextStyle(
          color: AppColors.textTertiary,
          fontSize: 10.5,
          fontWeight: FontWeight.w600));

  Widget _tdr(String s) => Text(s,
      textAlign: TextAlign.right,
      style: TextStyle(
          color: AppColors.textSecondary, fontSize: 11.5));
}
