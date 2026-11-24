import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart' show ImageSource;
import 'package:provider/provider.dart';

import '../../core/auth/require_login.dart';
import '../../core/format/credit_fmt.dart';
import '../../core/utils/image_data_url.dart';
import '../../models/chat.dart';
import '../../models/persona.dart';
import '../../services/analytics.dart';
import '../../services/image_attach_service.dart';
import '../../services/market_briefing.dart';
import '../../state/auth_state.dart';
import '../../state/chat_state.dart';
import '../../state/portfolio_state.dart';
import '../../theme/app_theme.dart';
import '../../wx/wx_kit.dart';
import '../settings/account_kit.dart';
import 'widgets/message_bubble.dart';
import 'widgets/persona_picker.dart';

/// 聊天页。采用豆包式白底问答：用户消息靠右，AI 回答通栏浅灰卡片，
/// 底部悬浮输入区。
///
/// 这一页就是「和投资助理对话」：会话主题固定为 money，人选是研究助理 /
/// 巴菲特 / 格雷厄姆那一套（见 [Personas]）。旧版本的「虚拟人伴侣」已经下线，
/// 历史里遗留的 companion 会话不会再被选中（见 [ChatState.ensureInvestmentSession]）。
///
/// 逻辑（发送、流式、图片、余额不足、重新生成、推荐追问）与重构前一致，
/// 这次只换了外观与入口。
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
  const AssistantScreen({super.key, this.launch, this.briefing});

  /// 构造时显式传入的启动参数；优先级高于 ModalRoute.arguments。
  final AssistantLaunch? launch;

  /// 快捷提问的数据源；测试 / 截图时注入假实现，默认走网络。
  final MarketBriefingService? briefing;

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final FocusNode _focus = FocusNode();

  /// 空会话的入场动画（问候语与提问依次淡入上浮）。
  late final AnimationController _entranceCtl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  String? _entranceSessionId;
  static const bool _showReasoning = true;

  /// 是否把持仓快照带进请求（仅由跨页跳转 [AssistantLaunch.attachPortfolio]
  /// 打开；输入栏不再提供手动开关）。
  bool _attachPortfolio = false;
  bool _launchHandled = false;

  late final MarketBriefingService _briefing =
      widget.briefing ?? MarketBriefingService();
  List<String>? _marketSuggestions;
  bool _loadingSuggestions = false;
  DateTime? _suggestionsLoadedAt;

  /// 待发送的图片（data URL）。
  final ImageAttachService _imageAttach = ImageAttachService();
  final List<String> _pendingImages = [];
  final Map<String, Uint8List> _pendingImageBytes = {};
  bool _pickingImage = false;

  /// 已经为哪个会话做过「进入即定位到最新消息」的初始滚动。
  String? _scrolledSessionId;


  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    // 输入框有字没字，决定右边是「发送」还是灰着 —— 需要跟着重建。
    _input.addListener(_onInputChanged);
    // ignore: unawaited_futures
    _loadMarketSuggestions();
  }

  void _onInputChanged() {
    if (mounted) setState(() {});
  }

  void _onScroll() {}

  @override
  void dispose() {
    _input.removeListener(_onInputChanged);
    _input.dispose();
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _focus.dispose();
    _entranceCtl.dispose();
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

  /// 滚动到底部。[animate]=false 时用 jumpTo（流式期间用）。
  void _scrollToBottom({bool animate = true}) {
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

  /// 进入 / 切换会话时定位到最新：markdown / 图片会在首帧后继续撑开高度，
  /// 单次 jump 往往偏短，这里首帧 + 延迟各跳一次。
  void _scrollToBottomInitial() {
    void jump() {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      jump();
      Future.delayed(const Duration(milliseconds: 180), jump);
      Future.delayed(const Duration(milliseconds: 420), jump);
    });
  }

  Future<void> _send([String? override]) async {
    final raw = override ?? _input.text;
    final text = raw.trim();
    final images = List<String>.from(_pendingImages);
    if (text.isEmpty && images.isEmpty) return;
    // 流式输出中不接受新消息：发送按钮此时是「停止」，但键盘回车仍会走到这里。
    if (context.read<ChatState>().streaming) return;
    // 发送是需鉴权功能：未登录先弹登录，放弃则不发送（保留输入内容）。
    if (!await requireLogin(context)) return;
    if (!mounted) return;
    _input.clear();
    if (images.isNotEmpty) {
      setState(() {
        _pendingImages.clear();
        _pendingImageBytes.clear();
      });
    }
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
    final chat = context.read<ChatState>();
    try {
      await chat.sendMessage(text,
          portfolioContext: ctxJson, imageDataUrls: images);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('消息发送失败，请稍后重试。')),
        );
      return;
    }
    Analytics.instance.track(Analytics.evChatSend, {
      'chars': text.length,
      'images': images.length,
      'with_portfolio': ctxJson != null,
    });
    _scrollToBottom();
  }

  Future<void> _sendSuggestion(String q) => _send(q);

  Future<void> _regenerate(ChatState chat, ChatMessage msg) async {
    if (chat.streaming) return;
    if (!await requireLogin(context)) return;
    if (!mounted) return;
    await chat.regenerate(msg);
    _scrollToBottom();
  }

  /// 选图：底部弹出「拍照 / 从相册选择」。
  Future<void> _pickImage() async {
    if (_pickingImage) return;
    final remaining = ImageAttachService.maxImages - _pendingImages.length;
    if (remaining <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('最多附带 ${ImageAttachService.maxImages} 张图片'),
        ),
      );
      return;
    }
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _ImageSourceSheet(
        remaining: remaining,
        total: ImageAttachService.maxImages,
      ),
    );
    if (source == null || !mounted) return;

    setState(() => _pickingImage = true);
    List<String> picked = const [];
    try {
      picked = source == ImageSource.camera
          ? await _imageAttach.pickFromCamera()
          : await _imageAttach.pickFromGallery();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('选择图片失败：$e')),
        );
      }
    }
    if (!mounted) return;
    setState(() {
      for (final url in picked.take(remaining)) {
        _pendingImages.add(url);
        _pendingImageBytes[url] = decodeImageDataUrl(url);
      }
      _pickingImage = false;
    });
  }

  /// 「喜点不足 / 扣费失败」弹窗。
  void _showChargeDialog(ChargeIssue issue) {
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
              if (rechargeAvailable) {
                // ignore: unawaited_futures
                showRechargeSheet(context);
              } else {
                showLedgerSheet(context);
              }
            },
            child: Text(rechargeAvailable ? '去充值' : '看明细'),
          ),
        ],
      ),
    );
  }

  /// 标题右边的「…」：当前助手 + 历史对话 + 新建 / 删除。
  Future<void> _openChatMenu(ChatState chat, Persona persona) async {
    final topic = chat.active?.topic ?? 'money';
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ChatMenuSheet(
        persona: persona,
        sessions: chat.sessions
            .where((s) => s.topic != ChatState.companionTopic)
            .toList(growable: false),
        activeId: chat.activeId,
      ),
    );
    if (!mounted || action == null) return;
    if (action.startsWith('switch:')) {
      chat.selectSession(action.substring('switch:'.length));
      _scrollToBottomInitial();
      return;
    }
    switch (action) {
      case 'persona':
        final picked =
            await showPersonaSheet(context, activeId: persona.id, topic: topic);
        if (picked == null || !mounted) return;
        final empty = chat.active?.messages.isEmpty ?? true;
        if (empty) {
          await chat.setPersona(picked);
        } else {
          await chat.newSession(personaId: picked);
        }
        break;
      case 'new':
        await chat.newSession();
        if (mounted) _scrollToBottomInitial();
        break;
      case 'delete':
        final id = chat.activeId;
        if (id == null) return;
        await chat.deleteSession(id);
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatState>();
    final session = chat.active;
    final persona = chat.currentPersona;
    final titleName = persona.displayName;
    final selfName = context.watch<AuthState>().currentUser?.nickname ?? '';

    if (chat.streaming) _scrollToBottom(animate: false);

    if (session != null &&
        session.messages.isNotEmpty &&
        session.id != _scrolledSessionId) {
      _scrolledSessionId = session.id;
      _scrollToBottomInitial();
    }

    final latest = chat.latestAssistant;

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

    // 空会话出现时重放入场动画（冷启动一次，之后每次「新建对话」再来一次）。
    final isEmptySession = session == null || session.messages.isEmpty;
    final entranceKey = isEmptySession ? (session?.id ?? 'new') : null;
    if (entranceKey != null && entranceKey != _entranceSessionId) {
      _entranceSessionId = entranceKey;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _entranceCtl.forward(from: 0);
      });
    }

    return Scaffold(
      key: const ValueKey('chat-white-surface'),
      backgroundColor: AppColors.bgSurface,
      appBar: AppBar(
        centerTitle: true,
        toolbarHeight: 64,
        backgroundColor: AppColors.bgSurface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              titleName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.title.copyWith(
                color: AppColors.textPrimary,
                fontSize: 17,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              'AI 生成可能有误，注意核实',
              style: AppType.micro.copyWith(
                color: AppColors.textTertiary,
                fontSize: 10,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            key: const ValueKey('chat-menu'),
            tooltip: '更多',
            icon: const Icon(Icons.more_horiz_rounded, size: 24),
            onPressed: () => _openChatMenu(chat, persona),
          ),
        ],
      ),
      body: ColoredBox(
        color: AppColors.bgSurface,
        child: Column(
          children: [
            Expanded(
              child: isEmptySession
                  ? _welcomePanel(persona)
                  : GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: () => FocusScope.of(context).unfocus(),
                      child: ListView.builder(
                        controller: _scroll,
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.fromLTRB(
                            AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.lg),
                        itemCount: session.messages.length,
                        itemBuilder: (context, i) {
                          final msg = session.messages[i];
                          final prev = i == 0 ? null : session.messages[i - 1];
                          final gap = prev == null
                              ? null
                              : msg.timestamp.difference(prev.timestamp);
                          final showTime = gap == null ||
                              gap.inMinutes.abs() >= 5 ||
                              gap.isNegative;
                          final isLatest = identical(msg, latest);
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (showTime)
                                WxTimeStamp(wxChatTime(msg.timestamp)),
                              MessageBubble(
                                message: msg,
                                allMessages: session.messages,
                                showReasoning: _showReasoning,
                                isLatest: isLatest,
                                selfName: selfName,
                                assistantName: titleName,
                                onSuggestion: isLatest ? _sendSuggestion : null,
                                onRegenerate: isLatest
                                    ? () => _regenerate(chat, msg)
                                    : null,
                                onFeedback: (r) => chat.setFeedback(msg, r),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
            ),
            _composer(chat),
          ],
        ),
      ),
    );
  }


  /// 空会话时的问候：豆包式标题、说明与建议问题，不抢对话主体视觉。
  Widget _welcomePanel(Persona persona) {
    final loadedAt = _suggestionsLoadedAt;
    if (loadedAt == null ||
        DateTime.now().difference(loadedAt) > const Duration(minutes: 5)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadMarketSuggestions();
      });
    }
    final market = _marketSuggestions;
    final suggestions = (market != null && market.isNotEmpty)
        ? market
        : persona.welcomeSuggestions;

    final nickname = context.watch<AuthState>().currentUser?.nickname ?? '';
    final who = nickname.trim().isEmpty ? '朋友' : nickname.trim();

    var slot = 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.md),
      child: SizedBox(
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Spacer(),
            _entrance(
              slot++,
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Hi，$who',
                    style: AppType.title.copyWith(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '今天想从哪个问题开始？',
                    style: AppType.body.copyWith(
                      fontSize: 15,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.lg),
            for (final q in suggestions.take(3))
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.sm),
                child: _entrance(slot++, _suggestion(q), from: 10),
              ),
            const SizedBox(height: AppSpace.xs),
          ],
        ),
      ),
    );
  }

  /// 拉取「当前时段 + 开/收盘行情」摘要并生成快捷提问；失败保持原建议。
  /// 只有「喜爱钱」这个圈有行情摘要，其它圈直接用助手自带的欢迎提问。
  Future<void> _loadMarketSuggestions() async {
    if (_loadingSuggestions) return;
    _loadingSuggestions = true;
    try {
      final topic = context.read<ChatState>().active?.topic ?? 'money';
      if (topic != 'money') {
        if (mounted) setState(() => _suggestionsLoadedAt = DateTime.now());
        return;
      }
      final list = await _briefing.loadSuggestions();
      if (!mounted) return;
      setState(() {
        _marketSuggestions = list.isEmpty ? null : list;
        _suggestionsLoadedAt = DateTime.now();
      });
    } catch (_) {
      if (mounted) setState(() => _suggestionsLoadedAt = DateTime.now());
    } finally {
      _loadingSuggestions = false;
    }
  }

  /// 快捷提问：豆包式浅灰建议卡片，轻量、可直接点开。
  Widget _suggestion(String text) => Material(
        color: const Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _send(text),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(text, style: AppType.body.copyWith(fontSize: 15)),
                ),
                Icon(Icons.arrow_forward_rounded,
                    size: 17, color: AppColors.textTertiary),
              ],
            ),
          ),
        ),
      );

  /// 入场动画：每个元素按 [slot] 依次淡入并上浮 [from] 像素。
  Widget _entrance(int slot, Widget child, {double from = 14}) {
    final start = (slot * 0.12).clamp(0.0, 0.6);
    final curve = CurvedAnimation(
      parent: _entranceCtl,
      curve: Interval(start, (start + 0.4).clamp(0.0, 1.0),
          curve: Curves.easeOutCubic),
    );
    return AnimatedBuilder(
      animation: curve,
      builder: (_, sub) => Opacity(
        opacity: curve.value,
        child: Transform.translate(
          offset: Offset(0, from * (1 - curve.value)),
          child: sub,
        ),
      ),
      child: child,
    );
  }

  /// 输入栏：豆包式白底悬浮输入框。左边一个圆形「加图」按钮，右边圆形发送。
  Widget _composer(ChatState chat) {
    final typed = _input.text.trim().isNotEmpty || _pendingImages.isNotEmpty;
    return Container(
      color: AppColors.bgSurface,
      padding: EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md,
          AppSpace.sm + MediaQuery.of(context).padding.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_pendingImages.isNotEmpty) _pendingImageStrip(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _attachButton(),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(minHeight: 48),
                  decoration: BoxDecoration(
                    color: AppColors.bgSurface,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: const Color(0xFFE8E8E8)),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x0D000000),
                        blurRadius: 14,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: TextField(
                    controller: _input,
                    focusNode: _focus,
                    minLines: 1,
                    maxLines: 5,
                    style: AppType.body.copyWith(fontSize: 16),
                    decoration: InputDecoration(
                      hintText: '发消息或提问…',
                      isDense: true,
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                      hintStyle: AppType.body.copyWith(
                          fontSize: 16, color: AppColors.textTertiary),
                    ),
                    onTapOutside: (_) => _focus.unfocus(),
                    onSubmitted: (_) => _send(),
                  ),
                ),
              ),
              const SizedBox(width: AppSpace.sm),
              _sendButton(chat, typed),
            ],
          ),
        ],
      ),
    );
  }

  /// 待发送图片的缩略图条（带右上角删除）。
  Widget _pendingImageStrip() {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm, left: AppSpace.xs),
      child: SizedBox(
        height: 64,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _pendingImages.length,
          separatorBuilder: (_, __) => const SizedBox(width: AppSpace.sm),
          itemBuilder: (context, i) {
            final url = _pendingImages[i];
            final bytes = _pendingImageBytes[url];
            return Stack(
              clipBehavior: Clip.none,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: bytes == null || bytes.isEmpty
                      ? Container(
                          width: 64,
                          height: 64,
                          color: AppColors.bgRaised,
                          child: Icon(Icons.broken_image_outlined,
                              size: 18, color: AppColors.textTertiary),
                        )
                      : Image.memory(bytes,
                          width: 64,
                          height: 64,
                          fit: BoxFit.cover,
                          gaplessPlayback: true),
                ),
                Positioned(
                  right: -6,
                  top: -6,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => setState(() {
                      _pendingImages.removeAt(i);
                      _pendingImageBytes.remove(url);
                    }),
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: AppColors.bgSurface,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.close,
                          size: 12, color: AppColors.textSecondary),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// 输入栏左侧：加图入口。做成和发送按钮同尺寸的圆形幽灵按钮，
  /// 和输入框、发送键在一条水平线上对齐。
  Widget _attachButton() {
    final full = _pendingImages.length >= ImageAttachService.maxImages;
    final disabled = full || _pickingImage;
    return SizedBox(
      width: 46,
      height: 46,
      child: Material(
        color: full ? const Color(0xFFF1F1F1) : AppColors.bgRaised,
        shape: const CircleBorder(),
        child: InkWell(
          key: const ValueKey('chat-attach'),
          customBorder: const CircleBorder(),
          onTap: disabled ? null : _pickImage,
          child: Icon(
            Icons.add_photo_alternate_outlined,
            size: 22,
            color: disabled ? AppColors.textTertiary : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }


  /// 右边：有字时是可发送的圆形按钮，流式中切换为停止。
  Widget _sendButton(ChatState chat, bool typed) {
    if (chat.streaming) {
      return SizedBox(
        width: 46,
        height: 46,
        child: IconButton.filled(
          tooltip: '停止生成',
          onPressed: () => chat.abort(),
          style: IconButton.styleFrom(
            backgroundColor: AppColors.textPrimary,
            foregroundColor: AppColors.bgSurface,
          ),
          icon: const Icon(Icons.stop_rounded, size: 21),
        ),
      );
    }
    return SizedBox(
      width: 46,
      height: 46,
      child: IconButton.filled(
        key: const ValueKey('chat-send'),
        tooltip: '发送',
        onPressed: typed ? _send : null,
        style: IconButton.styleFrom(
          backgroundColor: AppColors.amber,
          foregroundColor: AppColors.onAccent,
          disabledBackgroundColor: const Color(0xFFF1F1F1),
          disabledForegroundColor: AppColors.textTertiary,
        ),
        icon: const Icon(Icons.arrow_upward_rounded, size: 22),
      ),
    );
  }
}

/// 「添加图片」弹层：标题 + 剩余张数 + 两个入口。
class _ImageSourceSheet extends StatelessWidget {
  const _ImageSourceSheet({required this.remaining, required this.total});

  final int remaining;
  final int total;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.bgSurface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
        ),
        padding: const EdgeInsets.fromLTRB(
          AppSpace.lg,
          AppSpace.sm,
          AppSpace.lg,
          AppSpace.sm,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.borderMed,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: AppSpace.md),
            Row(
              children: [
                Text('添加图片',
                    style: AppType.title.copyWith(fontSize: 17)),
                const Spacer(),
                Text(
                  '还能选 $remaining 张',
                  style: AppType.micro.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.md),
            _SourceTile(
              icon: Icons.photo_camera_outlined,
              title: '拍照',
              subtitle: '用相机拍一张成交记录',
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            const SizedBox(height: AppSpace.sm),
            _SourceTile(
              icon: Icons.photo_library_outlined,
              title: '从相册选择',
              subtitle: '可多选，单次最多 $total 张',
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            const SizedBox(height: AppSpace.xs),
            TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
              ),
              child: const Text('取消'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.bgRaised,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.md,
            vertical: AppSpace.sm + 2,
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.bgSurface,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 20, color: AppColors.amber),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: AppType.body.copyWith(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        )),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: AppType.micro.copyWith(
                          color: AppColors.textSecondary,
                        )),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  size: 20, color: AppColors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

/// 「…」弹层：当前助手、历史对话与新建 / 删除。
class _ChatMenuSheet extends StatelessWidget {
  const _ChatMenuSheet({
    required this.persona,
    required this.sessions,
    required this.activeId,
  });

  final Persona persona;
  final List<ChatSession> sessions;
  final String? activeId;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.bgSurface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
        ),
        padding: const EdgeInsets.fromLTRB(
          AppSpace.lg,
          AppSpace.sm,
          AppSpace.lg,
          AppSpace.md,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.borderMed,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: AppSpace.md),
            _assistantRow(context),
            if (sessions.isNotEmpty) ...[
              const SizedBox(height: AppSpace.md),
              Row(
                children: [
                  Text(
                    '历史对话',
                    style: AppType.caption.copyWith(
                      fontSize: 12.5,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${sessions.length} 段',
                    style: AppType.micro.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 236),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: sessions.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 2),
                  itemBuilder: (context, i) =>
                      _historyRow(context, sessions[i]),
                ),
              ),
            ],
            const SizedBox(height: AppSpace.sm),
            Divider(
                height: 0.5, thickness: 0.5, color: AppColors.borderDim),
            const SizedBox(height: AppSpace.xs),
            _actionRow(
              context,
              icon: Icons.add_comment_outlined,
              title: '发起新的对话',
              subtitle: '从一段空白开始问',
              value: 'new',
            ),
            _actionRow(
              context,
              icon: Icons.delete_outline_rounded,
              title: '删除这个对话',
              subtitle: '只删本机这一段，报告不受影响',
              value: 'delete',
              danger: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _assistantRow(BuildContext context) {
    return Material(
      color: AppColors.bgRaised,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: () => Navigator.pop(context, 'persona'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.md,
            AppSpace.sm,
            AppSpace.md,
            AppSpace.sm,
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: persona.color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(persona.icon, size: 19, color: persona.color),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      persona.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.body.copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '当前助手 · 点这里换一个',
                      style: AppType.micro.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.swap_horiz_rounded,
                  size: 18, color: AppColors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _historyRow(BuildContext context, ChatSession session) {
    final current = session.id == activeId;
    return Material(
      color: current
          ? AppColors.amber.withValues(alpha: 0.08)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: () => Navigator.pop(context, 'switch:${session.id}'),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.sm + 2,
            vertical: AppSpace.sm,
          ),
          child: Row(
            children: [
              Icon(
                current
                    ? Icons.chat_bubble_rounded
                    : Icons.chat_bubble_outline_rounded,
                size: 16,
                color: current ? AppColors.amber : AppColors.textTertiary,
              ),
              const SizedBox(width: AppSpace.sm + 2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.body.copyWith(
                        fontSize: 14.5,
                        fontWeight:
                            current ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${session.messages.length} 条 · '
                      '${_sessionTime(session.updatedAt)}',
                      style: AppType.micro.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              if (current)
                Text(
                  '当前',
                  style: AppType.micro.copyWith(
                    color: AppColors.amberDim,
                    fontWeight: FontWeight.w600,
                  ),
                )
              else
                Icon(Icons.chevron_right_rounded,
                    size: 18, color: AppColors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionRow(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required String value,
    bool danger = false,
  }) {
    final tone = danger ? AppColors.danger : AppColors.textPrimary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: () => Navigator.pop(context, value),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.sm,
            vertical: AppSpace.sm,
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: danger
                      ? AppColors.danger.withValues(alpha: 0.08)
                      : AppColors.bgRaised,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 18, color: tone),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppType.body.copyWith(
                        fontSize: 15,
                        color: tone,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: AppType.micro.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  size: 18, color: AppColors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

String _sessionTime(DateTime time) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(time.year, time.month, time.day);
  final diff = today.difference(day).inDays;
  String two(int v) => v.toString().padLeft(2, '0');
  if (diff <= 0) return '${two(time.hour)}:${two(time.minute)}';
  if (diff == 1) return '昨天';
  if (diff < 7) return '$diff 天前';
  if (time.year == now.year) return '${time.month}月${time.day}日';
  return '${time.year}/${time.month}/${time.day}';
}
