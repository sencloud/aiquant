import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/instrument.dart';
import '../../services/tushare_service.dart';
import '../../state/watchlist_state.dart';
import '../../theme/app_theme.dart';

enum _AssetTab { stock, etf, future, indexInstrument }

/// 看盘页「添加关注品种」对话框。
/// 结构参考组合页的 InstrumentPickerDialog，但为自选场景精简：
/// 无需填写数量，勾选即加入自选。
class WatchAddDialog extends StatefulWidget {
  const WatchAddDialog({super.key});

  @override
  State<WatchAddDialog> createState() => _WatchAddDialogState();
}

class _WatchAddDialogState extends State<WatchAddDialog> {
  final _service = TushareService();
  final _query = TextEditingController();

  _AssetTab _tab = _AssetTab.stock;

  // 每个 tab 独立缓存，切换不重复请求。
  final Map<_AssetTab, List<Instrument>> _cache = {};
  final Map<_AssetTab, String?> _errors = {};
  final Map<_AssetTab, bool> _loading = {};

  // 交易所筛选
  String? _exchange; // 股票：SSE / SZSE / BSE
  String? _futExchange = 'CFFEX'; // 期货
  String? _indexMarket = 'SSE'; // 指数
  String _etfMarket = 'E'; // ETF：E 场内 / O 场外

  static const _stockExchanges = ['SSE', 'SZSE', 'BSE'];
  static const _futureExchanges = [
    'CFFEX', 'SHFE', 'INE', 'DCE', 'CZCE', 'GFEX',
  ];
  static const _indexMarkets = ['SSE', 'SZSE', 'CSI', 'OTH'];

  @override
  void initState() {
    super.initState();
    _loadCurrent();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _loadCurrent({bool force = false}) async {
    final tab = _tab;
    if (!force && _cache[tab] != null) return;
    setState(() {
      _loading[tab] = true;
      _errors[tab] = null;
    });
    try {
      List<Instrument> list;
      switch (tab) {
        case _AssetTab.stock:
          list = await _service.stockBasic(exchange: _exchange);
          break;
        case _AssetTab.etf:
          list = await _service.fundBasic(market: _etfMarket);
          break;
        case _AssetTab.future:
          list = await _service.futBasic(exchange: _futExchange ?? 'CFFEX');
          break;
        case _AssetTab.indexInstrument:
          list = await _service.indexBasic(market: _indexMarket ?? 'SSE');
          break;
      }
      setState(() {
        _cache[tab] = list;
        _loading[tab] = false;
      });
    } on TushareException catch (e) {
      setState(() {
        _errors[tab] = e.message;
        _loading[tab] = false;
      });
    } catch (e) {
      setState(() {
        _errors[tab] = e.toString();
        _loading[tab] = false;
      });
    }
  }

  /// 当前 tab + 关键词过滤后的可见列表。
  List<Instrument> get _visible {
    final list = _cache[_tab] ?? const <Instrument>[];
    final q = _query.text.trim().toLowerCase();
    return [
      for (final ins in list)
        if (q.isEmpty ||
            ins.tsCode.toLowerCase().contains(q) ||
            ins.name.toLowerCase().contains(q) ||
            ins.industry.toLowerCase().contains(q))
          ins,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final wl = context.read<WatchlistState>();
    return Dialog(
      backgroundColor: AppColors.bgSurface,
      insetPadding: const EdgeInsets.all(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 700),
        child: Column(
          children: [
            _header(),
            Divider(height: 1, color: AppColors.borderDim),
            _tabRow(),
            _searchRow(),
            Divider(height: 1, color: AppColors.borderDim),
            Expanded(child: _list(wl)),
            _footer(),
          ],
        ),
      ),
    );
  }

  Widget _header() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
        child: Row(
          children: [
            const Expanded(
              child: Text('添加关注品种',
                  style: TextStyle(
                      color: AppColors.amber,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6)),
            ),
            IconButton(
              icon: Icon(Icons.close,
                  color: AppColors.textTertiary, size: 18),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      );

  Widget _tabRow() {
    return Container(
      color: AppColors.bgRaised,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          _tabButton(_AssetTab.stock, '股票'),
          _tabButton(_AssetTab.etf, 'ETF'),
          _tabButton(_AssetTab.future, '期货'),
          _tabButton(_AssetTab.indexInstrument, '指数'),
          const Spacer(),
          IconButton(
            tooltip: '重新拉取',
            icon: const Icon(Icons.refresh, size: 16),
            onPressed: () => _loadCurrent(force: true),
          ),
        ],
      ),
    );
  }

  Widget _tabButton(_AssetTab t, String label) {
    final selected = _tab == t;
    return GestureDetector(
      onTap: () {
        setState(() => _tab = t);
        _loadCurrent();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? AppColors.amber : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppColors.amber : AppColors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  /// 搜索框 + 交易所筛选下拉。
  Widget _searchRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        children: [
          TextField(
            controller: _query,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: '搜索代码、名称或行业…',
              prefixIcon: Icon(Icons.search,
                  color: AppColors.textTertiary, size: 18),
              suffixIcon: _query.text.isEmpty
                  ? null
                  : IconButton(
                      icon: Icon(Icons.clear,
                          size: 16, color: AppColors.textTertiary),
                      onPressed: () => setState(() => _query.clear()),
                    ),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 32,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: _filterChips(),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _filterChips() {
    switch (_tab) {
      case _AssetTab.stock:
        return [
          _dropdown<String?>(
            label: '交易所',
            value: _exchange,
            options: const <String?>[null, ..._stockExchanges],
            display: (v) => v ?? '全部',
            onChanged: (v) {
              setState(() => _exchange = v);
              _loadCurrent(force: true);
            },
          ),
        ];
      case _AssetTab.etf:
        return [
          _dropdown<String>(
            label: '市场',
            value: _etfMarket,
            options: const ['E', 'O'],
            display: (v) => v == 'E' ? '场内' : '场外',
            onChanged: (v) {
              setState(() => _etfMarket = v ?? 'E');
              _loadCurrent(force: true);
            },
          ),
        ];
      case _AssetTab.future:
        return [
          _dropdown<String>(
            label: '交易所',
            value: _futExchange,
            options: _futureExchanges,
            display: (v) => v ?? '',
            onChanged: (v) {
              setState(() => _futExchange = v);
              _loadCurrent(force: true);
            },
          ),
        ];
      case _AssetTab.indexInstrument:
        return [
          _dropdown<String>(
            label: '市场',
            value: _indexMarket,
            options: _indexMarkets,
            display: (v) => v ?? '',
            onChanged: (v) {
              setState(() => _indexMarket = v);
              _loadCurrent(force: true);
            },
          ),
        ];
    }
  }

  Widget _dropdown<T>({
    required String label,
    required T? value,
    required List<T?> options,
    required String Function(T? v) display,
    required ValueChanged<T?> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.borderDim),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Row(
          children: [
            Text('$label：',
                style: TextStyle(
                    color: AppColors.textTertiary, fontSize: 11)),
            DropdownButtonHideUnderline(
              child: DropdownButton<T?>(
                value: value,
                dropdownColor: AppColors.bgRaised,
                isDense: true,
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700),
                items: [
                  for (final o in options)
                    DropdownMenuItem<T?>(
                      value: o,
                      child: Text(display(o)),
                    ),
                ],
                onChanged: onChanged,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _list(WatchlistState wl) {
    final loading = _loading[_tab] ?? false;
    if (loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    final err = _errors[_tab];
    if (err != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline,
                  color: AppColors.danger, size: 36),
              const SizedBox(height: 12),
              Text(err,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: AppColors.textSecondary, fontSize: 12)),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => _loadCurrent(force: true),
                icon: const Icon(Icons.refresh, size: 14),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    final list = _visible;
    if (list.isEmpty) {
      return Center(
        child: Text('没有找到匹配的品种',
            style:
                TextStyle(color: AppColors.textTertiary, fontSize: 12)),
      );
    }
    return ListView.separated(
      itemCount: list.length,
      separatorBuilder: (_, __) =>
          Divider(height: 1, color: AppColors.borderDim),
      itemBuilder: (_, i) {
        final ins = list[i];
        final added = wl.contains(ins.tsCode);
        return ListTile(
          dense: true,
          title: Row(
            children: [
              Expanded(
                child: Text(ins.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 8),
              Text(ins.tsCode,
                  style: const TextStyle(
                      color: AppColors.amber,
                      fontSize: 11,
                      fontFamily: 'monospace')),
            ],
          ),
          subtitle: ins.industry.isEmpty
              ? null
              : Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(ins.industry,
                      style: TextStyle(
                          color: AppColors.textTertiary, fontSize: 10)),
                ),
          trailing: TextButton(
            onPressed: added
                ? null
                : () {
                    // 加入自选后按钮变为"已添加"，可继续勾选其它品种。
                    context.read<WatchlistState>().add(ins);
                  },
            child: Text(added ? '已添加' : '+ 关注'),
          ),
          onTap: added
              ? null
              : () {
                  context.read<WatchlistState>().add(ins);
                },
        );
      },
    );
  }

  Widget _footer() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.borderDim)),
        color: AppColors.bgSurface,
      ),
      child: Row(
        children: [
          const Spacer(),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('完成'),
          ),
        ],
      ),
    );
  }
}
