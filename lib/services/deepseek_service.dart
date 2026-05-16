import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/config/app_config.dart';
import '../models/chat.dart';

class DeepSeekException implements Exception {
  final String message;
  DeepSeekException(this.message);
  @override
  String toString() => 'DeepSeekException: $message';
}

/// 一次工具调用的增量片段。
/// SSE 流里 OpenAI 协议把同一个 tool_call 的 arguments 切碎成多次 delta，
/// service 层负责按 index 拼装好后再 yield 一个 [DeepSeekToolCallDelta]。
class DeepSeekToolCallDelta {
  final int index;
  final String? id;
  final String? name;
  final String? argumentsDelta;

  DeepSeekToolCallDelta({
    required this.index,
    this.id,
    this.name,
    this.argumentsDelta,
  });
}

class DeepSeekChunk {
  final String? delta;
  final String? reasoning;
  final List<DeepSeekToolCallDelta>? toolCalls;

  /// finish_reason: stop / tool_calls / length / null
  final String? finishReason;
  final bool done;
  final int? promptTokens;
  final int? completionTokens;
  final int? totalTokens;

  DeepSeekChunk({
    this.delta,
    this.reasoning,
    this.toolCalls,
    this.finishReason,
    this.done = false,
    this.promptTokens,
    this.completionTokens,
    this.totalTokens,
  });
}

/// 一轮聊天的入参之一：把 ChatMessage 转换成 OpenAI/DeepSeek 协议的 message 对象。
///
/// - role=user/system/assistant：常规
/// - role=assistant 且带 toolCalls：要带 tool_calls 字段
/// - role=tool：必须带 tool_call_id + name
Map<String, dynamic> chatMessageToOpenAi(ChatMessage m) {
  if (m.role == 'tool') {
    return {
      'role': 'tool',
      'tool_call_id': m.toolCallId ?? '',
      'name': m.name ?? '',
      'content': m.content,
    };
  }
  if (m.role == 'assistant') {
    final out = <String, dynamic>{
      'role': 'assistant',
      'content': m.content.isEmpty ? null : m.content,
    };
    final calls = m.toolCalls;
    if (calls != null && calls.isNotEmpty) {
      out['tool_calls'] = [for (final c in calls) c.toOpenAiJson()];
    }
    return out;
  }
  // user / system
  return {'role': m.role, 'content': m.content};
}

/// DeepSeek client — OpenAI-compatible Chat Completions with SSE streaming.
///
/// `deepseek-reasoner` (R) 不支持 tool_calls；当本轮启用 tools 时，service
/// 层会自动忽略调用方传入的 model 改用 `deepseek-chat`。
class DeepSeekService {
  /// 流式聊天。
  ///
  /// [messages] 是已经按 OpenAI 协议序列化好的对话消息（含 system/user/
  /// assistant/tool）。如果 [tools] 不空就走 tool-calling 模式（强制使用
  /// `deepseek-chat`，会忽略调用方传入的 model）。
  Stream<DeepSeekChunk> chatStreamRaw({
    required List<Map<String, dynamic>> messages,
    String? modelOverride,
    double temperature = 0.7,
    List<Map<String, dynamic>>? tools,
    String toolChoice = 'auto',
  }) async* {
    final cfg = AppConfig.instance;
    if (!cfg.hasDeepseekKey) {
      yield DeepSeekChunk(
        delta: '⚠️ 请先在"设置"中配置 DeepSeek API Key。',
        done: true,
      );
      return;
    }

    final hasTools = tools != null && tools.isNotEmpty;
    // tools + reasoner 不兼容；强制切换到 deepseek-chat
    final effectiveModel = hasTools
        ? BuiltInSecrets.chatDeepseekModel
        : (modelOverride ?? cfg.deepseekModel);

    final body = <String, dynamic>{
      'model': effectiveModel,
      'messages': messages,
      'stream': true,
      'temperature': temperature,
      if (hasTools) ...{
        'tools': tools,
        'tool_choice': toolChoice,
      },
    };

    final uri = Uri.parse('${BuiltInSecrets.deepseekBaseUrl}/v1/chat/completions');
    final client = http.Client();
    final req = http.Request('POST', uri)
      ..headers['Authorization'] = 'Bearer ${cfg.deepseekApiKey}'
      ..headers['Content-Type'] = 'application/json'
      ..headers['Accept'] = 'text/event-stream'
      ..body = jsonEncode(body);

    http.StreamedResponse resp;
    try {
      // reasoner 起手 + tools 时模型会"思考"较久（reasoning_content）
      // 初始 headers 等待时间放宽到 180s 避免在工具调用链中途被 timeout 切流
      resp = await client.send(req).timeout(const Duration(seconds: 180));
    } catch (e) {
      client.close();
      yield DeepSeekChunk(delta: '⚠️ 网络错误：$e', done: true);
      return;
    }

    if (resp.statusCode != 200) {
      final raw = await resp.stream.bytesToString();
      client.close();
      yield DeepSeekChunk(
        delta: '⚠️ DeepSeek 返回 ${resp.statusCode}: $raw',
        done: true,
      );
      return;
    }

    int? promptTokens;
    int? completionTokens;
    int? totalTokens;
    String? finishReason;

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

        // usage 可能在中间或结尾出现
        final usage = obj['usage'] as Map?;
        if (usage != null) {
          promptTokens = (usage['prompt_tokens'] as num?)?.toInt();
          completionTokens = (usage['completion_tokens'] as num?)?.toInt();
          totalTokens = (usage['total_tokens'] as num?)?.toInt();
        }

        final choices = obj['choices'] as List? ?? const [];
        if (choices.isEmpty) continue;
        final choice = choices.first as Map<String, dynamic>;

        final fr = choice['finish_reason'];
        if (fr is String) finishReason = fr;

        final delta = choice['delta'] as Map<String, dynamic>? ?? const {};
        final text = delta['content'] as String?;
        final reasoning = delta['reasoning_content'] as String?;
        final rawToolCalls = delta['tool_calls'] as List?;

        List<DeepSeekToolCallDelta>? tcDeltas;
        if (rawToolCalls != null && rawToolCalls.isNotEmpty) {
          tcDeltas = [
            for (final raw in rawToolCalls)
              if (raw is Map<String, dynamic>)
                DeepSeekToolCallDelta(
                  index: (raw['index'] as num?)?.toInt() ?? 0,
                  id: raw['id'] as String?,
                  name:
                      (raw['function'] as Map?)?['name'] as String?,
                  argumentsDelta:
                      (raw['function'] as Map?)?['arguments'] as String?,
                ),
          ];
        }

        if (text != null || reasoning != null || tcDeltas != null) {
          yield DeepSeekChunk(
            delta: text,
            reasoning: reasoning,
            toolCalls: tcDeltas,
          );
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
      finishReason: finishReason,
      promptTokens: promptTokens,
      completionTokens: completionTokens,
      totalTokens: totalTokens,
    );
  }
}
