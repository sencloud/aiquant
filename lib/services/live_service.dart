import '../core/api/api_client.dart';
import '../models/live.dart';

/// LiveService 封装 /v1/live/* 的 HTTP 调用。
class LiveService {
  LiveService({ApiClient? client}) : _client = client ?? ApiClient.instance;
  final ApiClient _client;

  Future<List<LiveSession>> listSessions({int limit = 20}) async {
    final r = await _client.dio.get<Map<String, dynamic>>(
      '/v1/live/sessions',
      queryParameters: {'limit': limit},
    );
    final items = (r.data!['items'] as List).cast<Map<String, dynamic>>();
    return items.map(LiveSession.fromJson).toList();
  }

  Future<LiveSession> getSession(String uuid) async {
    final r = await _client.dio
        .get<Map<String, dynamic>>('/v1/live/sessions/$uuid');
    return LiveSession.fromJson(r.data!);
  }

  Future<LiveReportFull> getReport(int id) async {
    final r =
        await _client.dio.get<Map<String, dynamic>>('/v1/live/reports/$id');
    return LiveReportFull.fromJson(r.data!);
  }

  Future<List<LiveReportBrief>> listReportsBySymbol(
    String symbol, {
    int limit = 12,
  }) async {
    final r = await _client.dio.get<Map<String, dynamic>>(
      '/v1/live/symbols/$symbol',
      queryParameters: {'limit': limit},
    );
    final items = (r.data!['items'] as List).cast<Map<String, dynamic>>();
    return items.map(LiveReportBrief.fromJson).toList();
  }

  Future<List<LiveWatchItem>> listWatch() async {
    final r = await _client.dio.get<Map<String, dynamic>>('/v1/live/watchlist');
    final items = (r.data!['items'] as List).cast<Map<String, dynamic>>();
    return items.map(LiveWatchItem.fromJson).toList();
  }

  Future<void> addWatch(String symbol, {String name = ''}) async {
    await _client.dio.post('/v1/live/watchlist', data: {
      'symbol': symbol,
      'name': name,
    });
  }

  Future<void> removeWatch(String symbol) async {
    await _client.dio.delete('/v1/live/watchlist/$symbol');
  }
}
