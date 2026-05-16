import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../state/portfolio_state.dart';
import '../../../theme/app_theme.dart';

/// "交易" tab — full ledger of buys / sells / dividends for the active
/// portfolio. Mirrors PortfolioTxnPanel from the Qt app (with delete).
class TransactionsTab extends StatelessWidget {
  const TransactionsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final ps = context.watch<PortfolioState>();
    final txns = ps.currentTransactions();
    if (txns.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('当前组合还没有交易记录。',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        ),
      );
    }
    final df = DateFormat('yyyy-MM-dd');
    final fmt = NumberFormat('#,##0.00');

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: txns.length,
      separatorBuilder: (_, __) =>
          Divider(height: 1, color: AppColors.borderDim),
      itemBuilder: (_, i) {
        final t = txns[i];
        final color = _typeColor(t.type);
        return Dismissible(
          key: ValueKey(t.id),
          background: Container(
            alignment: Alignment.centerRight,
            color: AppColors.negative,
            padding: const EdgeInsets.only(right: 16),
            child: const Icon(Icons.delete_outline, color: Colors.white),
          ),
          direction: DismissDirection.endToStart,
          confirmDismiss: (_) async {
            return await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('删除交易记录'),
                    content: const Text('确定要删除这条交易吗？'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('取消'),
                      ),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.negative),
                        child: const Text('删除'),
                      ),
                    ],
                  ),
                ) ??
                false;
          },
          onDismissed: (_) => ps.deleteTransaction(t.id),
          child: ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            leading: Container(
              width: 38,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border.all(color: color),
                borderRadius: BorderRadius.circular(2),
              ),
              child: Text(_typeLabel(t.type),
                  style: TextStyle(
                      color: color,
                      fontSize: 10,
                      fontWeight: FontWeight.w800)),
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    '${t.symbol}  ${t.name}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700),
                  ),
                ),
                Text(df.format(t.date),
                    style: TextStyle(
                        color: AppColors.textTertiary, fontSize: 11)),
              ],
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                children: [
                  Text(
                      '${fmt.format(t.quantity)} × ${fmt.format(t.price)} = ${fmt.format(t.totalValue)}',
                      style: TextStyle(
                          color: AppColors.textSecondary,
                          fontFamily: 'monospace',
                          fontSize: 11)),
                  if (t.notes.isNotEmpty)
                    Expanded(
                      child: Text('  · ${t.notes}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: AppColors.textTertiary, fontSize: 10)),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static String _typeLabel(String t) {
    switch (t) {
      case 'buy':
        return '买入';
      case 'sell':
        return '卖出';
      case 'dividend':
        return '分红';
      default:
        return t.toUpperCase();
    }
  }

  static Color _typeColor(String t) {
    switch (t) {
      case 'buy':
        return AppColors.positive;
      case 'sell':
        return AppColors.negative;
      case 'dividend':
        return AppColors.amber;
      default:
        return AppColors.textSecondary;
    }
  }
}
