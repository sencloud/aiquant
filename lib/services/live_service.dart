import 'package:dio/dio.dart';

import '../core/api/api_client.dart';
import '../models/live.dart';

/// LiveService 封装 /v1/live/* 的 HTTP 调用(v2 直播间形态)。
class LiveService {
  LiveService({ApiClient? client}) : _client = client ?? ApiClient.instance;
  final ApiClient _client;

  /// 列直播间(最近 N 场,含 live + ended,按 started_at desc)。
  Future<List<LiveRoom>> listRooms({int limit = 20}) async {
    final r = await _client.dio.get<Map<String, dynamic>>(
      '/v1/live/rooms',
      queryParameters: {'limit': limit},
    );
    final items = (r.data!['items'] as List).cast<Map<String, dynamic>>();
    return items.map(LiveRoom.fromJson).toList();
  }

  /// 进入房间:一次性拉房间元信息 + 最近 recent 条消息(首屏初始化)。
  Future<LiveRoomDetail> getRoomDetail(String uuid, {int recent = 30}) async {
    final r = await _client.dio.get<Map<String, dynamic>>(
      '/v1/live/rooms/$uuid',
      queryParameters: {'recent': recent},
    );
    return LiveRoomDetail.fromJson(r.data!);
  }

  /// 增量轮询:返回 idx > sinceIdx 的新消息 + 当前房间状态 + 当前焦点。
  Future<LiveMessagesResponse> listMessagesSince(
    String uuid,
    int sinceIdx,
  ) async {
    final r = await _client.dio.get<Map<String, dynamic>>(
      '/v1/live/rooms/$uuid/messages',
      queryParameters: {'since_idx': sinceIdx},
    );
    return LiveMessagesResponse.fromJson(r.data!);
  }

  /// 拉 K 线 HTML 片段(self-contained,直接喂给 webview loadHtmlString)。
  ///
  /// 后端返回 text/html;客户端用 Options 强制以 plain 字符串接收。
  Future<String> fetchKlineHtml(String symbol) async {
    final r = await _client.dio.get<String>(
      '/v1/live/kline',
      queryParameters: {'symbol': symbol},
      options: Options(
        responseType: ResponseType.plain,
        headers: {'Accept': 'text/html'},
      ),
    );
    return r.data ?? '';
  }
}
