import 'package:dio/dio.dart';

import '../core/api/api_client.dart';
import '../core/api/auth_models.dart';
import '../core/api/billing_models.dart';

/// BillingService 封装 /v1/credits/* 的所有 HTTP 调用。
///
/// 只负责把后端响应翻译成强类型对象；状态管理在 BillingState。
class BillingService {
  BillingService({ApiClient? client}) : _client = client ?? ApiClient.instance;

  final ApiClient _client;
  Dio get _dio => _client.dio;

  Future<List<CreditSku>> listSkus() async {
    final r = await _dio.get<Map<String, dynamic>>('/v1/credits/skus');
    final items = (r.data!['items'] as List).cast<Map<String, dynamic>>();
    return items.map(CreditSku.fromJson).toList();
  }

  Future<int> getBalance() async {
    final r = await _dio.get<Map<String, dynamic>>('/v1/credits/balance');
    return (r.data!['balance'] as num).toInt();
  }

  Future<CreditOrder> createOrder({
    required String skuCode,
    String channel = 'apple_iap',
    String? clientRequestId,
  }) async {
    final reqId = clientRequestId ?? ApiClient.newRequestId();
    final r = await _dio.post<Map<String, dynamic>>(
      '/v1/credits/orders',
      data: {
        'sku_code': skuCode,
        'channel': channel,
        'client_request_id': reqId,
      },
    );
    return CreditOrder.fromJson(r.data!);
  }

  /// 验签并发币：返回 (订单, 最新余额)。
  Future<({CreditOrder order, int balance})> verifyIap({
    required String orderNo,
    required String jwsReceipt,
  }) async {
    final r = await _dio.post<Map<String, dynamic>>(
      '/v1/credits/iap/verify',
      data: {'order_no': orderNo, 'jws_receipt': jwsReceipt},
    );
    final body = r.data!;
    return (
      order: CreditOrder.fromJson(body['order'] as Map<String, dynamic>),
      balance: (body['balance'] as num).toInt(),
    );
  }

  /// dev 模式直冲：env=prod 时后端会拒绝。
  Future<int> devTopup({required int credits, String remark = ''}) async {
    final r = await _dio.post<Map<String, dynamic>>(
      '/v1/credits/dev/topup',
      data: {'credits': credits, 'remark': remark},
    );
    return (r.data!['balance'] as num).toInt();
  }

  Future<({List<CreditLedgerItem> items, int nextCursor})> listLedger({
    int cursor = 0,
    int limit = 30,
  }) async {
    final r = await _dio.get<Map<String, dynamic>>(
      '/v1/credits/ledger',
      queryParameters: {
        if (cursor > 0) 'cursor': cursor,
        'limit': limit,
      },
    );
    final body = r.data!;
    final items = (body['items'] as List)
        .cast<Map<String, dynamic>>()
        .map(CreditLedgerItem.fromJson)
        .toList();
    return (
      items: items,
      nextCursor: (body['next_cursor'] as num).toInt(),
    );
  }
}

/// 把 dio 抛出的 ApiException 提取出来，方便 UI 显示中文 message。
ApiException? extractApiException(Object error) {
  if (error is ApiException) return error;
  if (error is DioException) {
    final e = error.error;
    if (e is ApiException) return e;
  }
  return null;
}
