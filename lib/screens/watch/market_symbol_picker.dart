import 'package:flutter/material.dart';

import '../../models/instrument.dart';
import '../../services/tushare_service.dart';
import 'market_theme.dart';

enum MarketAssetTab { stock, future }

Future<Instrument?> showMarketSymbolPicker(
  BuildContext context, {
  MarketAssetTab initialTab = MarketAssetTab.stock,
  String? selectedCode,
  TushareService? service,
}) {
  return showDialog<Instrument>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.72),
    builder: (_) => MarketSymbolPicker(
      initialTab: initialTab,
      selectedCode: selectedCode,
      service: service,
    ),
  );
}

class MarketSymbolPicker extends StatefulWidget {
  const MarketSymbolPicker({
    super.key,
    this.initialTab = MarketAssetTab.stock,
    this.selectedCode,
    this.service,
  });

  final MarketAssetTab initialTab;
  final String? selectedCode;
  final TushareService? service;

  @override
  State<MarketSymbolPicker> createState() => _MarketSymbolPickerState();
}

class _MarketSymbolPickerState extends State<MarketSymbolPicker> {
  static const _futureExchanges = <String>[
    'CFFEX',
    'SHFE',
    'DCE',
    'CZCE',
    'GFEX',
    'INE',
  ];
  static const _futureExchangeLabels = <String, String>{
    'CFFEX': '中金所',
    'SHFE': '上期所',
    'DCE': '大商所',
    'CZCE': '郑商所',
    'GFEX': '广期所',
    'INE': '上海能源',
  };

  late final TushareService _service = widget.service ?? TushareService();
  final _search = TextEditingController();
  late MarketAssetTab _tab = widget.initialTab;
  String _futureExchange = 'CFFEX';
  List<Instrument> _instruments = const [];
  bool _loading = false;
  String? _error;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final requestId = ++_requestId;
    setState(() {
      _loading = true;
      _error = null;
      _instruments = const [];
    });
    try {
      final rows = _tab == MarketAssetTab.stock
          ? await _service.stockBasic()
          : await _service.futBasic(exchange: _futureExchange);
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _instruments = rows;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _loading = false;
        _error = error is TushareException ? error.message : error.toString();
      });
    }
  }

  List<Instrument> get _visible {
    final query = _search.text.trim().toLowerCase();
    if (query.isEmpty) return _instruments;
    return [
      for (final item in _instruments)
        if (item.tsCode.toLowerCase().contains(query) ||
            item.name.toLowerCase().contains(query) ||
            item.industry.toLowerCase().contains(query))
          item,
    ];
  }

  void _switchTab(MarketAssetTab tab) {
    if (_tab == tab) return;
    setState(() {
      _tab = tab;
      _search.clear();
    });
    _load();
  }

  void _switchExchange(String exchange) {
    if (_futureExchange == exchange) return;
    setState(() => _futureExchange = exchange);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.fromLTRB(12, 42, 12, 12),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 760),
        child: Column(
          children: [
            _header(),
            _tabs(),
            _searchRow(),
            if (_tab == MarketAssetTab.future) _exchangeRow(),
            const Divider(height: 1),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 10, 10),
      child: Row(
        children: [
          const Text(
            '选择交易品种',
            style: TextStyle(
              color: MarketColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            _tab == MarketAssetTab.stock ? 'A 股' : '国内期货',
            style: const TextStyle(
              color: MarketColors.textMuted,
              fontSize: 12,
            ),
          ),
          const Spacer(),
          IconButton(
            tooltip: '关闭',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(
              Icons.close,
              color: MarketColors.textSecondary,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabs() {
    Widget tab(MarketAssetTab tab, String label) {
      final selected = _tab == tab;
      return InkWell(
        onTap: () => _switchTab(tab),
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? MarketColors.accent : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color:
                  selected ? MarketColors.textPrimary : MarketColors.textMuted,
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      );
    }

    return Container(
      alignment: Alignment.centerLeft,
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: MarketColors.border),
          bottom: BorderSide(color: MarketColors.border),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 6),
          tab(MarketAssetTab.stock, '股票'),
          tab(MarketAssetTab.future, '期货'),
          const Spacer(),
          IconButton(
            tooltip: '重新载入',
            onPressed: _loading ? null : _load,
            icon: const Icon(
              Icons.refresh,
              color: MarketColors.textMuted,
              size: 18,
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: TextField(
        controller: _search,
        autofocus: false,
        onChanged: (_) => setState(() {}),
        style: const TextStyle(
          color: MarketColors.textPrimary,
          fontSize: 14,
        ),
        decoration: InputDecoration(
          hintText: _tab == MarketAssetTab.stock ? '输入股票代码或名称' : '输入合约代码或名称',
          prefixIcon: const Icon(Icons.search, size: 19),
          suffixIcon: _search.text.isEmpty
              ? null
              : IconButton(
                  onPressed: () => setState(_search.clear),
                  icon: const Icon(Icons.cancel, size: 17),
                ),
          isDense: true,
        ),
      ),
    );
  }

  Widget _exchangeRow() {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
        children: [
          for (final exchange in _futureExchanges)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text(_futureExchangeLabels[exchange] ?? exchange),
                selected: _futureExchange == exchange,
                onSelected: (_) => _switchExchange(exchange),
                showCheckmark: false,
                backgroundColor: MarketColors.panelRaised,
                selectedColor: MarketColors.accentSoft,
                side: BorderSide(
                  color: _futureExchange == exchange
                      ? MarketColors.accent
                      : MarketColors.border,
                ),
                labelStyle: TextStyle(
                  color: _futureExchange == exchange
                      ? MarketColors.textPrimary
                      : MarketColors.textMuted,
                  fontSize: 11,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_error != null) {
      return _errorView(_error!);
    }
    final visible = _visible;
    if (visible.isEmpty) {
      return Center(
        child: Text(
          _search.text.trim().isEmpty ? '暂无可用品种' : '没有找到匹配的品种',
          style: const TextStyle(
            color: MarketColors.textMuted,
            fontSize: 13,
          ),
        ),
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
          child: Row(
            children: [
              Text(
                '${visible.length} 个结果',
                style: const TextStyle(
                  color: MarketColors.textMuted,
                  fontSize: 11,
                ),
              ),
              const Spacer(),
              const Text(
                '点击后切换图表',
                style: TextStyle(
                  color: MarketColors.textMuted,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            itemCount: visible.length,
            itemBuilder: (context, index) => _row(visible[index]),
          ),
        ),
      ],
    );
  }

  Widget _row(Instrument instrument) {
    final selected = instrument.tsCode == widget.selectedCode;
    return InkWell(
      onTap: () => Navigator.of(context).pop(instrument),
      child: Container(
        constraints: const BoxConstraints(minHeight: 54),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: MarketColors.border)),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: MarketColors.panelRaised,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                instrument.name.isEmpty ? '—' : instrument.name.substring(0, 1),
                style: TextStyle(
                  color: _tab == MarketAssetTab.stock
                      ? MarketColors.up
                      : MarketColors.resistance,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    instrument.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: MarketColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (instrument.industry.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      instrument.industry,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: MarketColors.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              instrument.tsCode,
              style: TextStyle(
                color:
                    selected ? MarketColors.accent : MarketColors.textSecondary,
                fontSize: 11,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              selected ? Icons.check_circle : Icons.chevron_right,
              size: selected ? 17 : 18,
              color: selected ? MarketColors.accent : MarketColors.textMuted,
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorView(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_outlined,
              color: MarketColors.textMuted,
              size: 32,
            ),
            const SizedBox(height: 12),
            const Text(
              '品种列表加载失败',
              style: TextStyle(
                color: MarketColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: MarketColors.textMuted,
                fontSize: 11,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('重试'),
              style: OutlinedButton.styleFrom(
                foregroundColor: MarketColors.textPrimary,
                side: const BorderSide(color: MarketColors.border),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
