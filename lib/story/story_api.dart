import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart' as http_io;

import '../core/api/api_client.dart';
import '../core/config/app_config.dart';
import 'story_models.dart';

/// 服务端 story API 客户端。
///
/// 只做三件事：保存进度、拉回进度、流式聊天。剧情内容仍在客户端，
/// 服务端只存状态和消息；这样改文案不用发后端。
class StoryApi {
  StoryApi({http.Client? client}) : _client = client;

  final http.Client? _client;

  static const seasonId = 'before_dawn_s1';

  /// 打开试用版时先读一次远程开关；失败就用默认值，不挡用户。
  Future<StoryConfig> fetchConfig() async {
    final client = _client ?? http.Client();
    try {
      final resp = await client
          .get(_uri('/v1/story/config'))
          .timeout(const Duration(seconds: 2));
      if (resp.statusCode != 200) return StoryConfig.defaults;
      final json = (jsonDecode(resp.body) as Map).cast<String, dynamic>();
      return StoryConfig.fromJson(json);
    } catch (_) {
      return StoryConfig.defaults;
    } finally {
      if (_client == null) client.close();
    }
  }

  Future<String> _token() async {
    final token = await ApiClient.instance.ensureFreshAccessToken();
    if (token == null || token.isEmpty) {
      throw const StoryApiException('AUTH', '登录后才能接上 AI');
    }
    return token;
  }

  Uri _uri(String path) => Uri.parse('${AppConfig.instance.apiBaseUrl}$path');

  Future<void> saveRun(StoryRun run) async {
    final token = await _token();
    final body = jsonEncode({
      'season_id': seasonId,
      'character_id': run.characterId,
      'night': run.night,
      'beat': run.beat,
      'hearts': run.hearts,
      'flags': run.flags.toList(),
      'night_complete': run.nightComplete,
      'finished': run.finished,
      'ending_id': run.endingId ?? '',
    });
    final client = _client ?? http.Client();
    try {
      final resp = await client
          .put(
            _uri('/v1/story/runs/${run.id}'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: body,
          )
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode != 200) {
        throw StoryApiException(
          'HTTP_${resp.statusCode}',
          resp.body.isEmpty ? '进度没有存上' : resp.body,
        );
      }
    } finally {
      if (_client == null) client.close();
    }
  }

  /// 拉回当前账号最新一条故事线；没有则返回 null。
  Future<StorySave?> fetchState() async {
    final token = await _token();
    final client = _client ?? http.Client();
    try {
      final resp = await client.get(
        _uri('/v1/story/state'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 5));
      if (resp.statusCode != 200) return null;
      final root = jsonDecode(resp.body) as Map<String, dynamic>;
      final runJson = root['run'];
      if (runJson is! Map) return null;
      final run = StoryRun.fromJson(runJson.cast<String, dynamic>());
      final messages = (root['messages'] as List?)
              ?.map((e) =>
                  StoryMessage.fromJson((e as Map).cast<String, dynamic>()))
              .toList() ??
          const <StoryMessage>[];
      run.messages
        ..clear()
        ..addAll(messages);
      final endings =
          (root['endings'] as List?)?.cast<String>().toSet() ?? <String>{};
      return StorySave(
        introSeen: true,
        run: run,
        unlockedEndings: endings,
      );
    } catch (_) {
      return null;
    } finally {
      if (_client == null) client.close();
    }
  }

  Stream<StoryAiEvent> chat({
    required StoryRun run,
    required String message,
    required StoryScene scene,
  }) async* {
    final token = await _token();
    final body = jsonEncode({
      'message': message,
      'scene': scene.toJson(),
    });
    final client = http_io.IOClient(
      HttpClient()..findProxy = (uri) => 'DIRECT',
    );
    final req = http.Request(
      'POST',
      _uri('/v1/story/runs/${run.id}/chat'),
    )
      ..headers['Authorization'] = 'Bearer $token'
      ..headers['Content-Type'] = 'application/json'
      ..headers['Accept'] = 'text/event-stream'
      ..body = body;

    http.StreamedResponse resp;
    try {
      resp = await client.send(req).timeout(const Duration(seconds: 120));
    } catch (e) {
      client.close();
      throw StoryApiException('NETWORK', '网络错误：$e');
    }
    if (resp.statusCode != 200) {
      final raw = await resp.stream.bytesToString();
      client.close();
      throw StoryApiException('HTTP_${resp.statusCode}', raw);
    }

    String? event;
    final data = StringBuffer();
    try {
      await for (final line in resp.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        if (line.isEmpty) {
          if (event != null && data.isNotEmpty) {
            final ev = _parse(event, data.toString());
            if (ev != null) yield ev;
            if (ev?.kind == StoryAiEventKind.done ||
                ev?.kind == StoryAiEventKind.error) {
              return;
            }
          }
          event = null;
          data.clear();
          continue;
        }
        if (line.startsWith(':')) continue;
        if (line.startsWith('event:')) {
          event = line.substring(6).trim();
        } else if (line.startsWith('data:')) {
          data.write(line.substring(5).trim());
        }
      }
    } finally {
      client.close();
    }
  }

  StoryAiEvent? _parse(String event, String raw) {
    Map<String, dynamic> json;
    try {
      json = (jsonDecode(raw) as Map).cast<String, dynamic>();
    } catch (_) {
      return null;
    }
    switch (event) {
      case 'text_delta':
        return StoryAiEvent.delta(json['delta'] as String? ?? '');
      case 'done':
        return StoryAiEvent.done(
          json['text'] as String? ?? '',
          safety: json['safety'] as bool? ?? false,
        );
      case 'error':
        return StoryAiEvent.error(
          json['code'] as String? ?? 'STORY.ERROR',
          json['message'] as String? ?? 'AI 没有回答',
        );
      default:
        return null;
    }
  }
}

class StoryConfig {
  const StoryConfig({
    required this.enabled,
    required this.characters,
    required this.shareEnabled,
    required this.maxTurns,
    required this.notice,
  });

  static const defaults = StoryConfig(
    enabled: true,
    characters: {'linxia', 'suyu', 'chenye'},
    shareEnabled: true,
    maxTurns: 40,
    notice: '',
  );

  final bool enabled;
  final Set<String> characters;
  final bool shareEnabled;
  final int maxTurns;
  final String notice;

  factory StoryConfig.fromJson(Map<String, dynamic> json) {
    final chars = (json['characters'] as List?)?.cast<String>().toSet();
    return StoryConfig(
      enabled: json['enabled'] as bool? ?? true,
      characters: chars ?? const {'linxia', 'suyu', 'chenye'},
      shareEnabled: json['share_enabled'] as bool? ?? true,
      maxTurns: (json['max_turns'] as num?)?.toInt() ?? 40,
      notice: json['notice'] as String? ?? '',
    );
  }
}

class StoryScene {
  const StoryScene({
    required this.night,
    required this.beat,
    required this.beatId,
    required this.place,
    required this.scene,
    required this.beatNote,
    required this.opening,
  });

  final int night;
  final int beat;
  final String beatId;
  final String place;
  final String scene;
  final String beatNote;
  final List<String> opening;

  Map<String, dynamic> toJson() => {
        'night': night,
        'beat': beat,
        'beat_id': beatId,
        'place': place,
        'scene': scene,
        'beat_note': beatNote,
        'opening': opening,
      };
}

enum StoryAiEventKind { delta, done, error }

class StoryAiEvent {
  const StoryAiEvent._(this.kind, this.text, this.code, this.safety);

  factory StoryAiEvent.delta(String text) =>
      StoryAiEvent._(StoryAiEventKind.delta, text, '', false);

  factory StoryAiEvent.done(String text, {required bool safety}) =>
      StoryAiEvent._(StoryAiEventKind.done, text, '', safety);

  factory StoryAiEvent.error(String code, String message) =>
      StoryAiEvent._(StoryAiEventKind.error, message, code, false);

  final StoryAiEventKind kind;
  final String text;
  final String code;
  final bool safety;
}

class StoryApiException implements Exception {
  const StoryApiException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'StoryApiException($code): $message';
}
