import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../models/portfolio.dart';
import '../../../state/portfolio_state.dart';
import '../../../theme/app_theme.dart';

class PositionsTable extends StatefulWidget {
  const PositionsTable({super.key, required this.holdings, this.title = 'POSITIONS'});

  final List<PortfolioAsset> holdings;
  final String title;

  @override
  State<PositionsTable> createState() => _PositionsTableState();
}

enum _SortKey { symbol, qty, price, marketValue, pnl, pnlPct, dayPct, weight }

class _PositionsTableState extends State<PositionsTable> {
  _SortKey _key = _SortKey.weight;
  bool _desc = true;

  void _toggle(_SortKey k) {
    setState(() {
      if (_key == k) {
        _desc = !_desc;
      } else {
        _key = k;
        _desc = true;
      }
    });
  }

  List<PortfolioAsset> get _sorted {
    final list = [...widget.holdings];
    int cmp(PortfolioAsset a, PortfolioAsset b) {
      switch (_key) {
        case _SortKey.symbol:
          return a.symbol.compareTo(b.symbol);
        case _SortKey.qty:
          return a.quantity.compareTo(b.quantity);
        case _SortKey.price:
          return (a.currentPrice ?? a.avgBuyPrice)
              .compareTo(b.currentPrice ?? b.avgBuyPrice);
        case _SortKey.marketValue:
          return a.marketValue.compareTo(b.marketValue);
        case _SortKey.pnl:
          return a.unrealizedPnl.compareTo(b.unrealizedPnl);
        case _SortKey.pnlPct:
          return a.unrealizedPnlPercent.compareTo(b.unrealizedPnlPercent);
        case _SortKey.dayPct:
          return (a.dayChangePercent ?? 0).compareTo(b.dayChangePercent ?? 0);
        case _SortKey.weight:
          return a.marketValue.compareTo(b.marketValue);
      }
    }

    list.sort((a, b) => _desc ? cmp(b, a) : cmp(a, b));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final ps = context.read<PortfolioState>();
    final total = ps.currentSummary?.totalMarketValue ?? 0;
    final fmt = NumberFormat('#,##0.00');

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(widget.title,
                    style: const TextStyle(
                        color: AppColors.amber,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.borderDim),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Text('${widget.holdings.length}',
                      style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 10,
                          fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: MediaQuery.of(context).size.width - 56,
                ),
                child: DataTable(
                  headingRowHeight: 30,
                  dataRowMinHeight: 32,
                  dataRowMaxHeight: 38,
                  columnSpacing: 16,
                  horizontalMargin: 0,
                  headingTextStyle: TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5),
                  dataTextStyle: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 11,
                      fontFamily: 'monospace'),
                  columns: [
                    _col('代码', _SortKey.symbol),
                    _col('数量', _SortKey.qty, numeric: true),
                    _col('最新', _SortKey.price, numeric: true),
                    _col('均价', null, numeric: true),
                    _col('市值', _SortKey.marketValue, numeric: true),
                    _col('盈亏', _SortKey.pnl, numeric: true),
                    _col('盈亏%', _SortKey.pnlPct, numeric: true),
                    _col('涨跌%', _SortKey.dayPct, numeric: true),
                    _col('权重', _SortKey.weight, numeric: true),
                  ],
                  rows: [
                    for (final h in _sorted)
                      DataRow(cells: [
                        DataCell(Tooltip(
                          message: h.name,
                          child: Text(h.symbol,
                              style: const TextStyle(color: AppColors.amber)),
                        )),
                        DataCell(Text(fmt.format(h.quantity))),
                        DataCell(Text(h.currentPrice == null
                            ? '--'
                            : fmt.format(h.currentPrice))),
                        DataCell(Text(fmt.format(h.avgBuyPrice))),
                        DataCell(Text(fmt.format(h.marketValue))),
                        DataCell(_signed(h.unrealizedPnl, fmt)),
                        DataCell(_signedPct(h.unrealizedPnlPercent)),
                        DataCell(h.dayChangePercent == null
                            ? Text('--',
                                style: TextStyle(color: AppColors.textTertiary))
                            : _signedPct(h.dayChangePercent!)),
                        DataCell(Text(total <= 0
                            ? '--'
                            : '${(h.marketValue / total * 100).toStringAsFixed(1)}%')),
                      ]),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  DataColumn _col(String label, _SortKey? key,
      {bool numeric = false}) {
    final clickable = key != null;
    return DataColumn(
      numeric: numeric,
      label: GestureDetector(
        onTap: clickable ? () => _toggle(key) : null,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label),
            if (clickable && _key == key)
              Icon(_desc ? Icons.arrow_drop_down : Icons.arrow_drop_up,
                  size: 14, color: AppColors.amber),
          ],
        ),
      ),
    );
  }

  Widget _signed(double v, NumberFormat fmt) {
    final color = v > 0
        ? AppColors.positive
        : (v < 0 ? AppColors.negative : AppColors.textPrimary);
    final sign = v > 0 ? '+' : (v < 0 ? '-' : '');
    return Text('$sign${fmt.format(v.abs())}',
        style: TextStyle(color: color));
  }

  Widget _signedPct(double v) {
    final color = v > 0
        ? AppColors.positive
        : (v < 0 ? AppColors.negative : AppColors.textPrimary);
    final sign = v > 0 ? '+' : (v < 0 ? '' : '');
    return Text('$sign${v.toStringAsFixed(2)}%',
        style: TextStyle(color: color));
  }
}
