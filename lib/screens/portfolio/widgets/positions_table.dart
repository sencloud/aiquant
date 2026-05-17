import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/china_market.dart';
import '../../../models/portfolio.dart';
import '../../../state/portfolio_state.dart';
import '../../../theme/app_theme.dart';

/// 移动端持仓列表：以"品种名称 + 代码"为主标识，侧栏显示数量、市值、
/// 盈亏百分比。横向不滚动，避免被屏幕宽度截断。
class PositionsTable extends StatefulWidget {
  const PositionsTable({super.key, required this.holdings, this.title = '持仓'});

  final List<PortfolioAsset> holdings;
  final String title;

  @override
  State<PositionsTable> createState() => _PositionsTableState();
}

enum _SortKey { weight, pnlPct, dayPct, name }

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
        case _SortKey.weight:
          return a.marketValue.compareTo(b.marketValue);
        case _SortKey.pnlPct:
          return a.unrealizedPnlPercent.compareTo(b.unrealizedPnlPercent);
        case _SortKey.dayPct:
          return (a.dayChangePercent ?? 0).compareTo(b.dayChangePercent ?? 0);
        case _SortKey.name:
          return a.name.compareTo(b.name);
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
    final qfmt = NumberFormat('#,##0.##');

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _headerRow(),
            const SizedBox(height: 6),
            _columnLabels(),
            Divider(height: 1, color: AppColors.borderDim),
            for (final h in _sorted)
              _row(h, total: total, fmt: fmt, qfmt: qfmt),
          ],
        ),
      ),
    );
  }

  Widget _headerRow() {
    return Row(
      children: [
        Text(widget.title,
            style: const TextStyle(
                color: AppColors.amber,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8)),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
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
        const Spacer(),
        // 排序快捷按钮
        _sortChip('权重', _SortKey.weight),
        const SizedBox(width: 4),
        _sortChip('盈亏', _SortKey.pnlPct),
        const SizedBox(width: 4),
        _sortChip('涨跌', _SortKey.dayPct),
      ],
    );
  }

  Widget _sortChip(String label, _SortKey k) {
    final active = _key == k;
    return InkWell(
      onTap: () => _toggle(k),
      borderRadius: BorderRadius.circular(3),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          border: Border.all(
              color: active ? AppColors.amber : AppColors.borderDim),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: TextStyle(
                    color: active ? AppColors.amber : AppColors.textTertiary,
                    fontSize: 10,
                    fontWeight: FontWeight.w700)),
            if (active)
              Icon(_desc ? Icons.arrow_drop_down : Icons.arrow_drop_up,
                  size: 12, color: AppColors.amber),
          ],
        ),
      ),
    );
  }

  Widget _columnLabels() {
    final s = TextStyle(
        color: AppColors.textTertiary,
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.4);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(flex: 32, child: Text('品种', style: s)),
          Expanded(
            flex: 22,
            child: Text('持仓 / 最新',
                textAlign: TextAlign.right, style: s),
          ),
          Expanded(
            flex: 24,
            child: Text('市值', textAlign: TextAlign.right, style: s),
          ),
          Expanded(
            flex: 22,
            child: Text('盈亏%', textAlign: TextAlign.right, style: s),
          ),
        ],
      ),
    );
  }

  Widget _row(PortfolioAsset h,
      {required double total,
      required NumberFormat fmt,
      required NumberFormat qfmt}) {
    final shortCode = ChinaMarket.displaySymbol(h.symbol);
    final unit = ChinaMarket.quantityUnit(h.assetClass, symbol: h.symbol);
    final weight = total <= 0 ? 0.0 : h.marketValue / total * 100;
    final pnlPct = h.unrealizedPnlPercent;
    final pnlColor = pnlPct > 0
        ? AppColors.positive
        : (pnlPct < 0 ? AppColors.negative : AppColors.textPrimary);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.borderDim)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 32,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  h.name.isEmpty ? shortCode : h.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(shortCode,
                        style: TextStyle(
                            color: AppColors.textTertiary,
                            fontSize: 10,
                            fontFamily: 'monospace',
                            letterSpacing: 0.3)),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.bgBase,
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: Text(h.assetClass,
                          style: TextStyle(
                              color: AppColors.textTertiary, fontSize: 9)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            flex: 22,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${qfmt.format(h.quantity)} $unit',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 12,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  h.currentPrice == null
                      ? '--'
                      : fmt.format(h.currentPrice),
                  style: TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 10,
                      fontFamily: 'monospace'),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 24,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _fmtCny(h.marketValue),
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 12,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text('${weight.toStringAsFixed(1)}%',
                    style: TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 10,
                        fontFamily: 'monospace')),
              ],
            ),
          ),
          Expanded(
            flex: 22,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${pnlPct >= 0 ? '+' : ''}${pnlPct.toStringAsFixed(2)}%',
                  style: TextStyle(
                      color: pnlColor,
                      fontSize: 12,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  '${h.unrealizedPnl >= 0 ? '+' : '-'}${_fmtCny(h.unrealizedPnl.abs())}',
                  style: TextStyle(
                      color: pnlColor.withValues(alpha: 0.7),
                      fontSize: 10,
                      fontFamily: 'monospace'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 中国财经习惯：>= 1 亿 → "X.XX 亿"；>= 1 万 → "X.XX 万"。
  static String _fmtCny(double v) {
    final abs = v.abs();
    if (abs >= 1e8) return '${(v / 1e8).toStringAsFixed(2)} 亿';
    if (abs >= 1e4) return '${(v / 1e4).toStringAsFixed(2)} 万';
    return NumberFormat('#,##0.00').format(v);
  }
}
