import 'package:dio/dio.dart';

import '../core/api/api_client.dart';
import '../models/strategy_snapshot.dart';

/// GET /v1/strategy/primary 的客户端封装。
///
/// 后端返回三种形态，这里都收敛成 [StrategySnapshot?]：
///   - available=true  → 返回快照
///   - available=false → 返回 null（首次同步还没跑完，UI 显示占位态）
///   - 网络/鉴权异常    → 抛 [StrategyException]，由 UI 显示重试
class StrategyService {
  StrategyService({Dio? dio}) : _dio = dio ?? ApiClient.instance.dio;

  final Dio _dio;

  Future<StrategySnapshot?> fetchPrimary() async {
    final Response<Map<String, dynamic>> resp;
    try {
      resp = await _dio.get<Map<String, dynamic>>('/v1/strategy/primary');
    } on DioException catch (e) {
      throw StrategyException(_message(e));
    }
    final data = resp.data;
    if (data == null) return null;
    if (data['available'] != true) return null;
    final snap = data['snapshot'];
    if (snap is! Map) return null;
    return StrategySnapshot.fromJson(snap.cast<String, dynamic>());
  }

  String _message(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['message'] is String) return data['message'] as String;
    final code = e.response?.statusCode;
    if (code == 401) return '登录已过期，请重新登录';
    return '策略数据获取失败，请稍后重试';
  }

  /// 策略目录（含"即将上线"的占位项）。失败时返回空列表——
  /// 目录是锦上添花，不该影响主策略的展示。
  Future<List<StrategyCatalogEntry>> fetchCatalog() async {
    try {
      final resp = await _dio
          .get<Map<String, dynamic>>('/v1/strategy/catalog');
      final list = resp.data?['strategies'];
      if (list is! List) return const [];
      return [
        for (final e in list)
          if (e is Map)
            StrategyCatalogEntry.fromJson(e.cast<String, dynamic>()),
      ];
    } catch (_) {
      return const [];
    }
  }
}

class StrategyException implements Exception {
  StrategyException(this.message);
  final String message;

  @override
  String toString() => message;
}
