import 'package:dio/dio.dart';

import '../core/api/api_client.dart';
import '../models/ding.dart';

/// DingService 封装 /v1/ding/* 与 /v1/notifications/* 的 HTTP 调用。
class DingService {
  DingService({ApiClient? client}) : _client = client ?? ApiClient.instance;
  final ApiClient _client;

  Future<List<DingTask>> listTasks() async {
    final r = await _client.dio.get<Map<String, dynamic>>('/v1/ding/tasks');
    final items = (r.data!['items'] as List).cast<Map<String, dynamic>>();
    return items.map(DingTask.fromJson).toList();
  }

  Future<DingTask> createTask({
    required String title,
    required String prompt,
    required String schedule,
    String personaId = 'default',
    bool enabled = true,
    int costCreditsPerRun = 5,
  }) async {
    final r = await _client.dio.post<Map<String, dynamic>>(
      '/v1/ding/tasks',
      data: {
        'title': title,
        'prompt': prompt,
        'persona_id': personaId,
        'schedule': schedule,
        'enabled': enabled,
        'cost_credits_per_run': costCreditsPerRun,
      },
    );
    return DingTask.fromJson(r.data!);
  }

  Future<DingTask> updateTask(
    String uuid, {
    String? title,
    String? prompt,
    String? schedule,
    String? personaId,
    bool? enabled,
  }) async {
    final body = <String, dynamic>{};
    if (title != null) body['title'] = title;
    if (prompt != null) body['prompt'] = prompt;
    if (schedule != null) body['schedule'] = schedule;
    if (personaId != null) body['persona_id'] = personaId;
    if (enabled != null) body['enabled'] = enabled;
    final r = await _client.dio
        .patch<Map<String, dynamic>>('/v1/ding/tasks/$uuid', data: body);
    return DingTask.fromJson(r.data!);
  }

  Future<void> deleteTask(String uuid) async {
    await _client.dio.delete('/v1/ding/tasks/$uuid');
  }

  /// 服务端同步执行一次任务（唯一 LLM 工具 loop 路径）。
  ///
  /// 阻塞直到服务端完成一次完整对话 + 工具调用，返回新生成的 notification（若有）。
  Future<({DingMessage? notification})> runNow(String taskUuid) async {
    final r = await _client.dio.post<Map<String, dynamic>>(
      '/v1/ding/tasks/$taskUuid/run-now',
      options: Options(
        sendTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 180),
      ),
    );
    final body = r.data!;
    DingMessage? msg;
    if (body['notification'] is Map) {
      msg = DingMessage.fromJson(
          (body['notification'] as Map).cast<String, dynamic>());
    }
    return (notification: msg);
  }

  Future<({DingMessage? notification})> reportRun(
    String taskUuid, {
    required String status,
    required String title,
    required String content,
    String error = '',
    int totalTokens = 0,
    int durationMs = 0,
    DateTime? startedAt,
  }) async {
    final r = await _client.dio.post<Map<String, dynamic>>(
      '/v1/ding/tasks/$taskUuid/runs',
      data: {
        'task_uuid': taskUuid,
        'status': status,
        'title': title,
        'body_brief': '',
        'content': content,
        'error': error,
        'total_tokens': totalTokens,
        'duration_ms': durationMs,
        'started_at_ms': startedAt?.millisecondsSinceEpoch ?? 0,
      },
    );
    final body = r.data!;
    DingMessage? msg;
    if (body['notification'] is Map) {
      msg = DingMessage.fromJson(
          (body['notification'] as Map).cast<String, dynamic>());
    }
    return (notification: msg);
  }

  Future<({List<DingMessage> items, int nextCursor})> listNotifications({
    int cursor = 0,
    int limit = 30,
    bool unreadOnly = false,
  }) async {
    final r = await _client.dio.get<Map<String, dynamic>>(
      '/v1/notifications',
      queryParameters: {
        if (cursor > 0) 'cursor': cursor,
        'limit': limit,
        if (unreadOnly) 'unread_only': '1',
      },
    );
    final body = r.data!;
    final items = (body['items'] as List)
        .cast<Map<String, dynamic>>()
        .map(DingMessage.fromJson)
        .toList();
    return (
      items: items,
      nextCursor: (body['next_cursor'] as num).toInt(),
    );
  }

  Future<void> markRead(String uuid) async {
    await _client.dio.patch('/v1/notifications/$uuid/read');
  }

  Future<int> markAllRead() async {
    final r = await _client.dio
        .post<Map<String, dynamic>>('/v1/notifications/mark-all-read');
    return (r.data!['affected'] as num).toInt();
  }

  Future<int> unreadCount() async {
    final r = await _client.dio
        .get<Map<String, dynamic>>('/v1/notifications/unread-count');
    return (r.data!['unread'] as num).toInt();
  }

  Future<void> deleteNotification(String uuid) async {
    await _client.dio.delete('/v1/notifications/$uuid');
  }
}
