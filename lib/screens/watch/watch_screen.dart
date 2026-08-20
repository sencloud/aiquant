import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/watchlist_state.dart';
import '../../theme/app_theme.dart';
import 'symbol_detail_screen.dart';
import 'watch_add_dialog.dart';

/// 看盘首页 — 我关注的品种列表（类似主流股票软件的"自选"页）。
/// 点击品种行 → 进入品种详情（K 线 + 常见问题）。
class WatchScreen extends StatefulWidget {
  const WatchScreen({super.key});

  @override
  State<WatchScreen> createState() => _WatchScreenState();
}

class _WatchScreenState extends State<WatchScreen> {
  @override
  void initState() {
    super.initState();
    // 首次进入即拉一次最新行情（内部幂等，重复调用成本低）。
    Future.microtask(() {
      if (mounted) context.read<WatchlistState>().refreshQuotes();
    });
  }

  Future<void> _openAddDialog() async {
    await showDialog<void>(
      context: context,
      builder: (_) => const WatchAddDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wl = context.watch<WatchlistState>();
    final items = wl.items;

    return Scaffold(
      appBar: AppBar(
        title: const Text('看盘'),
        actions: [
          IconButton(
            tooltip: '刷新行情',
            icon: const Icon(Icons.refresh, size: 18),
            onPressed: wl.loading ? null : () => wl.refreshQuotes(),
          ),
          IconButton(
            tooltip: '添加品种',
            icon: const Icon(Icons.add, size: 20),
            onPressed: _openAddDialog,
          ),
        ],
      ),
      body: items.isEmpty
          ? _emptyView()
          : RefreshIndicator(
              color: AppColors.amber,
              onRefresh: () => wl.refreshQuotes(),
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: items.length,
                separatorBuilder: (_, __) =>
                    Divider(height: 1, color: AppColors.borderDim),
                itemBuilder: (_, i) => _WatchRow(item: items[i]),
              ),
            ),
    );
  }

  /// 空列表引导：说明 + 大按钮引导添加第一批关注品种。
  Widget _emptyView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.candlestick_chart_outlined,
              size: 44, color: AppColors.textTertiary),
          const SizedBox(height: 12),
          Text('还没有关注的品种',
              style: TextStyle(
                  color: AppColors.textSecondary, fontSize: 13)),
          const SizedBox(height: 4),
          Text('添加股票、ETF、期货、指数开始看盘',
              style: TextStyle(
                  color: AppColors.textTertiary, fontSize: 11)),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _openAddDialog,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('添加品种'),
          ),
        ],
      ),
    );
  }
}

/// 单个自选行：名称+代码 / 最新价+涨跌幅。
/// 涨跌颜色遵循 A 股惯例：涨红跌绿（positive=红 / negative=绿）。
class _WatchRow extends StatelessWidget {
  const _WatchRow({required this.item});
  final WatchItem item;

  @override
  Widget build(BuildContext context) {
    final wl = context.watch<WatchlistState>();
    final q = wl.quoteOf(item.tsCode);
    final pct = q?.pctChg;
    final up = (pct ?? 0) > 0;
    final down = (pct ?? 0) < 0;
    final color = up
        ? AppColors.positive
        : down
            ? AppColors.negative
            : AppColors.textPrimary;

    return Dismissible(
      key: ValueKey(item.tsCode),
      // 右滑删除：自选列表的标准交互。
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: AppColors.danger,
        child:
            const Icon(Icons.delete_outline, color: Colors.white, size: 20),
      ),
      onDismissed: (_) => wl.remove(item.tsCode),
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => SymbolDetailScreen(item: item),
        )),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            item.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            border:
                                Border.all(color: AppColors.borderDim),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            item.assetClass,
                            style: TextStyle(
                                color: AppColors.textTertiary,
                                fontSize: 9),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.tsCode,
                      style: TextStyle(
                          color: AppColors.textTertiary,
                          fontSize: 11,
                          fontFamily: 'monospace'),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    q == null ? '--' : _fmtPrice(q.close),
                    style: TextStyle(
                      color: q == null ? AppColors.textTertiary : color,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    pct == null ? '--' : '${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(2)}%',
                    style: TextStyle(
                      color: pct == null ? AppColors.textTertiary : color,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 价格展示：按数量级决定小数位（期货常见 3 位小数）。
  static String _fmtPrice(double v) {
    if (v >= 10000) return v.toStringAsFixed(0);
    if (v >= 100) return v.toStringAsFixed(2);
    return v.toStringAsFixed(2);
  }
}
