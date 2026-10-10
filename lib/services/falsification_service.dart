import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../core/api/api_client.dart';
import '../core/api/auth_models.dart';
import '../models/falsification.dart';

/// 证伪档案的加载口 + 付费动作（解锁详情 / 跑一次证伪）。
///
/// 档案优先读后端 `GET /v1/strategy/falsification`（免登录；带 token 时
/// 已解锁条目会直接带上付费字段），3 秒拿不到就回落打包进 App 的资产
/// （assets/strategy/falsification.json）—— 离线可用、首屏不被接口拖垮。
/// 后端档案由 alpha-radar 定时同步，补一条证伪记录不用发版。
class FalsificationService {
  FalsificationService({Dio? dio}) : _dioOverride = dio;

  /// 列表页、详情页、下单页共用一份缓存（解锁后的条目回写到这里）。
  static final FalsificationService shared = FalsificationService();

  final Dio? _dioOverride;
  Dio get _dio => _dioOverride ?? ApiClient.instance.dio;

  static const assetPath = 'assets/strategy/falsification.json';

  /// 缓存一次解析结果：证伪档案一天内变化不大，没必要反复读盘。
  FalsificationData? _cache;
  String _origin = 'bundle';

  /// 数据来源：bundle（App 内置）或 remote（后端，含后端 seed）。
  String get origin => _origin;

  /// 最近一次加载的档案（没加载过为 null）。
  FalsificationData? get cached => _cache;

  Future<FalsificationData> load({
    bool preferRemote = true,
    bool force = false,
  }) async {
    if (_cache != null && !force) return _cache!;

    if (preferRemote) {
      final remote = await _tryRemote();
      if (remote != null) {
        _origin = 'remote';
        return _cache = remote;
      }
    }
    if (_cache != null) return _cache!;
    final raw = await rootBundle.loadString(assetPath);
    _origin = 'bundle';
    return _cache =
        FalsificationData.fromJson(json.decode(raw) as Map<String, dynamic>);
  }

  /// 把一条解锁后的完整条目写回缓存。
  void cacheEntry(ArchiveEntry e) {
    final c = _cache;
    if (c != null) _cache = c.replaceEntry(e);
  }

  Future<FalsificationData?> _tryRemote() async {
    try {
      final resp = await _dio.get<Map<String, dynamic>>(
        '/v1/strategy/falsification',
        // 搜索要能搜到样本不足的条目：一次全拿，主列表在客户端过滤。
        queryParameters: const {'include': 'insufficient'},
        options: Options(
          // 这是个「有更好」的增强，不是必需路径：连不上就立刻用内置数据。
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

  // ── 解锁详情（需登录）────────────────────────────────────────────────

  /// 已解锁的条目 id。
  Future<Set<String>> unlockedIds() async {
    final r = await _dio
        .get<Map<String, dynamic>>('/v1/strategy/falsification/unlocks');
    final ids = r.data?['ids'];
    return ids is List ? {for (final i in ids) '$i'} : <String>{};
  }

  /// 解锁一条（幂等：已解锁不重复扣费）。余额不足抛
  /// ApiException(code: FALSIFICATION.INSUFFICIENT_BALANCE, statusCode: 402)。
  Future<UnlockResult> unlock(String id) async {
    try {
      final r = await _dio.post<Map<String, dynamic>>(
          '/v1/strategy/falsification/${Uri.encodeComponent(id)}/unlock');
      final d = r.data ?? const {};
      final entry = ArchiveEntry.fromJson(
          (d['entry'] as Map?)?.cast<String, dynamic>() ?? const {});
      final res = UnlockResult(
        entry: entry,
        charged: (d['charged'] as num?)?.toInt() ?? 0,
        balance: (d['balance'] as num?)?.toInt(),
      );
      cacheEntry(entry);
      return res;
    } catch (e) {
      throw asApiException(e) ?? e;
    }
  }

  /// 已解锁条目的完整内容（未解锁返回 402/403 时抛 ApiException）。
  Future<ArchiveEntry> detail(String id) async {
    try {
      final r = await _dio.get<Map<String, dynamic>>(
          '/v1/strategy/falsification/${Uri.encodeComponent(id)}/detail');
      final d = r.data ?? const {};
      final raw = d['entry'] is Map ? d['entry'] : d;
      final entry = ArchiveEntry.fromJson((raw as Map).cast<String, dynamic>());
      cacheEntry(entry);
      return entry;
    } catch (e) {
      throw asApiException(e) ?? e;
    }
  }

  // ── 跑一次证伪（需登录）──────────────────────────────────────────────

  Future<RunOptions> runOptions() async {
    final r = await _dio
        .get<Map<String, dynamic>>('/v1/strategy/falsification/run-options');
    return RunOptions.fromJson(r.data ?? const {});
  }

  Future<({FalsificationRun run, int? balance})> createRun({
    required String strategy,
    required String symbol,
    required String freq,
  }) async {
    try {
      final r = await _dio.post<Map<String, dynamic>>(
        '/v1/strategy/falsification/runs',
        data: {'strategy': strategy, 'symbol': symbol, 'freq': freq},
      );
      final d = r.data ?? const {};
      return (
        run: FalsificationRun.fromJson(
            (d['run'] as Map?)?.cast<String, dynamic>() ?? const {}),
        balance: (d['balance'] as num?)?.toInt(),
      );
    } catch (e) {
      throw asApiException(e) ?? e;
    }
  }

  Future<FalsificationRun> getRun(String id) async {
    final r = await _dio.get<Map<String, dynamic>>(
        '/v1/strategy/falsification/runs/${Uri.encodeComponent(id)}');
    return FalsificationRun.fromJson(
        (r.data?['run'] as Map?)?.cast<String, dynamic>() ?? const {});
  }
}

/// 从 Dio 异常里取出后端的 ApiException（code / message）。
ApiException? asApiException(Object e) {
  if (e is ApiException) return e;
  if (e is DioException && e.error is ApiException) {
    return e.error as ApiException;
  }
  return null;
}

class UnlockResult {
  const UnlockResult(
      {required this.entry, required this.charged, this.balance});
  final ArchiveEntry entry;
  final int charged;
  final int? balance;
}
