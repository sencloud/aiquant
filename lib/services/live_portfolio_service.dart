import 'package:dio/dio.dart';

import '../core/api/api_client.dart';
import '../models/live_portfolio.dart';

/// GET /v1/portfolio/live —— 组合管理里的「实盘」系统组合（需登录）。
///
/// available=false（后端还没物化）返回 null；网络/鉴权错误抛出，由调用方
/// 决定是否提示——本地已有上一份时界面照常可用。
class LivePortfolioService {
  LivePortfolioService({Dio? dio}) : _dio = dio;

  final Dio? _dio;

  Future<LivePortfolio?> fetch() async {
    final dio = _dio ?? ApiClient.instance.dio;
    final resp = await dio.get<Map<String, dynamic>>('/v1/portfolio/live');
    final data = resp.data;
    if (data == null || data['available'] != true) return null;
    final p = data['portfolio'];
    if (p is! Map) return null;
    final lp = LivePortfolio.fromJson(p.cast<String, dynamic>());
    if (lp.id.isEmpty) return null;
    return lp;
  }
}
