import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/config/app_config.dart';

class DeepSeekException implements Exception {
  final String message;
  DeepSeekException(this.message);
  @override
  String toString() => 'DeepSeekException: $message';
}

class DeepSeekChunk {
  final String? delta;
  final String? reasoning;
  final bool done;
  final int? promptTokens;
  final int? completionTokens;
  final int? totalTokens;

  DeepSeekChunk({
    this.delta,
    this.reasoning,
    this.done = false,
    this.promptTokens,
    this.completionTokens,
    this.totalTokens,
  });
}

class ChatTurn {
  final String role; // user / assistant / system
  final String content;
  ChatTurn(this.role, this.content);

  Map<String, dynamic> toJson() => {'role': role, 'content': content};
}

/// DeepSeek client — OpenAI-compatible Chat Completions with SSE streaming.
/// `deepseek-reasoner` (深度模式) returns an extra `reasoning_content` field
/// before the regular `content`; we surface it via [DeepSeekChunk.reasoning].
class DeepSeekService {
  /// Streams the assistant reply, yielding partial deltas as they arrive.
  /// Always closes with a final chunk where `done == true`.
  Stream<DeepSeekChunk> chatStream({
    required List<ChatTurn> history,
    String? systemPrompt,
    String? modelOverride,
    double temperature = 0.7,
  }) async* {
    final cfg = AppConfig.instance;
    if (!cfg.hasDeepseekKey) {
      yield DeepSeekChunk(
        delta: '⚠️ 请先在“设置”中配置 DeepSeek API Key。',
        done: true,
      );
      return;
    }

    final messages = <Map<String, dynamic>>[
      if (systemPrompt != null && systemPrompt.isNotEmpty)
        {'role': 'system', 'content': systemPrompt},
      ...history.map((m) => m.toJson()),
    ];

    final body = jsonEncode({
      'model': modelOverride ?? cfg.deepseekModel,
      'messages': messages,
      'stream': true,
      'temperature': temperature,
    });

    final uri = Uri.parse('${BuiltInSecrets.deepseekBaseUrl}/v1/chat/completions');
    final client = http.Client();
    final req = http.Request('POST', uri)
      ..headers['Authorization'] = 'Bearer ${cfg.deepseekApiKey}'
      ..headers['Content-Type'] = 'application/json'
      ..headers['Accept'] = 'text/event-stream'
      ..body = body;

    http.StreamedResponse resp;
    try {
      resp = await client.send(req).timeout(const Duration(seconds: 60));
    } catch (e) {
      client.close();
      yield DeepSeekChunk(delta: '⚠️ 网络错误：$e', done: true);
      return;
    }

    if (resp.statusCode != 200) {
      final raw = await resp.stream.bytesToString();
      client.close();
      yield DeepSeekChunk(
        delta: '⚠️ DeepSeek 返回 ${resp.statusCode}: ${raw.isEmpty ? "" : raw}',
        done: true,
      );
      return;
    }

    int? promptTokens;
    int? completionTokens;
    int? totalTokens;

    final stream = resp.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    String buffer = '';
    try {
      await for (final line in stream) {
        if (line.isEmpty) continue;
        if (!line.startsWith('data:')) continue;
        final payload = line.substring(5).trim();
        if (payload == '[DONE]') {
          break;
        }

        Map<String, dynamic> obj;
        try {
          obj = jsonDecode(payload) as Map<String, dynamic>;
        } catch (_) {
          buffer += payload;
          try {
            obj = jsonDecode(buffer) as Map<String, dynamic>;
            buffer = '';
          } catch (_) {
            continue;
          }
        }

        final choices = obj['choices'] as List? ?? const [];
        if (choices.isEmpty) {
          final usage = obj['usage'] as Map?;
          if (usage != null) {
            promptTokens = (usage['prompt_tokens'] as num?)?.toInt();
            completionTokens =
                (usage['completion_tokens'] as num?)?.toInt();
            totalTokens = (usage['total_tokens'] as num?)?.toInt();
          }
          continue;
        }
        final choice = choices.first as Map<String, dynamic>;
        final delta = choice['delta'] as Map<String, dynamic>? ?? {};
        final text = delta['content'] as String?;
        final reasoning = delta['reasoning_content'] as String?;
        final usage = obj['usage'] as Map?;
        if (usage != null) {
          promptTokens = (usage['prompt_tokens'] as num?)?.toInt();
          completionTokens = (usage['completion_tokens'] as num?)?.toInt();
          totalTokens = (usage['total_tokens'] as num?)?.toInt();
        }
        if (text != null || reasoning != null) {
          yield DeepSeekChunk(delta: text, reasoning: reasoning);
        }
      }
    } catch (e) {
      yield DeepSeekChunk(delta: '\n⚠️ 流读取异常：$e', done: true);
      client.close();
      return;
    }

    client.close();
    yield DeepSeekChunk(
      done: true,
      promptTokens: promptTokens,
      completionTokens: completionTokens,
      totalTokens: totalTokens,
    );
  }
}
