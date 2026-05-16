import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../models/chat.dart';
import '../../../theme/app_theme.dart';

/// 工具调用卡：assistant 消息底部展示发起的 tool_call 列表 + 返回结果摘要。
class ToolCallList extends StatelessWidget {
  const ToolCallList({
    super.key,
    required this.calls,
    required this.findResult,
  });

  final List<ToolCall> calls;

  /// 根据 toolCallId 查找对应 role=tool 的 ChatMessage（可能尚未到达）
  final ChatMessage? Function(String toolCallId) findResult;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final c in calls)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: _ToolCallCard(call: c, result: findResult(c.id)),
            ),
        ],
      ),
    );
  }
}

class _ToolCallCard extends StatefulWidget {
  const _ToolCallCard({required this.call, required this.result});

  final ToolCall call;
  final ChatMessage? result;

  @override
  State<_ToolCallCard> createState() => _ToolCallCardState();
}

class _ToolCallCardState extends State<_ToolCallCard> {
  bool _expanded = false;

  bool get _running => widget.result?.streaming ?? widget.result == null;
  bool get _hasError {
    final r = widget.result;
    if (r == null || r.streaming) return false;
    final txt = r.content;
    if (txt.isEmpty) return false;
    try {
      final m = jsonDecode(txt);
      return m is Map && m['error'] != null;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = _hasError
        ? AppColors.negative
        : (_running ? AppColors.info : AppColors.positive);
    final argsPretty = _prettyJson(widget.call.argumentsJson);
    final resultPretty =
        widget.result == null ? '执行中…' : _prettyJson(widget.result!.content);

    return Material(
      color: AppColors.bgSurface,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: AppColors.borderDim),
        borderRadius: BorderRadius.circular(6),
      ),
      child: InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    _hasError
                        ? Icons.error_outline
                        : (_running
                            ? Icons.sync
                            : Icons.check_circle_outline),
                    size: 14,
                    color: accent,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    widget.call.name,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: accent,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _running ? '调用中…' : (_hasError ? '失败' : '完成'),
                      style: TextStyle(
                          fontSize: 10, color: AppColors.textTertiary),
                    ),
                  ),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: AppColors.textTertiary,
                  ),
                ],
              ),
              if (_expanded) ...[
                const SizedBox(height: 6),
                _kv('入参', argsPretty),
                const SizedBox(height: 6),
                _kv('结果', resultPretty),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _kv(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              color: AppColors.textTertiary,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 2),
          Container(
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.bgBase,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: AppColors.borderDim),
            ),
            child: SelectableText(
              value,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 10,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
          ),
        ],
      );

  static String _prettyJson(String raw) {
    if (raw.trim().isEmpty) return '(空)';
    try {
      final obj = jsonDecode(raw);
      return const JsonEncoder.withIndent('  ').convert(obj);
    } catch (_) {
      return raw;
    }
  }
}
