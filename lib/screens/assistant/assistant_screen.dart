import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format/credit_fmt.dart';
import '../../models/chat.dart';
import '../../models/persona.dart';
import '../../models/strategy.dart';
import '../../state/chat_state.dart';
import '../../state/portfolio_state.dart';
import '../../theme/app_theme.dart';
import '../ding/widgets/ding_task_editor.dart';
import '../settings/settings_screen.dart';
import 'widgets/message_bubble.dart';
import 'widgets/persona_picker.dart';
import 'widgets/session_drawer.dart';
import 'widgets/strategy_picker.dart';

/// AssistantScreen 的入参。
///
/// 跨 Tab 跳转（组合 → 助理）时，可通过 `Navigator.push(MaterialPageRoute(
///   settings: const RouteSettings(arguments: AssistantLaunch(...)), ...))`
/// 携带初始 prompt + 是否自动附带组合，省一次手动点击。
class AssistantLaunch {
  const AssistantLaunch({
    this.initialMessage,
    this.attachPortfolio = false,
    this.autoSend = false,
  });

  final String? initialMessage;
  final bool attachPortfolio;
  final bool autoSend;
}

class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key, this.launch});

  /// 构造时显式传入的启动参数；优先级高于 ModalRoute.arguments。
  final AssistantLaunch? launch;

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final FocusNode _focus = FocusNode();
  // 推理过程默认始终展示；不再提供顶部隐藏开关。
  static const bool _showReasoning = true;

  /// 「@组合」开关：开启后下次 _send 会把 PortfolioState.currentSummary
  /// 序列化进 SSE body 的 portfolio_context 字段。
  bool _attachPortfolio = false;
  bool _launchHandled = false;

  /// 已经为哪个会话做过「进入即定位到最新消息」的初始滚动。
  /// 切换会话 / 首次进入聊天区时,自动跳到底部展示最新消息(而不是停在最老)。
  String? _scrolledSessionId;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_launchHandled) return;
    _launchHandled = true;
    final launch = widget.launch ??
        (ModalRoute.of(context)?.settings.arguments as AssistantLaunch?);
    if (launch == null) return;
    if (launch.attachPortfolio) _attachPortfolio = true;
    if (launch.initialMessage != null && launch.initialMessage!.isNotEmpty) {
      if (launch.autoSend) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _send(launch.initialMessage);
        });
      } else {
        _input.text = launch.initialMessage!;
        _input.selection = TextSelection.fromPosition(
          TextPosition(offset: _input.text.length),
        );
      }
    }
  }

  /// 滚动到底部。
  /// - [animate]=false：用 jumpTo（流式期间使用，避免每帧都启动新的 animateTo
  ///   打断旧动画造成抖动闪烁）。
  /// - [animate]=true：用 animateTo（首次发送 / 接收完毕调用一次）。
  void _scrollToBottom({bool animate = true}) {
    if (!_scroll.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final target = _scroll.position.maxScrollExtent;
      if (animate) {
        _scroll.animateTo(
          target,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      } else {
        _scroll.jumpTo(target);
      }
    });
  }

  Future<void> _send([String? override]) async {
    final raw = override ?? _input.text;
    final text = raw.trim();
    if (text.isEmpty) return;
    _input.clear();
    // 发送即收起键盘 + 失焦，让聊天区视野最大化
    _focus.unfocus();
    Map<String, dynamic>? ctxJson;
    if (_attachPortfolio) {
      final ps = context.read<PortfolioState>();
      final summary = ps.currentSummary;
      if (summary != null && summary.holdings.isNotEmpty) {
        ctxJson = summary.toAiContext();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('当前组合没有持仓，已忽略组合附带')),
        );
      }
    }
    await context
        .read<ChatState>()
        .sendMessage(text, portfolioContext: ctxJson);
    _scrollToBottom();
  }

  /// 「喜点不足 / 扣费失败」弹窗：提示余额，并可一键跳到充值页。
  void _showChargeDialog(ChargeIssue issue) {
    // 后端 message 里塞了原始整数（如「当前余额 8」），直接展示会跟前端
    // ÷10 的显示口径不一致；这里只用 issue.balance 重新组装文案。
    final balanceLabel =
        issue.balance != null ? CreditFmt.balance(issue.balance!) : null;
    final content = balanceLabel != null
        ? '当前余额 $balanceLabel 喜点，已经不够本次对话啦。先去充点喜点再聊？'
        : '喜点不够本次对话啦，先去充点喜点再聊？';
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('喜点不够啦'),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('再想想'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const SettingsScreen(),
              ));
            },
            child: const Text('去充值'),
          ),
        ],
      ),
    );
  }

  /// 把当前对话最近一条用户提问 / 输入框正在输入的内容作为预填，弹出
  /// DING 任务编辑器供用户设置定时执行。
  void _addToDing(BuildContext context, ChatState chat) {
    final fromInput = _input.text.trim();
    String? promptInit;
    String? titleInit;
    if (fromInput.isNotEmpty) {
      promptInit = fromInput;
    } else {
      // 取当前会话最近的一条 user 消息
      for (final m in chat.messages.reversed) {
        if (m.role == 'user' && m.content.trim().isNotEmpty) {
          promptInit = m.content.trim();
          break;
        }
      }
    }
    if (promptInit != null && promptInit.isNotEmpty) {
      titleInit = promptInit.length > 14
          ? '${promptInit.substring(0, 14)}…'
          : promptInit;
    }
    DingTaskEditor.show(
      context,
      initialPrompt: promptInit,
      initialTitle: titleInit,
      initialPersonaId: chat.currentPersona.id,
    );
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatState>();
    final session = chat.active;
    final persona = chat.currentPersona;

    if (chat.streaming) _scrollToBottom(animate: false);

    // 进入聊天区 / 切换会话:首帧后定位到最新消息(底部),而非停在最老。
    if (session != null &&
        session.messages.isNotEmpty &&
        session.id != _scrolledSessionId) {
      _scrolledSessionId = session.id;
      _scrollToBottom(animate: false);
    }

    final issue = chat.chargeIssue;
    if (issue != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final c = context.read<ChatState>();
        if (c.chargeIssue == null) return;
        c.consumeChargeIssue();
        _showChargeDialog(issue);
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('AI 助理'),
            const SizedBox(width: 8),
            if (chat.totalTokens > 0)
              Text(
                '${chat.totalTokens} tok',
                style: TextStyle(
                    fontSize: 10, color: AppColors.textTertiary),
              ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '新建对话',
            icon: const Icon(Icons.add_comment_outlined, size: 18),
            onPressed: () => chat.newSession(),
          ),
          IconButton(
            tooltip: '加入 DING（定时执行）',
            icon: const Icon(Icons.add_alarm, size: 18),
            onPressed: () => _addToDing(context, chat),
          ),
        ],
      ),
      drawer: const SessionDrawer(),
      body: Column(
        children: [
          _topTagBar(chat, persona, session),
          Container(height: 1, color: AppColors.borderDim),
          Expanded(
            child: session == null || session.messages.isEmpty
                ? _welcomePanel(persona)
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 14),
                    itemCount: session.messages.length,
                    itemBuilder: (context, i) {
                      final msg = session.messages[i];
                      return MessageBubble(
                        message: msg,
                        allMessages: session.messages,
                        showReasoning: _showReasoning,
                      );
                    },
                  ),
          ),
          _composer(chat),
        ],
      ),
    );
  }

  /// 顶部「角色 + 策略之王」并列下拉 tag。
  ///
  /// - 角色 tag：合并原横向 chip 列表，显示当前选中 persona，点击展开角色清单。
  /// - 策略之王 tag：呈现策略气泡列表，默认挂载「ETF 组合轮动」，点「立即运行」
  ///   即把策略 prompt 直接发给当前会话的 AI 助理。
  Widget _topTagBar(ChatState chat, Persona persona, ChatSession? session) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          PersonaPicker(
            activeId: persona.id,
            disabled: chat.streaming,
            onPick: (id) async {
              final isNewSessionEmpty =
                  (session?.messages.isEmpty ?? true);
              if (isNewSessionEmpty) {
                await chat.setPersona(id);
              } else {
                // 已有对话不切 persona，直接开新会话避免 prompt 跳变
                await chat.newSession(personaId: id);
              }
            },
          ),
          const SizedBox(width: 8),
          StrategyPicker(
            disabled: chat.streaming,
            onRun: (s) => _runStrategy(s),
          ),
        ],
      ),
    );
  }

  /// 「策略之王」气泡里点「立即运行」 → 直接发送策略 prompt 给 AI。
  ///
  /// 若用户已开启「@组合」，则把组合快照也带上，让 AI 在策略报告里参考
  /// 当前持仓做换仓建议。
  Future<void> _runStrategy(Strategy s) async {
    Map<String, dynamic>? ctxJson;
    if (_attachPortfolio) {
      final ps = context.read<PortfolioState>();
      final summary = ps.currentSummary;
      if (summary != null && summary.holdings.isNotEmpty) {
        ctxJson = summary.toAiContext();
      }
    }
    await context
        .read<ChatState>()
        .sendMessage(s.prompt, portfolioContext: ctxJson);
    _scrollToBottom();
  }

  /// 空会话时的欢迎面板：参考"元宝"截图布局——上半部分留白让视线聚焦，
  /// 下半部分依次为大标题、福利中心广告条、3 条快速提问 pill。
  Widget _welcomePanel(Persona persona) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Spacer(),
          Text(
            '嗨，今天想聊点什么？',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 14),
          _CreditAdBanner(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
          const SizedBox(height: 14),
          for (final q in persona.welcomeSuggestions.take(3)) _suggestion(q),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  /// 椭圆 pill 样式的快速提问（替代原 raised 背景的方框样式），
  /// 视觉风格更靠近"元宝"截图，但配色仍走金黄主调。
  Widget _suggestion(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Material(
          color: AppColors.bgRaised,
          shape: StadiumBorder(
            side: BorderSide(color: AppColors.borderDim),
          ),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: () => _send(text),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      text,
                      style: TextStyle(
                          color: AppColors.textPrimary, fontSize: 13),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.north_east,
                      color: AppColors.amber, size: 14),
                ],
              ),
            ),
          ),
        ),
      );

  /// 输入框做成圆角胶囊形，主按钮内嵌右侧——参考截图样式，
  /// 但保持深色暗调 + 金黄主色，不照搬截图浅色配色。
  Widget _composer(ChatState chat) {
    return Container(
      color: AppColors.bgSurface,
      padding: EdgeInsets.fromLTRB(
          14, 6, 14, 10 + MediaQuery.of(context).padding.bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _portfolioChip(),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.bgRaised,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: AppColors.borderDim),
                  ),
                  padding: const EdgeInsets.fromLTRB(18, 4, 6, 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _input,
                          focusNode: _focus,
                          minLines: 1,
                          maxLines: 6,
                          style: const TextStyle(fontSize: 13),
                          decoration: const InputDecoration(
                            hintText: '想问点什么？股票、ETF、期货都可以…',
                            isDense: true,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(
                                vertical: 12, horizontal: 0),
                          ),
                          onSubmitted: (_) => _send(),
                        ),
                      ),
                      const SizedBox(width: 4),
                      _sendButton(chat),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 「@组合」chip：默认关；开启后下次 _send 会把当前组合 summary 上送。
  ///
  /// 设计取舍：用 chip 而非 menu / dialog，单次请求级别开关；不持久化（用户
  /// 切到其它页再回来默认关闭），避免误用上传持仓。
  Widget _portfolioChip() {
    return Consumer<PortfolioState>(
      builder: (context, ps, _) {
        final summary = ps.currentSummary;
        final hasHoldings = summary != null && summary.holdings.isNotEmpty;
        final label = !hasHoldings
            ? '@组合（暂无持仓）'
            : _attachPortfolio
                ? '已附带：${summary.portfolio.name}（${summary.holdings.length} 只）'
                : '@组合（${summary.portfolio.name}）';
        const activeColor = AppColors.amber;
        final inactiveBg = AppColors.bgRaised;
        return Align(
          alignment: Alignment.centerLeft,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: !hasHoldings
                  ? null
                  : () => setState(() => _attachPortfolio = !_attachPortfolio),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _attachPortfolio
                      ? activeColor.withValues(alpha: 0.18)
                      : inactiveBg,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _attachPortfolio
                        ? activeColor
                        : AppColors.borderDim,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _attachPortfolio
                          ? Icons.account_balance_wallet
                          : Icons.account_balance_wallet_outlined,
                      size: 14,
                      color: _attachPortfolio
                          ? activeColor
                          : AppColors.textTertiary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _attachPortfolio
                            ? activeColor
                            : AppColors.textSecondary,
                      ),
                    ),
                    if (_attachPortfolio) ...[
                      const SizedBox(width: 6),
                      const Icon(Icons.close, size: 12, color: activeColor),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _sendButton(ChatState chat) {
    if (chat.streaming) {
      return Padding(
        padding: const EdgeInsets.all(2),
        child: Material(
          color: AppColors.bgSurface,
          shape: const CircleBorder(
            side: BorderSide(color: AppColors.amber, width: 1.2),
          ),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => chat.abort(),
            child: const SizedBox(
              width: 36,
              height: 36,
              child: Icon(Icons.stop, color: AppColors.amber, size: 18),
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(2),
      child: Material(
        color: AppColors.amber,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: _send,
          child: const SizedBox(
            width: 36,
            height: 36,
            child: Icon(Icons.arrow_upward, color: Colors.white, size: 18),
          ),
        ),
      ),
    );
  }
}

/// 福利中心广告条 — 引导用户进入"我的"页面充值喜点。
/// 视觉参考"元宝"截图的紫色福利条；这里改用金黄渐变与现有主题统一。
class _CreditAdBanner extends StatelessWidget {
  const _CreditAdBanner({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppColors.amber.withValues(alpha: 0.20),
                AppColors.amber.withValues(alpha: 0.06),
              ],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.amber.withValues(alpha: 0.55)),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.amber,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.stars_rounded,
                    color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '喜宽福利中心',
                      style: TextStyle(
                        color: AppColors.amber,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '充值喜点，畅享深度分析与更多 AI 能力',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.amber,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.shopping_bag_outlined,
                        color: Colors.white, size: 13),
                    SizedBox(width: 4),
                    Text(
                      '福利中心',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
