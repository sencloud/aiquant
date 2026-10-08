import 'package:flutter/foundation.dart' show debugPrint;

import '../tushare_service.dart';
import '../../core/utils/china_market.dart';
import 'etf_rotation.dart';

/// 回测行情数据源：包装 TushareService.historyFor() 并做内存缓存。
///
/// 「策略调试」场景会反复改参数重跑：候选池 + benchmark + defensive 通常
/// 7-10 只 ETF，首次拉取后全部命中缓存，后续重跑不再打 Tushare API
/// （免费档有每分钟限频）。
///
/// 缓存 key = 归一化代码 + 起止日期。拉宽时间范围时会以更宽的范围
/// 重新拉取并覆盖旧缓存（新数据是旧数据的超集，覆盖安全）。
class BacktestDataSource {
  BacktestDataSource({TushareService? tushare})
      : _tushare = tushare ?? TushareService();

  final TushareService _tushare;

  /// code -> 已缓存区间。用于判断「新请求范围是否被已有缓存覆盖」。
  final Map<String, _Range> _cached = {};

  /// code -> 日线序列（日期 YYYYMMDD 升序）。
  final Map<String, List<BacktestCandle>> _series = {};

  /// 当前是否在拉取（串行进行中）。
  final Set<String> _inflight = <String>{};

  /// 逐只拉取行情（未命中的才走网络），带进度回调。
  ///
  /// [dataStart] 应由调用方预留暖机窗口（start 前 long_window*2+30 自然日，
  /// 引擎侧会再次校验数据量是否够算动量）。
  Future<Map<String, List<BacktestCandle>>> loadAll(
    List<String> symbols, {
    required DateTime dataStart,
    required DateTime end,
    void Function(int done, int total, String code)? onProgress,
  }) async {
    final codes = symbols.toSet().toList();
    final result = <String, List<BacktestCandle>>{};
    var done = 0;

    for (final code in codes) {
      final hit = _cached[code];
      if (hit != null &&
          !dataStart.isBefore(hit.start) &&
          !end.isAfter(hit.end)) {
        // 缓存命中：范围被已有区间完全覆盖
        result[code] = _series[code]!;
        done++;
        onProgress?.call(done, codes.length, code);
        continue;
      }

      // 串行拉取，避免触发 Tushare 每分钟限频
      while (_inflight.contains(code)) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      _inflight.add(code);
      try {
        final candles = await _tushare.historyFor(code,
            start: dataStart, end: end);
        final list = candles
            .map((c) => BacktestCandle(_ymd(c.date), c.close))
            .toList();
        debugPrint('[BacktestDS] $code 拉取完成：${list.length} 根K线'
            '${list.isEmpty ? '（空！）' : '（${list.first.date} ~ ${list.last.date}）'}');
        _series[code] = list;
        _cached[code] = _Range(dataStart, end);
        result[code] = list;
      } finally {
        _inflight.remove(code);
      }
      done++;
      onProgress?.call(done, codes.length, code);
    }
    return result;
  }

  /// 数据量校验：该 code 的行情是否足够计算 longWindow 日动量。
  String? validateEnough(String code, int longWindow) {
    final s = _series[ChinaMarket.normalizeSymbol(code)];
    if (s == null || s.length < longWindow + 5) {
      return '$code 行情数据不足以计算 $longWindow 日动量'
          '（实际 ${s?.length ?? 0} 个交易日）';
    }
    return null;
  }

  String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}'
      '${d.month.toString().padLeft(2, '0')}'
      '${d.day.toString().padLeft(2, '0')}';
}

class _Range {
  _Range(this.start, this.end);
  final DateTime start;
  final DateTime end;
}
