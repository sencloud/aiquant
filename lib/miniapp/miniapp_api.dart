import 'package:dio/dio.dart';

import '../core/api/api_client.dart';
import '../services/falsification_service.dart' show asApiException;
import 'miniapp_models.dart';

/// /v1/miniapps/* 客户端封装。测试里继承它覆盖方法即可。
class MiniAppApi {
  MiniAppApi({Dio? dio}) : _dioOverride = dio;

  final Dio? _dioOverride;
  Dio get _dio => _dioOverride ?? ApiClient.instance.dio;

  Future<T> _wrap<T>(Future<T> Function() f) async {
    try {
      return await f();
    } catch (e) {
      throw asApiException(e) ?? e;
    }
  }

  Map<String, dynamic> _d(Response<Map<String, dynamic>> r) =>
      r.data ?? const <String, dynamic>{};

  MiniApp _app(Map<String, dynamic> d) =>
      MiniApp.fromJson((d['app'] as Map?)?.cast<String, dynamic>() ?? const {});

  List<MiniApp> _apps(Map<String, dynamic> d) => [
        for (final e in (d['items'] as List? ?? const []))
          if (e is Map) MiniApp.fromJson(e.cast<String, dynamic>())
      ];

  // ── 公开（未登录可用）────────────────────────────────────────────────

  Future<MiniAppCatalog> catalog(String topic) => _wrap(() async {
        final r = await _dio.get<Map<String, dynamic>>('/v1/miniapps/catalog',
            queryParameters: {'topic': topic});
        return MiniAppCatalog.fromJson(_d(r));
      });

  Future<List<MiniAppTemplate>> templates(String topic) => _wrap(() async {
        final r = await _dio.get<Map<String, dynamic>>(
            '/v1/miniapps/templates',
            queryParameters: {'topic': topic});
        return [
          for (final e in (_d(r)['items'] as List? ?? const []))
            if (e is Map) MiniAppTemplate.fromJson(e.cast<String, dynamic>())
        ];
      });

  Future<MiniAppRun> runTemplate(String id, {Map<String, dynamic>? inputs}) =>
      _wrap(() async {
        final r = await _dio.post<Map<String, dynamic>>(
            '/v1/miniapps/templates/${Uri.encodeComponent(id)}/run',
            data: {if (inputs != null) 'inputs': inputs},
            options: Options(receiveTimeout: const Duration(seconds: 40)));
        return MiniAppRun.fromJson(_d(r));
      });

  // ── 需登录 ───────────────────────────────────────────────────────────

  Future<List<MiniApp>> list(String topic) => _wrap(() async {
        final r = await _dio.get<Map<String, dynamic>>('/v1/miniapps',
            queryParameters: {'topic': topic});
        return _apps(_d(r));
      });

  Future<MiniApp> get(String id) => _wrap(() async {
        final r = await _dio
            .get<Map<String, dynamic>>('/v1/miniapps/${Uri.encodeComponent(id)}');
        return _app(_d(r));
      });

  /// 发起一轮生成（扣喜点后立即返回 pending；用 [gen] 轮询）。返回生成记录与最新余额。
  Future<(MiniAppGen, int?)> generate({
    required String requestId,
    required String topic,
    required String message,
    String? appUuid,
    String? sessionId,
  }) =>
      _wrap(() async {
        final r = await _dio.post<Map<String, dynamic>>(
            '/v1/miniapps/generate',
            data: {
              'request_id': requestId,
              'topic': topic,
              'message': message,
              if (appUuid != null) 'app_uuid': appUuid,
              if (sessionId != null) 'session_id': sessionId,
            });
        final d = _d(r);
        return (
          MiniAppGen.fromJson((d['gen'] as Map?)?.cast<String, dynamic>() ?? const {}),
          (d['balance'] as num?)?.toInt(),
        );
      });

  Future<(MiniAppGen, int?)> gen(String requestId) => _wrap(() async {
        final r = await _dio.get<Map<String, dynamic>>(
            '/v1/miniapps/gens/${Uri.encodeComponent(requestId)}');
        final d = _d(r);
        return (
          MiniAppGen.fromJson((d['gen'] as Map?)?.cast<String, dynamic>() ?? const {}),
          (d['balance'] as num?)?.toInt(),
        );
      });

  Future<List<MiniAppGen>> session(String sessionId) => _wrap(() async {
        final r = await _dio.get<Map<String, dynamic>>(
            '/v1/miniapps/sessions/${Uri.encodeComponent(sessionId)}');
        return [
          for (final e in (_d(r)['items'] as List? ?? const []))
            if (e is Map) MiniAppGen.fromJson(e.cast<String, dynamic>())
        ];
      });

  Future<MiniApp> fromTemplate(String templateId) => _wrap(() async {
        final r = await _dio.post<Map<String, dynamic>>(
            '/v1/miniapps/from-template',
            data: {'template_id': templateId});
        return _app(_d(r));
      });

  Future<List<MiniApp>> reorder(String topic, List<String> ids) =>
      _wrap(() async {
        final r = await _dio.post<Map<String, dynamic>>(
            '/v1/miniapps/mounts/order',
            data: {'topic': topic, 'ids': ids});
        return _apps(_d(r));
      });

  Future<MiniApp> mount(String id, {String? cardSize}) => _wrap(() async {
        final r = await _dio.post<Map<String, dynamic>>(
            '/v1/miniapps/${Uri.encodeComponent(id)}/mount',
            data: {if (cardSize != null) 'card_size': cardSize});
        return _app(_d(r));
      });

  Future<void> unmount(String id) => _wrap(() async {
        await _dio.delete<Map<String, dynamic>>(
            '/v1/miniapps/${Uri.encodeComponent(id)}/mount');
      });

  Future<void> delete(String id) => _wrap(() async {
        await _dio.delete<Map<String, dynamic>>(
            '/v1/miniapps/${Uri.encodeComponent(id)}');
      });

  Future<MiniApp> rename(String id, {String? title, String? icon}) =>
      _wrap(() async {
        final r = await _dio.patch<Map<String, dynamic>>(
            '/v1/miniapps/${Uri.encodeComponent(id)}',
            data: {
              if (title != null) 'title': title,
              if (icon != null) 'icon': icon,
            });
        return _app(_d(r));
      });

  Future<List<Map<String, dynamic>>> versions(String id) => _wrap(() async {
        final r = await _dio.get<Map<String, dynamic>>(
            '/v1/miniapps/${Uri.encodeComponent(id)}/versions');
        return [
          for (final e in (_d(r)['items'] as List? ?? const []))
            if (e is Map) e.cast<String, dynamic>()
        ];
      });

  Future<MiniApp> restore(String id, int version) => _wrap(() async {
        final r = await _dio.post<Map<String, dynamic>>(
            '/v1/miniapps/${Uri.encodeComponent(id)}/restore',
            data: {'version': version});
        return _app(_d(r));
      });

  Future<MiniAppRun> run(String id, {Map<String, dynamic>? inputs}) =>
      _wrap(() async {
        final r = await _dio.post<Map<String, dynamic>>(
            '/v1/miniapps/${Uri.encodeComponent(id)}/run',
            data: {if (inputs != null) 'inputs': inputs},
            options: Options(receiveTimeout: const Duration(seconds: 40)));
        return MiniAppRun.fromJson(_d(r));
      });

  Future<void> saveState(String id,
          {required Map<String, dynamic> inputs,
          Map<String, dynamic>? state}) =>
      _wrap(() async {
        await _dio.post<Map<String, dynamic>>(
            '/v1/miniapps/${Uri.encodeComponent(id)}/state',
            data: {'inputs': inputs, 'state': state ?? const {}});
      });
}
