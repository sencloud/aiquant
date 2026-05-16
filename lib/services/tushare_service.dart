import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../core/config/app_config.dart';
import '../core/utils/china_market.dart';
import '../models/instrument.dart';

class TushareException implements Exception {
  final String message;
  TushareException(this.message);
  @override
  String toString() => 'TushareException: $message';
}

/// Tushare Pro REST client. All endpoints share the same envelope:
///   POST http://api.tushare.pro
///   { api_name, token, params, fields }
/// → { code, msg, data: { fields, items } }
///
/// Translates the column-major response into a list of maps so screens can
/// consume rows like normal JSON objects.
class TushareService {
  TushareService({Dio? dio}) : _dio = dio ?? Dio() {
    _dio.options.connectTimeout = const Duration(seconds: 15);
    _dio.options.receiveTimeout = const Duration(seconds: 30);
  }
  final Dio _dio;

  /// 直接发起一次 Tushare API 请求并返回行式结果。
  /// 上层工具（财务/资金面 / 宏观）通过这个口子访问任何 Tushare 接口，
  /// 不需要为每个 api_name 写专门的方法。
  Future<List<Map<String, dynamic>>> query({
    required String apiName,
    Map<String, dynamic> params = const {},
    String fields = '',
  }) =>
      _post(apiName: apiName, params: params, fields: fields);

  Future<List<Map<String, dynamic>>> _post({
    required String apiName,
    Map<String, dynamic> params = const {},
    String fields = '',
  }) async {
    final token = AppConfig.instance.tushareToken;
    if (token.isEmpty || token.startsWith('PUT_YOUR_')) {
      throw TushareException('请先在“设置”中配置 Tushare Token。');
    }

    final body = {
      'api_name': apiName,
      'token': token,
      'params': params,
      'fields': fields,
    };

    Response<dynamic> resp;
    try {
      resp = await _dio.post<dynamic>(
        AppConfig.instance.tushareEndpoint,
        data: body,
        options: Options(
          headers: {'Content-Type': 'application/json'},
          responseType: ResponseType.json,
        ),
      );
    } on DioException catch (e) {
      // Web hits a CORS wall on the public Tushare endpoint — surface a
      // dedicated, actionable hint instead of the generic XHR error string.
      if (kIsWeb) {
        throw TushareException(
            'Tushare 在 Web 端被浏览器跨域 (CORS) 拦截。\n'
            '请改用 Android / iOS 客户端，或在“设置”里把 Tushare Endpoint '
            '指向你自己的 HTTPS 代理（透传到 http://api.tushare.pro 即可）。\n\n'
            '本地调试也可启动：\n'
            r'flutter run -d chrome --web-browser-flag="--disable-web-security" '
            r'--web-browser-flag="--user-data-dir=$HOME/.cors_chrome"');
      }
      throw TushareException('Tushare 请求失败：${e.message ?? e.toString()}');
    }

    final data = resp.data;
    if (data is! Map) {
      throw TushareException('Tushare 返回非 JSON 对象。');
    }
    if ((data['code'] as int? ?? -1) != 0) {
      throw TushareException(
          'Tushare 返回错误：${data['msg'] ?? "未知错误"} (api=$apiName)');
    }

    final payload = data['data'] as Map?;
    if (payload == null) return const [];
    final List<dynamic> fieldList = payload['fields'] as List? ?? const [];
    final List<dynamic> items = payload['items'] as List? ?? const [];
    return [
      for (final row in items)
        if (row is List)
          {
            for (var i = 0; i < fieldList.length && i < row.length; i++)
              fieldList[i].toString(): row[i],
          },
    ];
  }

  // ── Discovery: stock_basic / fund_basic / fut_basic / index_basic ─────

  Future<List<Instrument>> stockBasic({
    String? exchange,
    String listStatus = 'L',
  }) async {
    final params = <String, dynamic>{'list_status': listStatus};
    if (exchange != null && exchange.isNotEmpty) {
      params['exchange'] = exchange;
    }
    final rows = await _post(
      apiName: 'stock_basic',
      params: params,
      fields: 'ts_code,symbol,name,area,industry,market,list_date,exchange',
    );
    return rows
        .map((r) => Instrument(
              tsCode: (r['ts_code'] ?? '').toString(),
              displaySymbol: (r['symbol'] ?? '').toString(),
              name: (r['name'] ?? '').toString(),
              exchange: (r['exchange'] ?? r['market'] ?? '').toString(),
              assetClass: '股票',
              industry: (r['industry'] ?? '').toString(),
              area: (r['area'] ?? '').toString(),
              listDate: (r['list_date'] ?? '').toString(),
            ))
        .toList();
  }

  Future<List<Instrument>> fundBasic({
    String market = 'E', // E = 场内 (ETF/LOF), O = 场外
  }) async {
    final rows = await _post(
      apiName: 'fund_basic',
      params: {'market': market},
      fields: 'ts_code,name,management,fund_type,list_date,market',
    );
    return rows
        .map((r) => Instrument(
              tsCode: (r['ts_code'] ?? '').toString(),
              displaySymbol: (r['ts_code'] ?? '').toString(),
              name: (r['name'] ?? '').toString(),
              exchange: market == 'E' ? '场内' : '场外',
              assetClass: 'ETF',
              industry: (r['fund_type'] ?? '').toString(),
              area: (r['management'] ?? '').toString(),
              listDate: (r['list_date'] ?? '').toString(),
            ))
        .toList();
  }

  Future<List<Instrument>> futBasic({String exchange = 'CFFEX'}) async {
    final rows = await _post(
      apiName: 'fut_basic',
      params: {'exchange': exchange},
      fields:
          'ts_code,symbol,name,fut_code,exchange,multiplier,list_date,delist_date',
    );
    return rows
        .map((r) => Instrument(
              tsCode: (r['ts_code'] ?? '').toString(),
              displaySymbol: (r['symbol'] ?? '').toString(),
              name: (r['name'] ?? '').toString(),
              exchange: (r['exchange'] ?? exchange).toString(),
              assetClass: '期货',
              industry: (r['fut_code'] ?? '').toString(),
              listDate: (r['list_date'] ?? '').toString(),
            ))
        .toList();
  }

  Future<List<Instrument>> indexBasic({String market = 'SSE'}) async {
    final rows = await _post(
      apiName: 'index_basic',
      params: {'market': market},
      fields: 'ts_code,name,market,publisher,category,base_date,list_date',
    );
    return rows
        .map((r) => Instrument(
              tsCode: (r['ts_code'] ?? '').toString(),
              displaySymbol: (r['ts_code'] ?? '').toString(),
              name: (r['name'] ?? '').toString(),
              exchange: (r['market'] ?? '').toString(),
              assetClass: '指数',
              industry: (r['category'] ?? '').toString(),
              area: (r['publisher'] ?? '').toString(),
              listDate: (r['list_date'] ?? '').toString(),
            ))
        .toList();
  }

  // ── Quotes ──────────────────────────────────────────────────────────────

  Future<List<CandlePoint>> daily({
    required String tsCode,
    String? startDate, // YYYYMMDD
    String? endDate,
  }) =>
      _candleQuery(
        api: 'daily',
        tsCode: tsCode,
        startDate: startDate,
        endDate: endDate,
        fields:
            'ts_code,trade_date,open,high,low,close,pre_close,change,pct_chg,vol,amount',
      );

  Future<List<CandlePoint>> indexDaily({
    required String tsCode,
    String? startDate,
    String? endDate,
  }) =>
      _candleQuery(
        api: 'index_daily',
        tsCode: tsCode,
        startDate: startDate,
        endDate: endDate,
        fields:
            'ts_code,trade_date,close,open,high,low,pre_close,change,pct_chg,vol,amount',
      );

  Future<List<CandlePoint>> futDaily({
    required String tsCode,
    String? startDate,
    String? endDate,
  }) =>
      _candleQuery(
        api: 'fut_daily',
        tsCode: tsCode,
        startDate: startDate,
        endDate: endDate,
        fields:
            'ts_code,trade_date,open,high,low,close,pre_close,settle,change1,change2,vol,amount,oi',
      );

  Future<List<CandlePoint>> fundDaily({
    required String tsCode,
    String? startDate,
    String? endDate,
  }) =>
      _candleQuery(
        api: 'fund_daily',
        tsCode: tsCode,
        startDate: startDate,
        endDate: endDate,
        fields:
            'ts_code,trade_date,open,high,low,close,pre_close,change,pct_chg,vol,amount',
      );

  Future<List<CandlePoint>> _candleQuery({
    required String api,
    required String tsCode,
    String? startDate,
    String? endDate,
    required String fields,
  }) async {
    final params = <String, dynamic>{'ts_code': tsCode};
    if (startDate != null) params['start_date'] = startDate;
    if (endDate != null) params['end_date'] = endDate;

    final rows = await _post(apiName: api, params: params, fields: fields);
    final out = <CandlePoint>[];
    for (final r in rows) {
      final raw = (r['trade_date'] ?? '').toString();
      if (raw.length != 8) continue;
      final dt = DateTime(
        int.parse(raw.substring(0, 4)),
        int.parse(raw.substring(4, 6)),
        int.parse(raw.substring(6, 8)),
      );
      out.add(CandlePoint(
        date: dt,
        close: _toDouble(r['close']),
        open: _toDoubleOrNull(r['open']),
        high: _toDoubleOrNull(r['high']),
        low: _toDoubleOrNull(r['low']),
        pctChg: _toDoubleOrNull(r['pct_chg']),
      ));
    }
    out.sort((a, b) => a.date.compareTo(b.date));
    return out;
  }

  /// Smart router — picks the right `*_daily` API for the supplied symbol.
  Future<List<CandlePoint>> historyFor(String symbol,
      {DateTime? start, DateTime? end}) {
    final code = ChinaMarket.normalizeSymbol(symbol);
    final s = start != null ? _formatYmd(start) : null;
    final e = end != null ? _formatYmd(end) : null;
    if (ChinaMarket.isFuture(code)) {
      return futDaily(tsCode: code, startDate: s, endDate: e);
    }
    if (ChinaMarket.isIndex(code)) {
      return indexDaily(tsCode: code, startDate: s, endDate: e);
    }
    // ETF / fund codes use stock-style suffixes (.SH/.SZ); try fund first then daily.
    if (code.startsWith('5') || code.startsWith('1')) {
      return fundDaily(tsCode: code, startDate: s, endDate: e).then((rows) {
        if (rows.isNotEmpty) return rows;
        return daily(tsCode: code, startDate: s, endDate: e);
      });
    }
    return daily(tsCode: code, startDate: s, endDate: e);
  }

  // ── Utilities ───────────────────────────────────────────────────────────

  static double _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }

  static double? _toDoubleOrNull(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  static String _formatYmd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}'
      '${d.month.toString().padLeft(2, '0')}'
      '${d.day.toString().padLeft(2, '0')}';

  /// 启动预热：发起一个轻量请求，目的有两个——
  ///   1. 触发 iOS 中国地区首启时的"允许 App 使用 Wi-Fi 和蜂窝数据"系统弹窗，
  ///      避免用户首次发消息时 AI 请求直接失败；
  ///   2. 让 DNS / TLS / 长连接预先建立，AI 首条消息延迟更低。
  /// 失败完全静默，不阻塞 UI。
  Future<void> warmup() async {
    try {
      await _post(
        apiName: 'trade_cal',
        params: {
          'exchange': 'SSE',
          'is_open': '1',
          'limit': '1',
        },
        fields: 'cal_date',
      );
    } catch (_) {
      // 静默：联网失败/权限被拒等情况都不影响 app 启动。
    }
  }
}
