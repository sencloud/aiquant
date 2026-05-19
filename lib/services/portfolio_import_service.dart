import 'dart:convert';

import 'package:dio/dio.dart';

import '../core/api/api_client.dart';

/// /v1/portfolio/parse-screenshot 客户端封装。
///
/// 把券商 App 的"持仓"截图发给后端 qwen-vl 模型解析，返回结构化的
/// holdings 列表供用户在确认对话框里编辑后批量导入到当前组合。
class PortfolioImportService {
  PortfolioImportService();

  /// 解析持仓截图。
  ///
  /// [imageBytes] 是原始字节（jpg/png 都可，由 image_picker 返回）；
  /// 内部转 base64 + data: 前缀。
  Future<ParsedHoldingsResult> parseScreenshot({
    required List<int> imageBytes,
    String mimeType = 'image/png',
  }) async {
    final b64 = base64Encode(imageBytes);
    final resp = await ApiClient.instance.dio.post<Map<String, dynamic>>(
      '/v1/portfolio/parse-screenshot',
      data: {
        'image_base64': b64,
        'mime_type': mimeType,
      },
      options: Options(
        sendTimeout: const Duration(seconds: 60),
        receiveTimeout: const Duration(seconds: 60),
      ),
    );
    if (resp.statusCode != 200 || resp.data == null) {
      throw Exception('parse-screenshot 返回 ${resp.statusCode}');
    }
    final data = resp.data!;
    final holdings = (data['holdings'] as List? ?? const [])
        .whereType<Map>()
        .map((m) => ParsedHolding.fromJson(m.cast<String, dynamic>()))
        .toList();
    return ParsedHoldingsResult(
      brokerHint: (data['broker_hint'] as String?) ?? '',
      currency: (data['currency'] as String?) ?? 'CNY',
      holdings: holdings,
    );
  }
}

/// 后端 vision 返回的整张截图解析结果。
class ParsedHoldingsResult {
  ParsedHoldingsResult({
    required this.brokerHint,
    required this.currency,
    required this.holdings,
  });
  final String brokerHint;
  final String currency;
  final List<ParsedHolding> holdings;
}

/// 一行持仓的 JSON 反序列化形态；和 backend.qwen.ParsedHolding 字段一一对齐。
class ParsedHolding {
  ParsedHolding({
    required this.name,
    required this.code,
    required this.market,
    required this.quantity,
    required this.availableQty,
    required this.avgCost,
    required this.currentPrice,
    required this.marketValue,
    required this.pnl,
    required this.pnlPct,
  });

  factory ParsedHolding.fromJson(Map<String, dynamic> j) {
    double n(String k) {
      final v = j[k];
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v) ?? 0;
      return 0;
    }

    return ParsedHolding(
      name: (j['name'] as String?)?.trim() ?? '',
      code: (j['code'] as String?)?.trim() ?? '',
      market: (j['market'] as String?)?.trim() ?? '',
      quantity: n('quantity'),
      availableQty: n('available_qty'),
      avgCost: n('avg_cost'),
      currentPrice: n('current_price'),
      marketValue: n('market_value'),
      pnl: n('pnl'),
      pnlPct: n('pnl_pct'),
    );
  }

  final String name;
  final String code;
  final String market;
  final double quantity;
  final double availableQty;
  final double avgCost;
  final double currentPrice;
  final double marketValue;
  final double pnl;
  final double pnlPct;
}
