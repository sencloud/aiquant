import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/instrument.dart';
import '../../../services/tushare_service.dart';
import '../../../state/portfolio_state.dart';
import '../../../theme/app_theme.dart';
import 'asset_lot.dart';
import 'asset_quantity_dialog.dart';

enum _AssetTab { stock, etf, future, indexInstrument }

class InstrumentPickerDialog extends StatefulWidget {
  const InstrumentPickerDialog({super.key});

  @override
  State<InstrumentPickerDialog> createState() => _InstrumentPickerDialogState();
}

class _InstrumentPickerDialogState extends State<InstrumentPickerDialog> {
  final _service = TushareService();
  final _query = TextEditingController();

  _AssetTab _tab = _AssetTab.stock;

  // Per-tab cache so switching tabs doesn't refire the network call.
  final Map<_AssetTab, List<Instrument>> _cache = {};
  final Map<_AssetTab, String?> _errors = {};
  final Map<_AssetTab, bool> _loading = {};

  // Filters
  String? _exchange; // SSE / SZSE / BSE for stocks
  String? _industry;
  String? _futExchange = 'CFFEX'; // for futures
  String? _indexMarket = 'SSE'; // for indices
  String _etfMarket = 'E';

  final Set<String> _selected = {};
  static const _stockExchanges = ['SSE', 'SZSE', 'BSE'];
  static const _futureExchanges = [
    'CFFEX',
    'SHFE',
    'INE',
    'DCE',
    'CZCE',
    'GFEX'
  ];
  static const _indexMarkets = ['SSE', 'SZSE', 'CSI', 'OTH'];
  static const _etfMarkets = [
    ['E', '场内'],
    ['O', '场外'],
  ];

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

  List<Instrument> get _visible {
    final list = _cache[_tab] ?? const <Instrument>[];
    final q = _query.text.trim().toLowerCase();
    return [
      for (final ins in list)
        if ((q.isEmpty ||
                ins.tsCode.toLowerCase().contains(q) ||
                ins.name.toLowerCase().contains(q) ||
                ins.industry.toLowerCase().contains(q)) &&
            (_industry == null ||
                _industry!.isEmpty ||
                ins.industry == _industry))
          ins,
    ];
  }

  List<String> get _industries {
    final list = _cache[_tab] ?? const <Instrument>[];
    final s = <String>{};
    for (final i in list) {
      if (i.industry.isNotEmpty) s.add(i.industry);
    }
    return s.toList()..sort();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.bgSurface,
      insetPadding: const EdgeInsets.all(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 720),
        child: Column(
          children: [
            _header(),
            Divider(height: 1, color: AppColors.borderDim),
            _tabRow(),
            _filterRow(),
            Divider(height: 1, color: AppColors.borderDim),
            Expanded(child: _list()),
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
              child: Text('添加品种',
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
          _tabButton(_AssetTab.etf, 'ETF / 基金'),
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
        setState(() {
          _tab = t;
          _industry = null;
          _selected.clear();
        });
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

  Widget _filterRow() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      color: AppColors.bgSurface,
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
          _filterDropdown<String?>(
            label: '交易所',
            value: _exchange,
            options: const <String?>[null, ..._stockExchanges],
            display: (v) => v ?? '全部',
            onChanged: (v) {
              setState(() => _exchange = v);
              _loadCurrent(force: true);
            },
          ),
          _industryDropdown(),
        ];
      case _AssetTab.etf:
        return [
          _filterDropdown<String>(
            label: '市场',
            value: _etfMarket,
            options: _etfMarkets.map((p) => p[0]).toList(),
            display: (v) {
              final key = v ?? '';
              return _etfMarkets
                  .firstWhere((p) => p[0] == key, orElse: () => [key, key])[1];
            },
            onChanged: (v) {
              setState(() => _etfMarket = v ?? 'E');
              _loadCurrent(force: true);
            },
          ),
          _industryDropdown(),
        ];
      case _AssetTab.future:
        return [
          _filterDropdown<String>(
            label: '交易所',
            value: _futExchange,
            options: _futureExchanges,
            display: (v) => v ?? '',
            onChanged: (v) {
              setState(() => _futExchange = v);
              _loadCurrent(force: true);
            },
          ),
          _industryDropdown(),
        ];
      case _AssetTab.indexInstrument:
        return [
          _filterDropdown<String>(
            label: '市场',
            value: _indexMarket,
            options: _indexMarkets,
            display: (v) => v ?? '',
            onChanged: (v) {
              setState(() => _indexMarket = v);
              _loadCurrent(force: true);
            },
          ),
          _industryDropdown(),
        ];
    }
  }

  Widget _industryDropdown() {
    final list = _industries;
    if (list.isEmpty) return const SizedBox.shrink();
    return _filterDropdown<String?>(
      label: '行业 / 类别',
      value: _industry,
      options: <String?>[null, ...list],
      display: (v) => v == null || v.isEmpty ? '全部' : v,
      onChanged: (v) => setState(() => _industry = v),
    );
  }

  Widget _filterDropdown<T>({
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

  Widget _list() {
    final loading = _loading[_tab] ?? false;
    if (loading) {
      return const Center(child: CircularProgressIndicator());
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
            style: TextStyle(color: AppColors.textTertiary, fontSize: 12)),
      );
    }
    return ListView.separated(
      itemCount: list.length,
      separatorBuilder: (_, __) =>
          Divider(height: 1, color: AppColors.borderDim),
      itemBuilder: (_, i) {
        final ins = list[i];
        final selected = _selected.contains(ins.tsCode);
        return CheckboxListTile(
          value: selected,
          dense: true,
          activeColor: AppColors.amber,
          checkColor: Colors.black,
          controlAffinity: ListTileControlAffinity.leading,
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
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final entry in ins.tags.entries)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.borderDim),
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: Text('${entry.key}：${entry.value}',
                        style: TextStyle(
                            color: AppColors.textTertiary, fontSize: 10)),
                  ),
              ],
            ),
          ),
          onChanged: (v) {
            setState(() {
              if (v ?? false) {
                _selected.add(ins.tsCode);
              } else {
                _selected.remove(ins.tsCode);
              }
            });
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
          Text('已选 ${_selected.length} 项',
              style: TextStyle(
                  color: AppColors.textSecondary, fontSize: 11)),
          const Spacer(),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: _selected.isEmpty ? null : _confirm,
            icon: const Icon(Icons.add_task, size: 14),
            label: const Text('添加到组合'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirm() async {
    final list = _cache[_tab] ?? const <Instrument>[];
    final picks = [
      for (final ins in list)
        if (_selected.contains(ins.tsCode)) ins,
    ];
    if (picks.isEmpty) return;

    final ps = context.read<PortfolioState>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final qtyMap = await showDialog<Map<String, AssetLot>>(
      context: context,
      builder: (_) => AssetQuantityDialog(instruments: picks),
    );
    if (qtyMap == null || qtyMap.isEmpty) return;
    for (final ins in picks) {
      final lot = qtyMap[ins.tsCode];
      if (lot == null || lot.qty <= 0) continue;
      await ps.addAsset(
        instrument: ins,
        quantity: lot.qty,
        price: lot.price,
      );
    }
    if (mounted) {
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(content: Text('已添加 ${qtyMap.length} 个品种到组合')),
      );
    }
  }
}
