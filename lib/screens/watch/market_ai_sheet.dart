import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../models/market_period.dart';
import '../../services/ai_chat_service.dart';
import '../../services/market_ai_context.dart';
import '../../state/auth_state.dart';
import '../auth/login_screen.dart';
import 'market_theme.dart';
import 'widgets/ai_mascot_button.dart';

Future<void> showMarketAiSheet(
  BuildContext context, {
  required MarketAiSnapshot snapshot,
  AiChatService? service,
  Future<bool> Function()? authChecker,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭喜AI盘面问答',
    barrierColor: Colors.black.withValues(alpha: 0.12),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (context, animation, secondaryAnimation) {
      final screen = MediaQuery.sizeOf(context);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Align(
            alignment: Alignment.topRight,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 620,
                maxHeight: screen.height - 38,
              ),
              child: MarketAiSheet(
                snapshot: snapshot,
                service: service,
                authChecker: authChecker,
              ),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.04, -0.03),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class MarketAiSheet extends StatefulWidget {
  const MarketAiSheet({
    super.key,
    required this.snapshot,
    this.service,
    this.authChecker,
  });

  final MarketAiSnapshot snapshot;
  final AiChatService? service;
  final Future<bool> Function()? authChecker;

  @override
  State<MarketAiSheet> createState() => _MarketAiSheetState();
}

class _MarketAiSheetState extends State<MarketAiSheet> {
  late final AiChatService _service = widget.service ?? AiChatService();
  final ScrollController _scroll = ScrollController();
  StreamSubscription<AiChatEvent>? _subscription;
  MarketAiQuestion? _question;
  String _answer = '';
  String? _sessionId;
  String? _notice;
  bool _loading = false;
  bool _localAnswer = false;
  bool _authAvailable = false;
  int _requestId = 0;

  @override
  void dispose() {
    _subscription?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  Future<bool> _checkAuth() async {
    final custom = widget.authChecker;
    if (custom != null) {
      try {
        return await custom();
      } catch (_) {
        return false;
      }
    }
    try {
      return await ApiClient.instance.ensureFreshAccessToken() != null;
    } catch (_) {
      return false;
    }
  }

  Future<void> _ask(MarketAiQuestion question) async {
    await _subscription?.cancel();
    final requestId = ++_requestId;
    setState(() {
      _question = question;
      _answer = '';
      _notice = null;
      _loading = true;
      _localAnswer = false;
    });

    _authAvailable = await _checkAuth();
    if (!mounted || requestId != _requestId) return;
    if (!_authAvailable) {
      _showLocalAnswer(
        question,
        notice: '当前未登录 AI 服务，先展示基于当前屏幕数据的盘面速读。',
      );
      return;
    }

    final system =
        MarketAiPromptBuilder.systemPrompt(widget.snapshot, question);
    final message =
        MarketAiPromptBuilder.userMessage(widget.snapshot, question);
    _subscription = _service
        .stream(
      serverSessionId: _sessionId,
      message: message,
      persona: 'default',
      topic: 'money',
      systemHint: system,
    )
        .listen(
      (event) {
        if (!mounted || requestId != _requestId) return;
        switch (event.kind) {
          case AiChatEventKind.session:
            _sessionId = event.sessionId ?? _sessionId;
            break;
          case AiChatEventKind.textDelta:
            final delta = event.delta ?? '';
            if (delta.isEmpty) return;
            setState(() => _answer += delta);
            _scrollToBottom();
            break;
          case AiChatEventKind.done:
            if ((event.finalText ?? '').isNotEmpty) {
              setState(() => _answer = event.finalText!);
            }
            setState(() => _loading = false);
            if (_answer.trim().isEmpty) {
              _showLocalAnswer(
                question,
                notice: 'AI 没有返回有效内容，已切换为盘面速读。',
              );
            }
            break;
          case AiChatEventKind.error:
            final authError = event.errorCode?.startsWith('AUTH') ?? false;
            _authAvailable = !authError;
            _showLocalAnswer(
              question,
              notice: authError
                  ? 'AI 服务需要登录，先展示基于当前屏幕数据的盘面速读。'
                  : 'AI 服务暂不可用，已切换为盘面速读：${event.errorMessage ?? '未知错误'}',
            );
            break;
          case AiChatEventKind.toolCall:
          case AiChatEventKind.toolResult:
          case AiChatEventKind.suggestions:
            break;
        }
      },
      onError: (Object error) {
        if (!mounted || requestId != _requestId) return;
        _showLocalAnswer(
          question,
          notice: '网络请求失败，已切换为盘面速读。',
        );
      },
      onDone: () {
        if (mounted && requestId == _requestId && _loading) {
          setState(() => _loading = false);
        }
      },
    );
  }

  void _showLocalAnswer(MarketAiQuestion question, {required String notice}) {
    if (!mounted) return;
    final answer = MarketAiPromptBuilder.localAnswer(widget.snapshot, question);
    setState(() {
      _question = question;
      _answer = answer;
      _notice = notice;
      _loading = false;
      _localAnswer = true;
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _openLogin() async {
    await Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ChangeNotifierProvider<AuthState>(
          create: (_) => AuthState()..bootstrap(),
          child: const LoginScreen(modal: true),
        ),
      ),
    );
    if (!mounted) return;
    _authAvailable = await _checkAuth();
    if (!mounted) return;
    setState(() {});
    final question = _question;
    if (_authAvailable && question != null) _ask(question);
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 3, sigmaY: 3),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.91),
            border: Border.all(
              color: MarketColors.border.withValues(alpha: 0.9),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _header(),
              const Divider(height: 1),
              _questions(),
              const Divider(height: 1),
              Flexible(child: _content()),
              _footer(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 10),
      child: Row(
        children: [
          const AiMascotAvatar(size: 38),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '问问喜AI',
                  style: TextStyle(
                    color: MarketColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${widget.snapshot.name} · '
                  '${widget.snapshot.code} · '
                  '${widget.snapshot.period.longLabel}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: MarketColors.textMuted,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '关闭',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(
              Icons.close,
              color: MarketColors.textSecondary,
              size: 19,
            ),
          ),
        ],
      ),
    );
  }

  Widget _questions() {
    final current = _question;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final twoColumns = constraints.maxWidth >= 330;
          final width = twoColumns
              ? (constraints.maxWidth - 8) / 2
              : constraints.maxWidth;
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final question in MarketAiQuestion.values)
                SizedBox(
                  width: width,
                  child: _questionButton(
                    question,
                    selected: current == question,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _questionButton(
    MarketAiQuestion question, {
    required bool selected,
  }) {
    return Material(
      color: selected ? MarketColors.accentSoft : MarketColors.panelRaised,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: _loading && selected ? null : () => _ask(question),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          constraints: const BoxConstraints(minHeight: 46),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(
              color: selected
                  ? MarketColors.accent.withValues(alpha: 0.42)
                  : MarketColors.border,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                _questionIcon(question),
                size: 16,
                color:
                    selected ? MarketColors.accent : MarketColors.textSecondary,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  question.label,
                  style: TextStyle(
                    color: selected
                        ? MarketColors.accent
                        : MarketColors.textPrimary,
                    fontSize: 11,
                    height: 1.35,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _questionIcon(MarketAiQuestion question) {
    switch (question) {
      case MarketAiQuestion.entry:
        return Icons.add_chart_outlined;
      case MarketAiQuestion.takeProfit:
        return Icons.trending_up_outlined;
      case MarketAiQuestion.stopLoss:
        return Icons.shield_outlined;
      case MarketAiQuestion.assess:
        return Icons.radar_outlined;
    }
  }

  Widget _content() {
    if (_question == null) {
      return _intro();
    }
    return SingleChildScrollView(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 7,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: MarketColors.accentSoft,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _localAnswer ? '盘面速读' : 'AI 分析',
                  style: const TextStyle(
                    color: MarketColors.accent,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _question!.label,
                  style: const TextStyle(
                    color: MarketColors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (_notice != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: MarketColors.warning.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: MarketColors.warning.withValues(alpha: 0.25),
                ),
              ),
              child: Text(
                _notice!,
                style: const TextStyle(
                  color: MarketColors.warning,
                  fontSize: 10,
                  height: 1.45,
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          if (_loading && _answer.isEmpty)
            const _AnswerLoading()
          else
            MarkdownBody(
              data: _answer,
              selectable: true,
              styleSheet: _markdownStyle,
            ),
        ],
      ),
    );
  }

  Widget _intro() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '我会读取当前屏幕上的 K 线、均线、成交量和支撑阻力区间，'
            '并结合${widget.snapshot.isReplay ? '回放位置之前的数据' : '最新一根 K 线'}作答。',
            style: const TextStyle(
              color: MarketColors.textSecondary,
              fontSize: 12,
              height: 1.65,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _infoChip(
                '现价 ${MarketAiPromptBuilder.formatPrice(widget.snapshot.candles.last.close)}',
              ),
              _infoChip(widget.snapshot.period.longLabel),
              if (widget.snapshot.isReplay)
                _infoChip(
                  '回放 ${widget.snapshot.activeIndex + 1}/${widget.snapshot.totalBars}',
                ),
              _infoChip(widget.snapshot.assetClass),
            ],
          ),
        ],
      ),
    );
  }

  Widget _infoChip(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: MarketColors.panelRaised,
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(
          text,
          style: const TextStyle(
            color: MarketColors.textSecondary,
            fontSize: 10,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      );

  Widget _footer() {
    final showLogin = !_authAvailable && _localAnswer && !_loading;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 10, 9),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: MarketColors.border)),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'AI 基于当前屏幕数据，仅供盘面参考，不构成投资建议。',
              style: TextStyle(
                color: MarketColors.textMuted,
                fontSize: 9,
                height: 1.4,
              ),
            ),
          ),
          if (showLogin)
            TextButton(
              onPressed: _openLogin,
              style: TextButton.styleFrom(
                foregroundColor: MarketColors.accent,
                minimumSize: const Size(0, 30),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                '登录使用 AI',
                style: TextStyle(fontSize: 10),
              ),
            ),
        ],
      ),
    );
  }

  MarkdownStyleSheet get _markdownStyle => MarkdownStyleSheet(
        p: const TextStyle(
          color: MarketColors.textSecondary,
          fontSize: 12,
          height: 1.68,
        ),
        strong: const TextStyle(
          color: MarketColors.textPrimary,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
        h2: const TextStyle(
          color: MarketColors.textPrimary,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
        h3: const TextStyle(
          color: MarketColors.textPrimary,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
        listBullet: const TextStyle(
          color: MarketColors.accent,
          fontSize: 12,
          height: 1.68,
        ),
        blockSpacing: 8,
      );
}

class _AnswerLoading extends StatelessWidget {
  const _AnswerLoading();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(height: 10),
          Text(
            '正在读取当前盘面…',
            style: TextStyle(
              color: MarketColors.textMuted,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}
