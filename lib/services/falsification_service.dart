import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../core/api/api_client.dart';
import '../models/falsification.dart';

/// 证伪台数据的加载口。
///
/// 数据默认来自打包进 App 的资产（assets/strategy/falsification.json）——
/// 离线可用、首屏不用等网络、不会被接口故障拖垮。如果后端提供了
/// `GET /v1/strategy/falsification`（同一份 schema），就用远端覆盖本地：
/// 这样补一条证伪记录不用发版。远端拿不到时静默回落资产，不打扰用户。
class FalsificationService {
  FalsificationService({Dio? dio}) : _dio = dio ?? ApiClient.instance.dio;

  final Dio _dio;

  static const assetPath = 'assets/strategy/falsification.json';

  /// 缓存一次解析结果：证伪档案是研究结论，一天内不会变，没必要反复读盘。
  FalsificationData? _cache;
  String _origin = 'bundle';

  /// 数据来源：bundle（App 内置）或 remote（后端覆盖）。
  String get origin => _origin;

  Future<FalsificationData> load({bool preferRemote = true}) async {
    if (_cache != null) return _cache!;

    if (preferRemote) {
      final remote = await _tryRemote();
      if (remote != null) {
        _origin = 'remote';
        return _cache = remote;
      }
    }
    final raw = await rootBundle.loadString(assetPath);
    _origin = 'bundle';
    return _cache = FalsificationData.fromJson(
        json.decode(raw) as Map<String, dynamic>);
  }

  Future<FalsificationData?> _tryRemote() async {
    try {
      final resp = await _dio.get<Map<String, dynamic>>(
        '/v1/strategy/falsification',
        options: Options(
          // 这是个「有更好」的增强，不是必需路径：连不上就立刻用内置数据，
          // 不能让首屏卡在一个可选接口上。
          receiveTimeout: const Duration(seconds: 3),
          sendTimeout: const Duration(seconds: 3),
        ),
      );
      final data = resp.data;
      if (data == null || data['archive'] is! List) return null;
      return FalsificationData.fromJson(data);
    } catch (_) {
      return null;
    }
  }
}
