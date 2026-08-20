import 'package:flutter/material.dart';

import '../../models/instrument.dart';
import '../../services/tushare_service.dart';
import '../../state/watchlist_state.dart';
import '../../theme/app_theme.dart';
import 'widgets/candlestick_chart.dart';
import 'widgets/faq_section.dart';

/// K 线周期。
enum _Range { m3, m6, y1, y3 }

const _rangeDefs = {
  _Range.m3: (label: '3月', days: 90),
  _Range.m6: (label: '6月', days: 182),
  _Range.y1: (label: '1年', days: 365),
  _Range.y3: (label: '3年', days: 365 * 3),
};

/// 看盘第二页 — 品种详情。
/// 上下结构：上半部分 K 线图（指标可开关），下半部分常见问题下拉。
class SymbolDetailScreen extends StatefulWidget {
  const SymbolDetailScreen({super.key, required this.item});

  final WatchItem item;

  @override
  State<SymbolDetailScreen> createState() => _SymbolDetailScreenState();
}

class _SymbolDetailScreenState extends State<SymbolDetailScreen> {
  final _tushare = TushareService();

  List<CandlePoint> _candles = const [];
  bool _loading = false;
  String? _error;
  _Range _range = _Range.m6;

  /// 指标开关状态（默认开 MA + 成交量，与主流软件一致）。
  ChartIndicatorFlags _flags = const ChartIndicatorFlags();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final days = _rangeDefs[_range]!.days;
      final candles = await _tushare.historyFor(
        widget.item.tsCode,
        start: DateTime.now().subtract(Duration(days: days + 30)),
        end: DateTime.now(),
      );
      if (!mounted) return;
      setState(() {
        _candles = candles;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _setRange(_Range r) {
    if (_range == r) return;
    _range = r;
    _load();
  }

  /// 指标开关注册表：顺序即展示顺序。
  /// 每项 = (标签, 当前开关, 设置函数)。
  List<(String, bool, void Function(bool))> get _indicatorToggles => [
        ('MA', _flags.ma, (v) => _flags = _flags.copyWith(ma: v)),
        ('BOLL', _flags.boll, (v) => _flags = _flags.copyWith(boll: v)),
        ('成交量', _flags.vol, (v) => _flags = _flags.copyWith(vol: v)),
        ('MACD', _flags.macd, (v) => _flags = _flags.copyWith(macd: v)),
        ('KDJ', _flags.kdj, (v) => _flags = _flags.copyWith(kdj: v)),
        ('RSI', _flags.rsi, (v) => _flags = _flags.copyWith(rsi: v)),
      ];

  @override
  Widget build(BuildContext context) {
    final last = _candles.isEmpty ? null : _candles.last;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Flexible(
              child: Text(
                widget.item.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              widget.item.tsCode,
              style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textTertiary,
                  fontFamily: 'monospace'),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          _header(last),
          Divider(height: 1, color: AppColors.borderDim),
          // 上半部分：K 线图
          Expanded(
            flex: 3,
            child: _chartArea(),
          ),
          Divider(height: 1, color: AppColors.borderDim),
          // 下半部分：常见问题
          Expanded(
            flex: 2,
            child: SingleChildScrollView(
              child: FaqSection(
                tsCode: widget.item.tsCode,
                name: widget.item.name,
                assetClass: widget.item.assetClass,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 最新价头部：价格 + 涨跌幅。
  Widget _header(CandlePoint? last) {
    final prev = _candles.length >= 2 ? _candles[_candles.length - 2] : null;
    final close = last?.close;
    final pct = last?.pctChg ??
        (prev != null && close != null && prev.close != 0
            ? (close - prev.close) / prev.close * 100
            : null);
    final up = (pct ?? 0) > 0;
    final color = up
        ? AppColors.positive
        : (pct ?? 0) < 0
            ? AppColors.negative
            : AppColors.textPrimary;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        children: [
          Text(
            close == null ? '--' : close.toStringAsFixed(2),
            style: TextStyle(
              color: close == null ? AppColors.textTertiary : color,
              fontSize: 26,
              fontWeight: FontWeight.w900,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(width: 10),
          if (pct != null)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${up ? '+' : ''}${pct.toStringAsFixed(2)}%',
                style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'monospace'),
              ),
            ),
          const Spacer(),
          if (last != null)
            Text(
              '${last.date.year}-${last.date.month.toString().padLeft(2, '0')}-${last.date.day.toString().padLeft(2, '0')}',
              style: TextStyle(
                  color: AppColors.textTertiary, fontSize: 11),
            ),
        ],
      ),
    );
  }

  Widget _chartArea() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
      child: Column(
        children: [
          _rangeRow(),
          const SizedBox(height: 4),
          _indicatorRow(),
          const SizedBox(height: 4),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(
                        color: AppColors.amber, strokeWidth: 2))
                : _error != null
                    ? _errorView()
                    : CandlestickChart(
                        candles: _candles, flags: _flags),
          ),
        ],
      ),
    );
  }

  /// 周期切换行：3月 / 6月 / 1年 / 3年。
  Widget _rangeRow() {
    return Row(
      children: [
        for (final e in _rangeDefs.entries)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: _pill(
              label: e.value.label,
              active: _range == e.key,
              onTap: () => _setRange(e.key),
            ),
          ),
      ],
    );
  }

  /// 指标开关行：MA / BOLL / 成交量 / MACD / KDJ / RSI。
  Widget _indicatorRow() {
    return SizedBox(
      height: 28,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final (label, on, set) in _indicatorToggles)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: _pill(
                label: label,
                active: on,
                onTap: () => setState(() => set(!on)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _pill({required String label, required bool active,
      required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: active
              ? AppColors.amber.withValues(alpha: 0.16)
              : AppColors.bgRaised,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: active ? AppColors.amber : AppColors.borderDim),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? AppColors.amber : AppColors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _errorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline,
                color: AppColors.danger, size: 32),
            const SizedBox(height: 10),
            Text(
              _error ?? '',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: AppColors.textSecondary, fontSize: 11),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh, size: 14),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}
