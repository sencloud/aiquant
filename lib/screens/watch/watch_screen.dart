import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/storage/hive_setup.dart' show prefsBox;
import '../../core/utils/china_market.dart';
import '../../models/instrument.dart';
import '../../models/market_period.dart';
import '../../services/market_levels.dart';
import '../../services/tushare_service.dart';
import '../../state/watchlist_state.dart';
import 'market_symbol_picker.dart';
import 'market_theme.dart';
import 'widgets/trading_candle_chart.dart';

/// 应用唯一首页：股票 / 期货行情与关键价位。
class WatchScreen extends StatefulWidget {
  const WatchScreen({super.key, this.service});

  final TushareService? service;

  @override
  State<WatchScreen> createState() => _WatchScreenState();
}

class _WatchScreenState extends State<WatchScreen> {
  static const _selectionKey = 'market_home.selection.v1';
  static const _recentKey = 'market_home.recent.v1';
  static const _defaultItem = WatchItem(
    tsCode: '600519.SH',
    name: '贵州茅台',
    assetClass: '股票',
  );

  late final TushareService _service = widget.service ?? TushareService();
  WatchItem _selected = _defaultItem;
  MarketPeriod _period = MarketPeriod.oneDay;
  List<CandlePoint> _candles = const [];
  SupportResistance _levels = const SupportResistance();
  List<WatchItem> _recent = const [];
  ChartCrosshair? _crosshair;
  int? _replayIndex;
  bool _replayPlaying = false;
  Timer? _replayTimer;
  bool _loading = false;
  bool _showMovingAverages = true;
  bool _showVolume = true;
  String? _error;
  DateTime? _updatedAt;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _restoreLocalState();
    _load(clear: true);
  }

  @override
  void dispose() {
    _replayTimer?.cancel();
    super.dispose();
  }

  void _restoreLocalState() {
    try {
      final rawSelection = prefsBox.get(_selectionKey);
      if (rawSelection is Map) {
        final item = WatchItem.fromJson(
          Map<String, dynamic>.from(rawSelection),
        );
        if (_isSupported(item)) _selected = item;
      }
      final rawRecent = prefsBox.get(_recentKey);
      if (rawRecent is String && rawRecent.isNotEmpty) {
        final decoded = jsonDecode(rawRecent);
        if (decoded is List) {
          _recent = [
            for (final row in decoded)
              if (row is Map)
                WatchItem.fromJson(Map<String, dynamic>.from(row)),
          ].where(_isSupported).take(6).toList(growable: false);
        }
      }
    } catch (_) {
      // Hive 尚未打开或旧数据损坏时，从默认股票开始，不影响行情页。
    }
  }

  bool _isSupported(WatchItem item) =>
      ChinaMarket.isStock(item.tsCode) || ChinaMarket.isFuture(item.tsCode);

  Future<void> _load({bool clear = false}) async {
    final requestId = ++_requestId;
    _replayTimer?.cancel();
    setState(() {
      _loading = true;
      _error = null;
      _crosshair = null;
      _replayIndex = null;
      _replayPlaying = false;
      if (!clear && _candles.isNotEmpty) {
        _levels = MarketLevelAnalyzer.analyze(_candles);
      }
      if (clear) {
        _candles = const [];
        _levels = const SupportResistance();
      }
    });
    try {
      final candles = await _service.historyForPeriod(
        _selected.tsCode,
        _period,
      );
      if (!mounted || requestId != _requestId) return;
      if (candles.isEmpty) {
        throw TushareException('当前周期没有返回 K 线数据。');
      }
      final levels = MarketLevelAnalyzer.analyze(candles);
      setState(() {
        _candles = List<CandlePoint>.unmodifiable(candles);
        _levels = levels;
        _loading = false;
        _updatedAt = DateTime.now();
      });
    } catch (error) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _loading = false;
        _candles = const [];
        _levels = const SupportResistance();
        _error = error is TushareException ? error.message : error.toString();
      });
    }
  }

  Future<void> _selectPeriod(MarketPeriod period) async {
    if (_period == period) return;
    setState(() => _period = period);
    await _load(clear: true);
  }

  Future<void> _openPicker() async {
    final item = await showMarketSymbolPicker(
      context,
      initialTab: ChinaMarket.isFuture(_selected.tsCode)
          ? MarketAssetTab.future
          : MarketAssetTab.stock,
      selectedCode: _selected.tsCode,
      service: _service,
    );
    if (item == null || !mounted) return;
    final selection = WatchItem.fromInstrument(item);
    if (!_isSupported(selection)) return;
    setState(() {
      _selected = selection;
      _crosshair = null;
    });
    _remember(selection);
    await _load(clear: true);
  }

  Future<void> _selectRecent(WatchItem item) async {
    if (item.tsCode == _selected.tsCode) return;
    setState(() {
      _selected = item;
      _crosshair = null;
    });
    _remember(item);
    await _load(clear: true);
  }

  void _remember(WatchItem item) {
    final next = [
      item,
      for (final old in _recent)
        if (old.tsCode != item.tsCode) old,
    ].take(6).toList(growable: false);
    setState(() => _recent = next);
    try {
      prefsBox.put(_selectionKey, item.toJson());
      prefsBox.put(
        _recentKey,
        jsonEncode([for (final row in next) row.toJson()]),
      );
    } catch (_) {
      // 本地缓存失败不阻断行情。
    }
  }

  SupportResistance _levelsThrough(int index) => MarketLevelAnalyzer.analyze(
        _candles.take(index + 1).toList(growable: false),
      );

  void _startReplay() {
    final crosshair = _crosshair;
    if (crosshair == null || _candles.isEmpty) return;
    final start = crosshair.index.clamp(0, _candles.length - 1);
    final hasFuture = start < _candles.length - 1;
    _replayTimer?.cancel();
    setState(() {
      _crosshair = null;
      _replayIndex = start;
      _replayPlaying = hasFuture;
      _levels = _levelsThrough(start);
    });
    if (hasFuture) _scheduleReplayTick();
  }

  void _toggleReplayPlay() {
    final index = _replayIndex;
    if (index == null || index >= _candles.length - 1) return;
    setState(() => _replayPlaying = !_replayPlaying);
    if (_replayPlaying) {
      _scheduleReplayTick();
    } else {
      _replayTimer?.cancel();
    }
  }

  void _moveReplay(int delta, {bool automatic = false}) {
    final current = _replayIndex;
    if (current == null) return;
    final next = (current + delta).clamp(0, _candles.length - 1);
    final atEnd = next >= _candles.length - 1;
    if (!automatic) _replayTimer?.cancel();
    setState(() {
      _replayIndex = next;
      _levels = _levelsThrough(next);
      if (!automatic || atEnd) _replayPlaying = false;
    });
  }

  void _scheduleReplayTick() {
    _replayTimer?.cancel();
    if (!_replayPlaying || _replayIndex == null) return;
    _replayTimer = Timer(const Duration(milliseconds: 650), () {
      if (!mounted || !_replayPlaying || _replayIndex == null) return;
      _moveReplay(1, automatic: true);
      if (_replayPlaying) _scheduleReplayTick();
    });
  }

  void _exitReplay() {
    if (_replayIndex == null) return;
    _replayTimer?.cancel();
    setState(() {
      _replayIndex = null;
      _replayPlaying = false;
      _crosshair = null;
      _levels = MarketLevelAnalyzer.analyze(_candles);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: MarketColors.background,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 920;
              if (!wide) {
                return _compactLayout();
              }
              return Row(
                children: [
                  SizedBox(width: 252, child: _sidebar()),
                  const VerticalDivider(width: 1),
                  Expanded(child: _marketPane(compact: false)),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _compactLayout() {
    return Column(
      children: [
        _compactTopBar(),
        const Divider(height: 1),
        Expanded(child: _marketPane(compact: true)),
      ],
    );
  }

  Widget _compactTopBar() {
    return SizedBox(
      height: 52,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: MarketColors.accent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                '喜',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 9),
            const Text(
              '喜AI',
              style: TextStyle(
                color: MarketColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            _symbolSwitchButton(),
            const SizedBox(width: 4),
            IconButton(
              tooltip: '刷新行情',
              onPressed: _loading ? null : () => _load(),
              icon: const Icon(
                Icons.refresh,
                color: MarketColors.textSecondary,
                size: 19,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sidebar() {
    return ColoredBox(
      color: MarketColors.panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 14, 16),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: MarketColors.accent,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: const Text(
                    '喜',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '喜AI',
                      style: TextStyle(
                        color: MarketColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '股票 · 期货',
                      style: TextStyle(
                        color: MarketColors.textMuted,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SizedBox(
              height: 38,
              child: FilledButton.icon(
                onPressed: _openPicker,
                icon: const Icon(Icons.search, size: 17),
                label: const Text('选择品种'),
                style: FilledButton.styleFrom(
                  backgroundColor: MarketColors.panelRaised,
                  foregroundColor: MarketColors.textPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                    side: const BorderSide(color: MarketColors.border),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          _sideLabel('当前品种'),
          _sideCurrent(),
          const SizedBox(height: 18),
          _sideLabel('关键价位'),
          _sideLevels(),
          const SizedBox(height: 18),
          _sideLabel('最近查看'),
          Expanded(child: _recentList()),
          _sideFooter(),
        ],
      ),
    );
  }

  Widget _sideLabel(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Text(
          text,
          style: const TextStyle(
            color: MarketColors.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.6,
          ),
        ),
      );

  Widget _sideCurrent() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MarketColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: MarketColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _selected.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: MarketColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _selected.tsCode,
                  style: const TextStyle(
                    color: MarketColors.textMuted,
                    fontSize: 10,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _assetBadge(),
        ],
      ),
    );
  }

  Widget _sideLevels() {
    final rows = <Widget>[];
    for (var i = _levels.resistances.length - 1; i >= 0; i--) {
      final zone = _levels.resistances[i];
      rows.add(
        _levelRow(
          label: 'R${i + 1}',
          zone: zone,
          color: MarketColors.resistance,
        ),
      );
    }
    for (var i = 0; i < _levels.supports.length; i++) {
      final zone = _levels.supports[i];
      rows.add(
        _levelRow(
          label: 'S${i + 1}',
          zone: zone,
          color: MarketColors.support,
        ),
      );
    }
    if (rows.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: Text(
          '等待足够的 K 线后计算',
          style: TextStyle(color: MarketColors.textMuted, fontSize: 11),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(children: rows),
    );
  }

  Widget _levelRow({
    required String label,
    required MarketPriceZone zone,
    required Color color,
  }) {
    final close = _candles.isEmpty ? null : _candles.last.close;
    final distance = close == null || close == 0
        ? null
        : (zone.center - close) / close * 100;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              '${_formatPrice(zone.low)}–${_formatPrice(zone.high)}',
              style: const TextStyle(
                color: MarketColors.textSecondary,
                fontSize: 11,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          if (distance != null)
            Text(
              '${distance >= 0 ? '+' : ''}${distance.toStringAsFixed(2)}%',
              style: TextStyle(
                color: color.withValues(alpha: 0.82),
                fontSize: 10,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
        ],
      ),
    );
  }

  Widget _recentList() {
    if (_recent.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: Text(
          '选择过的股票和期货会出现在这里',
          style: TextStyle(
            color: MarketColors.textMuted,
            fontSize: 11,
            height: 1.5,
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      itemCount: _recent.length,
      itemBuilder: (context, index) {
        final item = _recent[index];
        final selected = item.tsCode == _selected.tsCode;
        return InkWell(
          onTap: () => _selectRecent(item),
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              color: selected ? MarketColors.panelRaised : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color:
                        selected ? MarketColors.accent : MarketColors.textMuted,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected
                          ? MarketColors.textPrimary
                          : MarketColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ),
                Text(
                  ChinaMarket.displaySymbol(item.tsCode),
                  style: const TextStyle(
                    color: MarketColors.textMuted,
                    fontSize: 9,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _sideFooter() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: MarketColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.verified_outlined,
                color: MarketColors.textMuted,
                size: 13,
              ),
              SizedBox(width: 5),
              Text(
                '数据源 · Tushare Pro',
                style: TextStyle(
                  color: MarketColors.textMuted,
                  fontSize: 10,
                ),
              ),
            ],
          ),
          if (_updatedAt != null) ...[
            const SizedBox(height: 4),
            Text(
              '更新 ${_formatClock(_updatedAt!)}',
              style: const TextStyle(
                color: MarketColors.textMuted,
                fontSize: 10,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _marketPane({required bool compact}) {
    return ColoredBox(
      color: MarketColors.background,
      child: Column(
        children: [
          _symbolHeader(compact: compact),
          const Divider(height: 1),
          _periodBar(),
          const Divider(height: 1),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(child: _chart()),
                if (_loading)
                  const Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: LinearProgressIndicator(
                      minHeight: 1.5,
                      backgroundColor: Colors.transparent,
                      color: MarketColors.accent,
                    ),
                  ),
                if (_error != null && !_loading)
                  Positioned.fill(child: _errorOverlay()),
                if (_candles.isEmpty && !_loading && _error == null)
                  Positioned.fill(child: _emptyOverlay()),
              ],
            ),
          ),
          _statusBar(compact: compact),
        ],
      ),
    );
  }

  Widget _symbolHeader({required bool compact}) {
    final replayCandle = _replayIndex == null || _candles.isEmpty
        ? null
        : _candles[_replayIndex!];
    final active = _crosshair?.candle ??
        replayCandle ??
        (_candles.isEmpty ? null : _candles.last);
    final previous = _previousClose(active);
    final change =
        active == null ? null : active.close - (previous ?? active.close);
    final pct = active == null
        ? null
        : previous != null && previous != 0
            ? change! / previous * 100
            : active.pctChg;
    final color = (change ?? pct ?? 0) > 0
        ? MarketColors.up
        : (change ?? pct ?? 0) < 0
            ? MarketColors.down
            : MarketColors.textPrimary;
    final canStartReplay = _replayIndex == null &&
        _crosshair != null &&
        _crosshair!.index < _candles.length - 1;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        compact ? 13 : 16,
        compact ? 10 : 12,
        compact ? 8 : 14,
        10,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  _selected.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: MarketColors.textPrimary,
                    fontSize: compact ? 17 : 19,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _assetBadge(),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  _selected.tsCode,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: MarketColors.textMuted,
                    fontSize: 11,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              if (compact && canStartReplay) ...[
                const Spacer(),
                _replayShortcut(),
              ] else if (compact && _replayIndex != null) ...[
                const Spacer(),
                const Text(
                  '回放模式',
                  style: TextStyle(
                    color: MarketColors.accent,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              if (!compact) ...[
                const Spacer(),
                _symbolSwitchButton(),
                const SizedBox(width: 2),
                IconButton(
                  tooltip: '刷新行情',
                  onPressed: _loading ? null : () => _load(),
                  icon: const Icon(
                    Icons.refresh,
                    color: MarketColors.textSecondary,
                    size: 19,
                  ),
                ),
              ],
            ],
          ),
          SizedBox(height: compact ? 6 : 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                active == null ? '—' : _formatPrice(active.close),
                style: TextStyle(
                  color: active == null ? MarketColors.textMuted : color,
                  fontSize: compact ? 27 : 31,
                  height: 1,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.8,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 10),
              if (active != null && (change != null || pct != null))
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    '${(change ?? 0) >= 0 ? '+' : ''}'
                    '${(change ?? 0).toStringAsFixed(2)} '
                    '${(pct ?? 0) >= 0 ? '+' : ''}'
                    '${(pct ?? 0).toStringAsFixed(2)}%',
                    style: TextStyle(
                      color: color,
                      fontSize: compact ? 12 : 13,
                      fontWeight: FontWeight.w500,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              const Spacer(),
              if (!compact && canStartReplay)
                _replayShortcut()
              else if (!compact && _replayIndex != null)
                const Text(
                  '回放模式',
                  style: TextStyle(
                    color: MarketColors.accent,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
          SizedBox(height: compact ? 8 : 10),
          _ohlcRow(active, compact: compact),
          if (_replayIndex != null) ...[
            const SizedBox(height: 5),
            _replayControls(),
          ],
        ],
      ),
    );
  }

  Widget _replayShortcut() {
    return TextButton.icon(
      onPressed: _startReplay,
      style: TextButton.styleFrom(
        foregroundColor: MarketColors.accent,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        minimumSize: const Size(0, 30),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: const Icon(Icons.replay, size: 15),
      label: const Text(
        '从此处回放',
        style: TextStyle(fontSize: 10),
      ),
    );
  }

  Widget _ohlcRow(CandlePoint? active, {required bool compact}) {
    final values = <(String, String, Color)>[
      (
        '开',
        active?.open == null ? '—' : _formatPrice(active!.open!),
        MarketColors.textSecondary
      ),
      (
        '高',
        active?.high == null ? '—' : _formatPrice(active!.high!),
        MarketColors.textSecondary
      ),
      (
        '低',
        active?.low == null ? '—' : _formatPrice(active!.low!),
        MarketColors.textSecondary
      ),
      (
        '收',
        active == null ? '—' : _formatPrice(active.close),
        MarketColors.textSecondary
      ),
      (
        '量',
        active?.vol == null ? '—' : _formatVolume(active!.vol!),
        MarketColors.textSecondary
      ),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < values.length; i++) ...[
            Text(
              values[i].$1,
              style: const TextStyle(
                color: MarketColors.textMuted,
                fontSize: 10,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              values[i].$2,
              style: TextStyle(
                color: values[i].$3,
                fontSize: compact ? 10 : 11,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            if (i != values.length - 1) const SizedBox(width: 14),
          ],
          if (active != null &&
              (_crosshair != null || _replayIndex != null)) ...[
            const SizedBox(width: 14),
            Text(
              _formatDateTime(active.date),
              style: const TextStyle(
                color: MarketColors.textMuted,
                fontSize: 10,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _replayControls() {
    final index = _replayIndex;
    if (index == null) return const SizedBox.shrink();
    final atStart = index <= 0;
    final atEnd = index >= _candles.length - 1;
    return Container(
      height: 32,
      padding: const EdgeInsets.only(left: 8, right: 2),
      decoration: BoxDecoration(
        color: MarketColors.accentSoft,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '回放 ${index + 1}/${_candles.length}',
            style: const TextStyle(
              color: MarketColors.accent,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 6),
          _replayIcon(
            icon: Icons.skip_previous,
            tooltip: '上一根',
            onPressed: atStart ? null : () => _moveReplay(-1),
          ),
          _replayIcon(
            icon: _replayPlaying ? Icons.pause : Icons.play_arrow,
            tooltip: _replayPlaying ? '暂停' : '播放',
            onPressed: atEnd ? null : _toggleReplayPlay,
          ),
          _replayIcon(
            icon: Icons.skip_next,
            tooltip: '下一根',
            onPressed: atEnd ? null : () => _moveReplay(1),
          ),
          _replayIcon(
            icon: Icons.close,
            tooltip: '退出回放',
            onPressed: _exitReplay,
          ),
        ],
      ),
    );
  }

  Widget _replayIcon({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
  }) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      color: MarketColors.accent,
      disabledColor: MarketColors.textMuted.withValues(alpha: 0.4),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 28, height: 28),
      visualDensity: VisualDensity.compact,
    );
  }

  double? _previousClose(CandlePoint? active) {
    if (active == null || _candles.isEmpty) return null;
    final index = _candles.indexWhere(
      (bar) =>
          bar.date == active.date &&
          bar.close == active.close &&
          bar.open == active.open,
    );
    if (index < 0) return null;
    if (_period.isIntraday) {
      var firstOfDay = index;
      while (firstOfDay > 0 &&
          _sameDate(_candles[firstOfDay - 1].date, active.date)) {
        firstOfDay--;
      }
      if (firstOfDay < index) return _candles[firstOfDay].open;
    }
    return index > 0 ? _candles[index - 1].close : active.pctChg;
  }

  Widget _assetBadge() {
    final future = _selected.assetClass == '期货';
    final color = future ? MarketColors.resistance : MarketColors.accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        future ? '期货' : '股票',
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _symbolSwitchButton() {
    return InkWell(
      onTap: _openPicker,
      borderRadius: BorderRadius.circular(5),
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          border: Border.all(color: MarketColors.border),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              ChinaMarket.displaySymbol(_selected.tsCode),
              style: const TextStyle(
                color: MarketColors.textSecondary,
                fontSize: 11,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 5),
            const Icon(
              Icons.keyboard_arrow_down,
              color: MarketColors.textMuted,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  Widget _periodBar() {
    Widget periodButton(MarketPeriod period) {
      final selected = _period == period;
      return InkWell(
        onTap: () => _selectPeriod(period),
        borderRadius: BorderRadius.circular(4),
        child: Container(
          height: 38,
          constraints: const BoxConstraints(minWidth: 46),
          padding: const EdgeInsets.symmetric(horizontal: 9),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? MarketColors.accentSoft : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            period.label,
            style: TextStyle(
              color:
                  selected ? MarketColors.accent : MarketColors.textSecondary,
              fontSize: 11,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      );
    }

    Widget toggle(String label, bool active, VoidCallback onTap) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 7),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: active ? MarketColors.textPrimary : MarketColors.textMuted,
              fontSize: 10,
              fontWeight: active ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: 40,
      child: Row(
        children: [
          const SizedBox(width: 8),
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final period in MarketPeriod.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 2),
                    child: periodButton(period),
                  ),
              ],
            ),
          ),
          toggle(
            'MA',
            _showMovingAverages,
            () => setState(
              () => _showMovingAverages = !_showMovingAverages,
            ),
          ),
          toggle(
            'VOL',
            _showVolume,
            () => setState(() => _showVolume = !_showVolume),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  Widget _chart() {
    return TradingCandleChart(
      candles: _candles,
      period: _period,
      levels: _levels,
      watermark: ChinaMarket.displaySymbol(_selected.tsCode),
      showMovingAverages: _showMovingAverages,
      showVolume: _showVolume,
      replayIndex: _replayIndex,
      onCrosshair: (crosshair) {
        if (_replayIndex != null) return;
        if (_crosshair?.index == crosshair?.index) return;
        setState(() => _crosshair = crosshair);
      },
    );
  }

  Widget _errorOverlay() {
    final minutePermissionHint =
        _period.isIntraday && (_error?.contains('权限') ?? false);
    return ColoredBox(
      color: MarketColors.background.withValues(alpha: 0.96),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.show_chart,
                  color: MarketColors.textMuted,
                  size: 32,
                ),
                const SizedBox(height: 12),
                const Text(
                  '行情加载失败',
                  style: TextStyle(
                    color: MarketColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  _error ?? '',
                  textAlign: TextAlign.center,
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: MarketColors.textMuted,
                    fontSize: 11,
                    height: 1.55,
                  ),
                ),
                if (minutePermissionHint) ...[
                  const SizedBox(height: 8),
                  const Text(
                    '分钟线需要在 Tushare 账户中开通对应权限；日线不受影响。',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: MarketColors.warning,
                      fontSize: 10,
                      height: 1.5,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () => _load(clear: true),
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('重新加载'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: MarketColors.textPrimary,
                    side: const BorderSide(color: MarketColors.border),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _emptyOverlay() {
    return ColoredBox(
      color: MarketColors.background,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.candlestick_chart_outlined,
              color: MarketColors.textMuted,
              size: 34,
            ),
            const SizedBox(height: 10),
            const Text(
              '选择一个股票或期货',
              style: TextStyle(
                color: MarketColors.textMuted,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: _openPicker,
              child: const Text('打开品种列表'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusBar({required bool compact}) {
    return Container(
      height: compact ? 30 : 27,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: MarketColors.border)),
      ),
      child: Row(
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: const BoxDecoration(
              color: MarketColors.down,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '${_period.longLabel} · Tushare',
            style: const TextStyle(
              color: MarketColors.textMuted,
              fontSize: 9,
            ),
          ),
          const SizedBox(width: 12),
          if (!compact)
            const Text(
              '滚轮缩放 · 拖动平移 · 双击复位',
              style: TextStyle(
                color: MarketColors.textMuted,
                fontSize: 9,
              ),
            )
          else
            const Text(
              '捏合缩放 · 长按十字线',
              style: TextStyle(
                color: MarketColors.textMuted,
                fontSize: 9,
              ),
            ),
          const Spacer(),
          const _LiveClock(),
        ],
      ),
    );
  }

  static bool _sameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String _formatPrice(double value) {
    final abs = value.abs();
    if (abs >= 100000) return value.toStringAsFixed(0);
    if (abs >= 1000) return value.toStringAsFixed(1);
    return value.toStringAsFixed(2);
  }

  static String _formatVolume(double value) {
    if (value >= 100000000) {
      return '${(value / 100000000).toStringAsFixed(2)}亿';
    }
    if (value >= 10000) return '${(value / 10000).toStringAsFixed(2)}万';
    return value.toStringAsFixed(0);
  }

  static String _formatClock(DateTime date) =>
      '${date.hour.toString().padLeft(2, '0')}:'
      '${date.minute.toString().padLeft(2, '0')}:'
      '${date.second.toString().padLeft(2, '0')}';

  static String _formatDateTime(DateTime date) =>
      '${date.year}/${date.month.toString().padLeft(2, '0')}/'
      '${date.day.toString().padLeft(2, '0')} '
      '${date.hour.toString().padLeft(2, '0')}:'
      '${date.minute.toString().padLeft(2, '0')}';
}

class _LiveClock extends StatefulWidget {
  const _LiveClock();

  @override
  State<_LiveClock> createState() => _LiveClockState();
}

class _LiveClockState extends State<_LiveClock> {
  Timer? _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = '${_now.hour.toString().padLeft(2, '0')}:'
        '${_now.minute.toString().padLeft(2, '0')}:'
        '${_now.second.toString().padLeft(2, '0')}';
    return Text(
      text,
      key: const Key('market-live-clock'),
      style: const TextStyle(
        color: MarketColors.textMuted,
        fontSize: 9,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
    );
  }
}
