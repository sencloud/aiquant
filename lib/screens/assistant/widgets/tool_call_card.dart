import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../models/chat.dart';
import '../../../theme/app_theme.dart';

/// 一轮回答里调用过哪些工具。
///
/// 默认只显示一行摘要（豆包那种「已处理 3.2 秒 · 6 个工具」），点开才列出
/// 每一个工具；再点某一行才展开它的入参与结果。工具名对用户没有意义，
/// 所以统一换成中文动作名，原始名只在展开后的详情里出现。
class ToolCallSummary extends StatefulWidget {
  const ToolCallSummary({
    super.key,
    required this.calls,
    required this.findResult,
    this.durationMs,
  });

  final List<ToolCall> calls;

  /// 根据 toolCallId 查找对应 role=tool 的 ChatMessage（可能尚未到达）
  final ChatMessage? Function(String toolCallId) findResult;

  /// 这一轮回答的总耗时（毫秒），未知时传 null。
  final int? durationMs;

  @override
  State<ToolCallSummary> createState() => _ToolCallSummaryState();
}

class _ToolCallSummaryState extends State<ToolCallSummary> {
  bool _expanded = false;
  final Set<String> _openIds = <String>{};

  bool _isRunning(String id) {
    final r = widget.findResult(id);
    return r == null || r.streaming;
  }

  bool get _anyRunning => widget.calls.any((c) => _isRunning(c.id));

  bool _hasError(String id) {
    final r = widget.findResult(id);
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
    final count = widget.calls.length;
    final summary = _anyRunning
        ? '正在处理…'
        : '已处理 ${_fmtDuration(widget.durationMs)}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          key: const ValueKey('chat-tool-summary'),
          borderRadius: BorderRadius.circular(AppRadius.sm),
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                _anyRunning
                    ? SizedBox(
                        width: 13,
                        height: 13,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.6,
                          color: AppColors.amber,
                        ),
                      )
                    : Icon(
                        Icons.auto_awesome_rounded,
                        size: 14,
                        color: AppColors.amber,
                      ),
                const SizedBox(width: 6),
                Text(
                  summary,
                  style: AppType.caption.copyWith(
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                Text(
                  ' · $count 个工具',
                  style: AppType.caption.copyWith(
                    fontSize: 12.5,
                    color: AppColors.textTertiary,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  _expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 18,
                  color: AppColors.textTertiary,
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topLeft,
          child: !_expanded
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: 2, bottom: 6),
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.bgBase,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 2,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < widget.calls.length; i++) ...[
                          if (i > 0)
                            Divider(
                              height: 0.5,
                              thickness: 0.5,
                              color: AppColors.borderDim,
                            ),
                          _toolRow(widget.calls[i]),
                        ],
                      ],
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _toolRow(ToolCall call) {
    final running = _isRunning(call.id);
    final failed = _hasError(call.id);
    final open = _openIds.contains(call.id);
    final tone = failed
        ? AppColors.danger
        : (running ? AppColors.info : AppColors.textSecondary);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() {
            if (open) {
              _openIds.remove(call.id);
            } else {
              _openIds.add(call.id);
            }
          }),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(
              children: [
                Icon(
                  failed
                      ? Icons.error_outline_rounded
                      : running
                          ? Icons.more_horiz_rounded
                          : Icons.check_rounded,
                  size: 14,
                  color: tone,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    toolLabel(call.name),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.caption.copyWith(
                      fontSize: 12.5,
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Text(
                  running
                      ? '进行中'
                      : failed
                          ? '未完成'
                          : '完成',
                  style: AppType.micro.copyWith(
                    fontSize: 11,
                    color: tone,
                  ),
                ),
                const SizedBox(width: 2),
                Icon(
                  open
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 16,
                  color: AppColors.textTertiary,
                ),
              ],
            ),
          ),
        ),
        if (open)
          Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 20),
            child: _detail(call),
          ),
      ],
    );
  }

  Widget _detail(ToolCall call) {
    final result = widget.findResult(call.id);
    final resultText =
        result == null ? '执行中…' : _prettyJson(result.content);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _kv('参数', _prettyJson(call.argumentsJson)),
        const SizedBox(height: 6),
        _kv('结果', resultText),
      ],
    );
  }

  Widget _kv(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppType.micro.copyWith(
              fontSize: 10,
              color: AppColors.textTertiary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 2),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.bgSurface,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: AppColors.borderDim),
            ),
            child: SelectableText(
              value,
              maxLines: 12,
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

/// 工具名 → 用户看得懂的动作名。没收录的按原样展示（下划线换成空格）。
String toolLabel(String name) {
  final known = _toolLabels[name];
  if (known != null) return known;
  if (name.startsWith('search_web')) return '联网搜索';
  return name.replaceAll('_', ' ');
}

const Map<String, String> _toolLabels = {
  'get_realtime_quote': '拉取实时行情',
  'get_realtime_quotes': '拉取实时行情',
  'get_quote': '读取行情快照',
  'get_valuation': '对比估值',
  'get_industry_news': '查行业新闻',
  'search_global_events': '查国际市场事件',
  'get_us_stock_realtime_batch': '拉取美股实时行情',
  'get_us_stock_quote': '读取美股行情',
  'get_dominant_contract': '查主力合约',
  'get_cn_news': '查中文新闻',
  'get_market_brief': '读取行情简报',
  'search_web': '联网搜索',
  'search_web_news': '联网搜新闻',
};

String _fmtDuration(int? ms) {
  if (ms == null || ms <= 0) return '一会儿';
  if (ms < 1000) return '${ms}ms';
  final seconds = ms / 1000;
  if (seconds < 60) {
    return seconds < 10
        ? '${seconds.toStringAsFixed(1)} 秒'
        : '${seconds.round()} 秒';
  }
  final minutes = seconds ~/ 60;
  final rest = (seconds % 60).round();
  return '$minutes 分 $rest 秒';
}
