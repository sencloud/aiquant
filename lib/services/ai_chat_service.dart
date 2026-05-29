import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart' as http_io;

import '../core/api/api_client.dart';
import '../core/config/app_config.dart';

/// /v1/ai/chat SSE 客户端。
///
/// 服务端事件协议：
///   event: session       data: { session_id, persona, balance }
///   event: text_delta    data: { delta }
///   event: tool_call     data: { id, name, arguments }
///   event: tool_result   data: { id, name, result }
///   event: done          data: { session_id, final_text, tool_calls, credits, balance_after }
///   event: error         data: { code, message }
class AiChatService {
  AiChatService();

  /// 发起一次流式对话；调用方根据 [AiChatEvent.kind] 渲染 UI / 更新本地状态。
  ///
  /// - [serverSessionId] 为空 → 服务端新建一个 session（done/session 事件返回 id）
  /// - 客户端在 abort 时取消订阅即可，[client.close()] 由 stream 内部 onDone 兜底
  Stream<AiChatEvent> stream({
    String? serverSessionId,
    required String message,
    String? persona,
    bool deepMode = false,
    String? systemHint,
    Map<String, dynamic>? portfolioContext,
  }) async* {
    final cfg = AppConfig.instance;
    // SSE 走裸 http 绕过了 dio 拦截器，必须在这里主动续签：
    // access TTL 仅 15 分钟，多聊几轮后若不刷新就会带着过期 token 发出，
    // 后端 JWTMiddleware 返回 401 AUTH.TOKEN_INVALID: token is expired。
    final accessToken = await ApiClient.instance.ensureFreshAccessToken();
    if (accessToken == null) {
      yield AiChatEvent.error('AUTH.EXPIRED', '登录已过期，请重新登录');
      return;
    }

    final uri = Uri.parse('${cfg.apiBaseUrl}/v1/ai/chat');
    final body = <String, dynamic>{
      if (serverSessionId != null && serverSessionId.isNotEmpty)
        'session_id': serverSessionId,
      if (persona != null && persona.isNotEmpty) 'persona': persona,
      if (deepMode) 'deep_mode': true,
      if (systemHint != null && systemHint.isNotEmpty)
        'system_hint': systemHint,
      if (portfolioContext != null && portfolioContext.isNotEmpty)
        'portfolio_context': portfolioContext,
      'message': message,
    };

    final client = http_io.IOClient(
      HttpClient()..findProxy = (uri) => 'DIRECT',
    );
    final req = http.Request('POST', uri)
      ..headers['Authorization'] = 'Bearer $accessToken'
      ..headers['Content-Type'] = 'application/json'
      ..headers['Accept'] = 'text/event-stream'
      ..body = jsonEncode(body);

    http.StreamedResponse resp;
    try {
      resp = await client.send(req).timeout(const Duration(seconds: 180));
    } catch (e) {
      client.close();
      yield AiChatEvent.error('NETWORK', '网络错误：$e');
      return;
    }

    if (resp.statusCode != 200) {
      final raw = await resp.stream.bytesToString();
      client.close();
      String code = 'HTTP_${resp.statusCode}';
      String msg = raw.isEmpty ? '服务端返回 ${resp.statusCode}' : raw;
      try {
        final m = jsonDecode(raw);
        if (m is Map) {
          code = (m['code'] as String?) ?? code;
          msg = (m['message'] as String?) ?? msg;
        }
      } catch (_) {}
      yield AiChatEvent.error(code, msg);
      return;
    }

    String? eventName;
    final dataBuf = StringBuffer();

    try {
      await for (final line in resp.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        if (line.isEmpty) {
          // 一条 event 结束（按 SSE 协议）
          if (eventName != null && dataBuf.isNotEmpty) {
            final ev = _parse(eventName, dataBuf.toString());
            if (ev != null) yield ev;
          }
          eventName = null;
          dataBuf.clear();
          continue;
        }
        if (line.startsWith(':')) continue;
        if (line.startsWith('event:')) {
          eventName = line.substring(6).trim();
        } else if (line.startsWith('data:')) {
          if (dataBuf.isNotEmpty) dataBuf.write('\n');
          dataBuf.write(line.substring(5).trim());
        }
      }
      // 流末尾若残留一段未空行结束的事件，补 emit 一次
      if (eventName != null && dataBuf.isNotEmpty) {
        final ev = _parse(eventName, dataBuf.toString());
        if (ev != null) yield ev;
      }
    } catch (e) {
      yield AiChatEvent.error('STREAM_READ', '流读取异常：$e');
    } finally {
      client.close();
    }
  }

  AiChatEvent? _parse(String name, String raw) {
    Map<String, dynamic> data;
    try {
      data = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
    switch (name) {
      case 'session':
        return AiChatEvent(
          kind: AiChatEventKind.session,
          sessionId: data['session_id'] as String?,
          persona: data['persona'] as String?,
          balance: (data['balance'] as num?)?.toInt(),
        );
      case 'text_delta':
        return AiChatEvent(
          kind: AiChatEventKind.textDelta,
          delta: data['delta'] as String?,
        );
      case 'tool_call':
        return AiChatEvent(
          kind: AiChatEventKind.toolCall,
          toolCallId: data['id'] as String?,
          toolName: data['name'] as String?,
          toolArguments: data['arguments'] as String?,
        );
      case 'tool_result':
        return AiChatEvent(
          kind: AiChatEventKind.toolResult,
          toolCallId: data['id'] as String?,
          toolName: data['name'] as String?,
          toolResult: data['result'] as String?,
        );
      case 'done':
        return AiChatEvent(
          kind: AiChatEventKind.done,
          sessionId: data['session_id'] as String?,
          finalText: data['final_text'] as String?,
          toolCalls: (data['tool_calls'] as num?)?.toInt(),
          credits: (data['credits'] as num?)?.toInt(),
          balanceAfter: (data['balance_after'] as num?)?.toInt(),
        );
      case 'error':
        return AiChatEvent(
          kind: AiChatEventKind.error,
          errorCode: (data['code'] as String?) ?? 'UNKNOWN',
          errorMessage: (data['message'] as String?) ?? '未知错误',
          // INSUFFICIENT_BALANCE 时后端会同时下发 balance / estimate
          balance: (data['balance'] as num?)?.toInt(),
          balanceAfter: (data['balance'] as num?)?.toInt(),
        );
    }
    return null;
  }
}

enum AiChatEventKind { session, textDelta, toolCall, toolResult, done, error }

class AiChatEvent {
  AiChatEvent({
    required this.kind,
    this.sessionId,
    this.persona,
    this.balance,
    this.delta,
    this.toolCallId,
    this.toolName,
    this.toolArguments,
    this.toolResult,
    this.finalText,
    this.toolCalls,
    this.credits,
    this.balanceAfter,
    this.errorCode,
    this.errorMessage,
  });

  factory AiChatEvent.error(String code, String message) => AiChatEvent(
        kind: AiChatEventKind.error,
        errorCode: code,
        errorMessage: message,
      );

  final AiChatEventKind kind;

  final String? sessionId;
  final String? persona;
  final int? balance;

  final String? delta;

  final String? toolCallId;
  final String? toolName;
  final String? toolArguments;
  final String? toolResult;

  final String? finalText;
  final int? toolCalls;
  final int? credits;
  final int? balanceAfter;

  final String? errorCode;
  final String? errorMessage;
}
