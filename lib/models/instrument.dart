/// One Tushare instrument (A-share, ETF, futures contract, index).
class Instrument {
  final String tsCode; // canonical Tushare code, e.g. 000001.SZ
  final String displaySymbol;
  final String name;
  final String exchange; // SSE / SZSE / BSE / DCE / CZC ...
  final String assetClass; // 股票 / ETF / 期货 / 指数
  final String industry; // industry / sector label
  final String area; // listing region (Tushare-specific)
  final String listDate;

  Instrument({
    required this.tsCode,
    required this.displaySymbol,
    required this.name,
    required this.exchange,
    required this.assetClass,
    this.industry = '',
    this.area = '',
    this.listDate = '',
  });

  String get displayLine =>
      '$tsCode  $name${industry.isNotEmpty ? "  · $industry" : ""}';

  Map<String, String> get tags => {
        '类型': assetClass,
        if (exchange.isNotEmpty) '交易所': exchange,
        if (industry.isNotEmpty) '行业': industry,
        if (area.isNotEmpty) '地区': area,
      };
}

/// Daily OHLC bar.
class CandlePoint {
  final DateTime date;
  final double close;
  final double? open;
  final double? high;
  final double? low;
  final double? pctChg;

  CandlePoint({
    required this.date,
    required this.close,
    this.open,
    this.high,
    this.low,
    this.pctChg,
  });
}
