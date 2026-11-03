import 'package:dio/dio.dart';

import '../core/api/api_client.dart';

class MarketRealtimeException implements Exception {
  const MarketRealtimeException(this.message);

  final String message;

  @override
  String toString() => 'MarketRealtimeException: $message';
}

/// A provider-neutral snapshot returned by the backend market quote endpoint.
class RealtimeQuote {
  const RealtimeQuote({
    required this.tsCode,
    required this.name,
    required this.assetClass,
    required this.last,
    required this.pctChg,
    required this.open,
    required this.high,
    required this.low,
    required this.preClose,
    required this.preSettle,
    required this.volume,
    required this.delayed,
    required this.source,
    required this.asOf,
    this.quoteTime,
  });

  final String tsCode;
  final String name;
  final String assetClass;
  final double last;
  final double pctChg;
  final double open;
  final double high;
  final double low;
  final double preClose;
  final double preSettle;
  final int volume;
  final bool delayed;
  final String source;

  /// Time at which the backend received the snapshot.
  final DateTime asOf;

  /// Timestamp supplied by the upstream quote provider, when available.
  final DateTime? quoteTime;

  DateTime get effectiveTime => quoteTime ?? asOf;

  factory RealtimeQuote.fromJson(Map<String, dynamic> json) {
    final asOfMs = _toInt(json['as_of'] ?? json['asOf']);
    final quoteMs = _toInt(json['quote_time'] ?? json['quoteTime']);
    return RealtimeQuote(
      tsCode: (json['ts_code'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      assetClass: (json['asset_class'] ?? '').toString(),
      last: _toDouble(json['last']),
      pctChg: _toDouble(json['pct_chg']),
      open: _toDouble(json['open']),
      high: _toDouble(json['high']),
      low: _toDouble(json['low']),
      preClose: _toDouble(json['pre_close']),
      preSettle: _toDouble(json['pre_settle']),
      volume: _toInt(json['volume']),
      delayed: json['delayed'] == true,
      source: (json['source'] ?? '').toString(),
      asOf: asOfMs > 0
          ? DateTime.fromMillisecondsSinceEpoch(asOfMs)
          : DateTime.now(),
      quoteTime:
          quoteMs > 0 ? DateTime.fromMillisecondsSinceEpoch(quoteMs) : null,
    );
  }

  static double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

/// Injectable realtime quote API used by the market screen and widget tests.
abstract interface class MarketQuoteService {
  Future<RealtimeQuote> fetchQuote(String tsCode);
}

class MarketRealtimeService implements MarketQuoteService {
  MarketRealtimeService({Dio? dio}) : _dio = dio ?? ApiClient.instance.dio;

  final Dio _dio;

  @override
  Future<RealtimeQuote> fetchQuote(String tsCode) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/v1/market/quote',
        queryParameters: {'ts_code': tsCode},
      );
      if (response.statusCode != 200) {
        throw MarketRealtimeException(
          '实时行情请求失败（${response.statusCode ?? '未知状态'}）',
        );
      }
      final quote = response.data?['quote'];
      if (quote is! Map) {
        throw const MarketRealtimeException('实时行情返回格式不正确。');
      }
      final parsed = RealtimeQuote.fromJson(
        Map<String, dynamic>.from(quote),
      );
      if (!parsed.last.isFinite || parsed.last <= 0) {
        throw const MarketRealtimeException('实时行情没有有效最新价。');
      }
      return parsed;
    } on DioException catch (error) {
      final body = error.response?.data;
      final message = body is Map ? body['message'] : null;
      throw MarketRealtimeException(
        (message ?? error.message ?? '实时行情暂时不可用').toString(),
      );
    }
  }
}
