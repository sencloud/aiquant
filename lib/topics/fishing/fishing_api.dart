import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../core/api/api_client.dart';
import '../../services/falsification_service.dart' show asApiException;
import 'fishing_models.dart';

/// /v1/fishing/* 客户端封装。测试里继承它覆盖方法即可。
class FishingApi {
  FishingApi({Dio? dio}) : _dioOverride = dio;

  final Dio? _dioOverride;
  Dio get _dio => _dioOverride ?? ApiClient.instance.dio;

  Future<T> _wrap<T>(Future<T> Function() f) async {
    try {
      return await f();
    } catch (e) {
      throw asApiException(e) ?? e;
    }
  }

  /// 出钓指数：place 或 lat/lon 二选一。
  Future<FishingForecast> forecast(
      {String? place, double? lat, double? lon, String? name, int days = 3}) {
    return _wrap(() async {
      final q = <String, dynamic>{'days': days};
      if (lat != null && lon != null) {
        q['lat'] = lat;
        q['lon'] = lon;
        if (name != null && name.isNotEmpty) q['name'] = name;
      } else {
        q['place'] = place ?? '';
      }
      final r = await _dio.get<Map<String, dynamic>>('/v1/fishing/forecast',
          queryParameters: q,
          options: Options(receiveTimeout: const Duration(seconds: 40)));
      return FishingForecast.fromJson(r.data ?? const {});
    });
  }

  Future<FishingRegulations> regulations() => _wrap(() async {
        final r =
            await _dio.get<Map<String, dynamic>>('/v1/fishing/regulations');
        return FishingRegulations.fromJson(r.data ?? const {});
      });

  /// 拍照识鱼（3 喜点；同一 requestId 重试不重复扣费）。返回识别结果和最新余额。
  Future<(FishIdentification, int?)> identify(
          {required String requestId, required Uint8List jpeg}) =>
      _wrap(() async {
        final r = await _dio.post<Map<String, dynamic>>(
          '/v1/fishing/identify',
          data: {
            'request_id': requestId,
            'image': 'data:image/jpeg;base64,${base64Encode(jpeg)}',
          },
          options: Options(
            sendTimeout: const Duration(seconds: 60),
            receiveTimeout: const Duration(seconds: 70),
          ),
        );
        final d = r.data ?? const {};
        return (
          FishIdentification.fromJson(
              (d['identification'] as Map?)?.cast<String, dynamic>() ??
                  const {}),
          (d['balance'] as num?)?.toInt(),
        );
      });

  Future<(List<FishCatch>, CatchStats?)> catches({int? before}) =>
      _wrap(() async {
        final r = await _dio.get<Map<String, dynamic>>('/v1/fishing/catches',
            queryParameters: {if (before != null) 'before': before});
        final d = r.data ?? const {};
        final items = (d['items'] as List? ?? const [])
            .whereType<Map>()
            .map((m) => FishCatch.fromJson(m.cast<String, dynamic>()))
            .toList();
        final st = d['stats'] is Map
            ? CatchStats.fromJson((d['stats'] as Map).cast<String, dynamic>())
            : null;
        return (items, st);
      });

  Future<FishCatch> createCatch(Map<String, dynamic> body) => _wrap(() async {
        final r = await _dio.post<Map<String, dynamic>>('/v1/fishing/catches',
            data: body,
            options: Options(sendTimeout: const Duration(seconds: 60)));
        return FishCatch.fromJson(
            (r.data?['catch'] as Map).cast<String, dynamic>());
      });

  Future<void> deleteCatch(String uuid) =>
      _wrap(() => _dio.delete<dynamic>('/v1/fishing/catches/$uuid'));

  Future<Uint8List> catchPhoto(String uuid) => _wrap(() async {
        final r = await _dio.get<List<int>>('/v1/fishing/catches/$uuid/photo',
            options: Options(responseType: ResponseType.bytes));
        return Uint8List.fromList(r.data ?? const []);
      });

  Future<List<FishingSpot>> spots() => _wrap(() async {
        final r = await _dio.get<Map<String, dynamic>>('/v1/fishing/spots');
        return (r.data?['items'] as List? ?? const [])
            .whereType<Map>()
            .map((m) => FishingSpot.fromJson(m.cast<String, dynamic>()))
            .toList();
      });

  Future<FishingSpot> saveSpot(Map<String, dynamic> body, {String? uuid}) =>
      _wrap(() async {
        final r = uuid == null
            ? await _dio.post<Map<String, dynamic>>('/v1/fishing/spots',
                data: body)
            : await _dio.patch<Map<String, dynamic>>('/v1/fishing/spots/$uuid',
                data: body);
        return FishingSpot.fromJson(
            (r.data?['spot'] as Map).cast<String, dynamic>());
      });

  Future<void> deleteSpot(String uuid) =>
      _wrap(() => _dio.delete<dynamic>('/v1/fishing/spots/$uuid'));
}
